import Foundation

/// Janela de áudio para a revisão final: várias falas seguidas do mesmo idioma, com as pausas
/// entre elas preenchidas com silêncio, para o Whisper ter contexto e as emendas não cortarem palavras.
public struct RefinementWindow: Sendable, Equatable {
    public let startSample: Int
    public let samples: [Float]
    public let sampleRate: Double
    public let language: String

    public var start: TimeInterval { Double(startSample) / sampleRate }
    public var end: TimeInterval { Double(startSample + samples.count) / sampleRate }
}

/// Agrupa os trechos do `SpeechSegmenter` em janelas de até ~28 s (o Whisper processa 30 s por vez).
/// Só junta trechos do mesmo idioma: com o idioma fixo, o Whisper traduziria a parte no outro idioma.
public struct RefinementWindowBuilder: Sendable {
    public struct Configuration: Sendable {
        public var maxWindow: TimeInterval = 28
        /// Pausa máxima entre duas falas da mesma janela.
        public var maxGap: TimeInterval = 2.5

        public init() {}
    }

    public let config: Configuration
    private var current: (startSample: Int, samples: [Float], sampleRate: Double, language: String)?

    public init(config: Configuration = Configuration()) {
        self.config = config
    }

    /// Adiciona um trecho e devolve a janela que ficou completa, se houver.
    public mutating func add(_ chunk: SpeechChunk, language: String) -> [RefinementWindow] {
        var output: [RefinementWindow] = []
        if var window = current {
            let windowEnd = window.startSample + window.samples.count
            let gap = chunk.startSample - windowEnd
            let total = chunk.startSample + chunk.samples.count - window.startSample
            let fits = window.language == language
                && gap >= 0
                && Double(gap) / chunk.sampleRate <= config.maxGap
                && Double(total) / chunk.sampleRate <= config.maxWindow
            if fits {
                window.samples.append(contentsOf: repeatElement(0, count: gap))
                window.samples.append(contentsOf: chunk.samples)
                current = window
                return []
            }
            output.append(RefinementWindow(startSample: window.startSample, samples: window.samples,
                                           sampleRate: window.sampleRate, language: window.language))
        }
        current = (chunk.startSample, chunk.samples, chunk.sampleRate, language)
        return output
    }

    public mutating func flush() -> [RefinementWindow] {
        defer { current = nil }
        guard let window = current else { return [] }
        return [RefinementWindow(startSample: window.startSample, samples: window.samples,
                                 sampleRate: window.sampleRate, language: window.language)]
    }
}

public enum TranscriptMerge {
    /// Junta as trilhas em ordem cronológica, descartando falas do microfone que são eco do sistema.
    public static func merge(microphone: [TranscriptSegment], system: [TranscriptSegment]) -> [TranscriptSegment] {
        let kept = microphone.filter { !TranscriptFilters.isEcho($0, of: system) }
        return (kept + system).sorted { $0.start < $1.start }
    }
}
