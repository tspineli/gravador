import Foundation

/// Trecho de fala pronto para transcrever (16 kHz mono).
public struct SpeechChunk: Sendable, Equatable {
    /// Posição do primeiro sample desde o início da trilha.
    public let startSample: Int
    public let samples: [Float]
    public let sampleRate: Double

    public var start: TimeInterval { Double(startSample) / sampleRate }
    public var end: TimeInterval { Double(startSample + samples.count) / sampleRate }
}

/// VAD por energia: acumula áudio e corta em pausas de fala (ou num tamanho máximo),
/// para mandar à transcrição trechos curtos e com contexto completo.
public struct SpeechSegmenter: Sendable {
    public struct Configuration: Sendable {
        public var sampleRate: Double = 16_000
        public var frameDuration: TimeInterval = 0.03
        /// Pausa que encerra um trecho.
        public var silenceToCut: TimeInterval = 0.6
        /// Trechos com menos fala que isso são descartados (cliques, ruído).
        public var minSpeech: TimeInterval = 0.3
        /// Corte forçado para não atrasar demais a transcrição.
        public var maxChunk: TimeInterval = 25
        /// Áudio mantido antes do início detectado da fala.
        public var preRoll: TimeInterval = 0.3
        /// Nível mínimo (RMS linear) para considerar fala, independentemente do ruído de fundo.
        public var absoluteThreshold: Float = 0.006
        /// Quantas vezes acima do ruído de fundo o RMS precisa estar.
        public var noiseMultiplier: Float = 3.0

        public init() {}
    }

    public let config: Configuration
    private let frameSize: Int
    private var pending: [Float] = []
    /// Índice (em samples) do início de `pending`.
    private var pendingStart = 0
    private var noiseFloor: Float = 0.002

    private var inSpeech = false
    private var chunk: [Float] = []
    private var chunkStart = 0
    private var speechFrames = 0
    private var silentFrames = 0
    private var preRollBuffer: [Float] = []

    public init(config: Configuration = Configuration()) {
        self.config = config
        self.frameSize = max(1, Int(config.sampleRate * config.frameDuration))
    }

    private var silenceFramesToCut: Int { Int((config.silenceToCut / config.frameDuration).rounded()) }
    private var minSpeechFrames: Int { Int((config.minSpeech / config.frameDuration).rounded()) }
    private var maxChunkSamples: Int { Int(config.maxChunk * config.sampleRate) }
    private var preRollSamples: Int { Int(config.preRoll * config.sampleRate) }

    /// Sem fala em andamento: todo o áudio até `processedDuration` já foi entregue em trechos.
    public var isIdle: Bool { !inSpeech }

    /// Duração de áudio já analisada desde o início da trilha.
    public var processedDuration: TimeInterval { Double(pendingStart) / config.sampleRate }

    /// Adiciona áudio e devolve os trechos que ficaram completos.
    public mutating func append(_ samples: [Float]) -> [SpeechChunk] {
        pending.append(contentsOf: samples)
        var output: [SpeechChunk] = []
        var offset = 0
        while pending.count - offset >= frameSize {
            let frame = Array(pending[offset..<(offset + frameSize)])
            let frameStart = pendingStart + offset
            if let done = process(frame: frame, at: frameStart) { output.append(done) }
            offset += frameSize
        }
        pending.removeFirst(offset)
        pendingStart += offset
        return output
    }

    /// Encerra a trilha, devolvendo o trecho em andamento (se tiver fala suficiente).
    public mutating func flush() -> [SpeechChunk] {
        if !pending.isEmpty, inSpeech { chunk.append(contentsOf: pending) }
        pendingStart += pending.count
        pending.removeAll()
        let result = finishChunk()
        return result.map { [$0] } ?? []
    }

    private mutating func process(frame: [Float], at frameStart: Int) -> SpeechChunk? {
        let rms = Self.rms(frame)
        let threshold = max(config.absoluteThreshold, noiseFloor * config.noiseMultiplier)
        let isSpeech = rms > threshold

        if !isSpeech {
            // Ruído de fundo segue lentamente o nível dos frames sem fala.
            noiseFloor = noiseFloor * 0.98 + rms * 0.02
        }

        if !inSpeech {
            if isSpeech {
                inSpeech = true
                chunk = preRollBuffer + frame
                chunkStart = frameStart - preRollBuffer.count
                speechFrames = 1
                silentFrames = 0
                preRollBuffer.removeAll()
            } else {
                preRollBuffer.append(contentsOf: frame)
                if preRollBuffer.count > preRollSamples {
                    preRollBuffer.removeFirst(preRollBuffer.count - preRollSamples)
                }
            }
            return nil
        }

        chunk.append(contentsOf: frame)
        if isSpeech {
            speechFrames += 1
            silentFrames = 0
        } else {
            silentFrames += 1
        }

        if silentFrames >= silenceFramesToCut {
            return finishChunk()
        }
        if chunk.count >= maxChunkSamples {
            // Corte forçado no meio da fala: o próximo trecho começa logo em seguida.
            let done = finishChunk()
            inSpeech = true
            chunkStart = frameStart + frameSize
            return done
        }
        return nil
    }

    private mutating func finishChunk() -> SpeechChunk? {
        defer {
            inSpeech = false
            chunk.removeAll()
            speechFrames = 0
            silentFrames = 0
        }
        guard inSpeech, speechFrames >= minSpeechFrames, !chunk.isEmpty else { return nil }
        // Remove a cauda de silêncio, mantendo um pouco para não cortar a última palavra.
        let tail = max(0, silentFrames - 5) * frameSize
        let samples = Array(chunk.dropLast(min(tail, chunk.count)))
        return SpeechChunk(startSample: max(0, chunkStart), samples: samples, sampleRate: config.sampleRate)
    }

    static func rms(_ frame: [Float]) -> Float {
        guard !frame.isEmpty else { return 0 }
        var sum: Float = 0
        for s in frame { sum += s * s }
        return (sum / Float(frame.count)).squareRoot()
    }
}
