import AVFoundation
import Foundation
import GravadorCore
import OSLog

/// Uma gravação em andamento: duas trilhas (mic = "Eu", sistema = "Outros") gravadas em arquivo
/// e transcritas em tempo real, trecho a trecho.
final class MeetingRecorder {
    struct Options {
        var voiceProcessing = false
        var microphoneUID: String?
        var allowedLanguages: Set<String> = ["pt", "en", "es"]
    }

    private static let log = Logger(subsystem: "com.tiagospineli.gravador", category: "recorder")

    let folder: URL
    let label: String
    let startedAt = Date()

    private let options: Options
    private let engine: (any TranscriptionEngine)?
    private let onSegment: @MainActor (TranscriptSegment) -> Void

    private var microphone: MicrophoneCapture?
    private let systemTap = SystemAudioTap()
    private var pipelines: [Track: TrackPipeline] = [:]
    private var transcriber: TranscriptionQueue?
    private var writer: TranscriptWriter?

    init(folder: URL, label: String, engine: (any TranscriptionEngine)?, options: Options,
         onSegment: @escaping @MainActor (TranscriptSegment) -> Void) {
        self.folder = folder
        self.label = label
        self.engine = engine
        self.options = options
        self.onSegment = onSegment
    }

    func start() async throws {
        guard await MicrophoneCapture.requestAccess() else {
            throw RecorderError.microphoneDenied
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let writer = try TranscriptWriter(folder: folder,
                                          title: MeetingFolderNaming.title(startedAt: startedAt, label: label),
                                          startedAt: startedAt)
        self.writer = writer

        let transcriber = TranscriptionQueue(engine: engine, allowedLanguages: options.allowedLanguages,
                                             writer: writer, onSegment: onSegment)
        self.transcriber = transcriber

        for track in Track.allCases {
            pipelines[track] = TrackPipeline(track: track,
                                             fileURL: folder.appendingPathComponent(track.rawValue),
                                             transcriber: transcriber)
        }

        let mic = MicrophoneCapture(voiceProcessing: options.voiceProcessing, deviceUID: options.microphoneUID)
        do {
            try mic.start { [weak self] buffer, _ in
                guard let copy = buffer.deepCopy() else { return }
                self?.pipelines[.microphone]?.consume(copy)
            }
            microphone = mic
            try systemTap.start { [weak self] buffer, _ in
                self?.pipelines[.system]?.consume(buffer)
            }
        } catch {
            mic.stop()
            systemTap.stop()
            throw error
        }
        Self.log.info("Gravação iniciada em \(self.folder.lastPathComponent, privacy: .public)")
    }

    /// Para a captura, termina de transcrever o que ficou na fila e fecha os arquivos.
    /// Com `save == false`, apaga a pasta da reunião.
    func stop(save: Bool) async {
        microphone?.stop()
        systemTap.stop()
        microphone = nil

        if !save {
            await transcriber?.cancel()
            for pipeline in pipelines.values { pipeline.discard() }
            try? FileManager.default.removeItem(at: folder)
            Self.log.info("Gravação descartada")
            return
        }

        for pipeline in pipelines.values { pipeline.flushSpeech() }
        await transcriber?.drain()
        for pipeline in pipelines.values { _ = await pipeline.finishFile() }
        let ended = Date()
        try? writer?.finish(endedAt: ended, duration: ended.timeIntervalSince(startedAt))
        writer = nil
        Self.log.info("Gravação salva em \(self.folder.lastPathComponent, privacy: .public)")
    }
}

enum RecorderError: LocalizedError {
    case microphoneDenied

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "Sem acesso ao microfone. Libere em Ajustes do Sistema › Privacidade e Segurança › Microfone."
        }
    }
}

/// Processamento de uma trilha fora da thread de áudio: grava o arquivo e corta a fala em trechos.
final class TrackPipeline {
    let track: Track
    private let queue: DispatchQueue
    private let file: AudioFileWriter
    private let resampler = ASRResampler()
    private var segmenter = SpeechSegmenter()
    private let transcriber: TranscriptionQueue
    private var discarded = false
    private var lastIdleReport: TimeInterval = 0

    init(track: Track, fileURL: URL, transcriber: TranscriptionQueue) {
        self.track = track
        self.queue = DispatchQueue(label: "gravador.track.\(track.rawValue)", qos: .userInitiated)
        // Sua voz em mono; o áudio do sistema em estéreo.
        self.file = AudioFileWriter(url: fileURL, maxChannels: track == .microphone ? 1 : 2)
        self.transcriber = transcriber
    }

    func consume(_ buffer: AVAudioPCMBuffer) {
        queue.async { [self] in
            guard !discarded else { return }
            file.write(buffer)
            let samples = resampler.convert(buffer)
            guard !samples.isEmpty else { return }
            for chunk in segmenter.append(samples) {
                transcriber.enqueue(track: track, chunk: chunk)
            }
            // Avisa que o sistema está em silêncio, para liberar trechos do microfone retidos.
            if track == .system, segmenter.isIdle, segmenter.processedDuration - lastIdleReport >= 0.5 {
                lastIdleReport = segmenter.processedDuration
                transcriber.systemIdle(until: segmenter.processedDuration)
            }
        }
    }

    func flushSpeech() {
        queue.sync {
            for chunk in segmenter.flush() {
                transcriber.enqueue(track: track, chunk: chunk)
            }
        }
    }

    func finishFile() async -> URL? {
        queue.sync {}
        return await file.finish()
    }

    func discard() {
        queue.sync { discarded = true }
    }
}

/// Fila única de transcrição para as duas trilhas: o modelo roda um trecho por vez.
/// O `EchoGate` segura os trechos do microfone até dar para saber se são eco do alto-falante.
final class TranscriptionQueue: @unchecked Sendable {
    private enum Job {
        case chunk(Track, SpeechChunk)
        case systemIdle(until: TimeInterval)
        case tick
    }

    private let continuation: AsyncStream<Job>.Continuation
    private var worker: Task<Void, Never>?
    private var ticker: Task<Void, Never>?

    init(engine: (any TranscriptionEngine)?, allowedLanguages: Set<String>, writer: TranscriptWriter,
         onSegment: @escaping @MainActor (TranscriptSegment) -> Void) {
        let (stream, continuation) = AsyncStream<Job>.makeStream()
        self.continuation = continuation

        worker = Task.detached(priority: .userInitiated) {
            let log = Logger(subsystem: "com.tiagospineli.gravador", category: "transcription")
            var gate = EchoGate()

            func publish(_ segments: [TranscriptSegment]) async {
                for segment in segments {
                    do { try writer.append(segment) } catch {
                        log.error("Falha ao gravar transcrição: \(error.localizedDescription, privacy: .public)")
                    }
                    await onSegment(segment)
                }
            }

            for await job in stream {
                if Task.isCancelled { break }
                switch job {
                case .tick:
                    await publish(gate.tick(now: Date()))
                case .systemIdle(let until):
                    await publish(gate.systemIdle(until: until))
                case .chunk(let track, let chunk):
                    guard let engine else { continue }
                    do {
                        let output = try await engine.transcribe(chunk.samples, allowedLanguages: allowedLanguages)
                        guard let output else {
                            if track == .system { await publish(gate.systemIdle(until: chunk.end)) }
                            continue
                        }
                        let segment = TranscriptSegment(track: track, start: chunk.start, end: chunk.end,
                                                        language: output.language, text: output.text)
                        if track == .system {
                            await publish(gate.addSystem(segment))
                        } else {
                            await publish(gate.addMicrophone(segment, now: Date()))
                        }
                    } catch {
                        log.error("Falha ao transcrever trecho: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
            if !Task.isCancelled { await publish(gate.flush()) }
        }

        ticker = Task.detached {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                continuation.yield(.tick)
            }
        }
    }

    func enqueue(track: Track, chunk: SpeechChunk) {
        continuation.yield(.chunk(track, chunk))
    }

    func systemIdle(until: TimeInterval) {
        continuation.yield(.systemIdle(until: until))
    }

    /// Termina tudo o que está na fila (inclusive trechos do microfone retidos) e encerra.
    func drain() async {
        ticker?.cancel()
        continuation.finish()
        await worker?.value
    }

    func cancel() async {
        ticker?.cancel()
        worker?.cancel()
        continuation.finish()
        await worker?.value
    }
}
