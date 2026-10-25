import AVFoundation
import Foundation
import GravadorCore
import OSLog

/// Revisão final: depois da reunião, transcreve de novo as trilhas gravadas com janelas de até 28 s
/// (e, se configurado, com um modelo maior) e substitui a transcrição ao vivo, que fica guardada
/// como `transcricao-ao-vivo.md`. Uma marcação na pasta permite retomar a revisão depois de fechar o app.
enum TranscriptRefiner {
    struct Job: Codable {
        var title: String
        var startedAt: Date
        var endedAt: Date
        var duration: TimeInterval
    }

    static let markerName = ".revisao-pendente.json"
    static let liveMarkdownName = "transcricao-ao-vivo.md"
    static let liveJSONLName = "transcricao-ao-vivo.jsonl"
    private static let log = Logger(subsystem: "com.tiagospineli.gravador", category: "refine")

    // MARK: - Pendências

    static func markPending(folder: URL, job: Job) throws {
        try JSONEncoder().encode(job).write(to: folder.appendingPathComponent(markerName), options: .atomic)
    }

    static func pendingJob(in folder: URL) -> Job? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(markerName)) else { return nil }
        return try? JSONDecoder().decode(Job.self, from: data)
    }

    static func clearPending(in folder: URL) {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(markerName))
    }

    /// Reuniões com revisão pendente, da mais antiga para a mais nova.
    static func pendingFolders(in root: URL) -> [URL] {
        MeetingLibrary.meetings(in: root).map(\.folder).reversed().filter { pendingJob(in: $0) != nil }
    }

    static func audioFile(for track: Track, in folder: URL) -> URL? {
        ["m4a", "caf"].map { folder.appendingPathComponent(track.rawValue).appendingPathExtension($0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: - Revisão

    /// Revisa a reunião da pasta. `progress` vai de 0 a 1.
    static func refine(folder: URL, job: Job, engine: any TranscriptionEngine, modelName: String,
                       allowedLanguages: Set<String>, progress: @escaping @MainActor (Double) -> Void) async throws {
        let started = Date()
        let files = Track.allCases.compactMap { track in audioFile(for: track, in: folder).map { (track, $0) } }
        var byTrack: [Track: [TranscriptSegment]] = [:]
        for (index, (track, url)) in files.enumerated() {
            byTrack[track] = try await transcribe(track: track, file: url, engine: engine,
                                                  allowedLanguages: allowedLanguages) { fraction in
                progress((Double(index) + fraction) / Double(files.count))
            }
        }
        let merged = TranscriptMerge.merge(microphone: byTrack[.microphone] ?? [], system: byTrack[.system] ?? [])
        try Task.checkCancellation()

        // Nunca troca uma transcrição ao vivo com conteúdo por uma revisão vazia.
        if merged.isEmpty, !TranscriptWriter.readSegments(in: folder).isEmpty {
            log.error("Revisão sem nenhuma fala; mantendo a transcrição ao vivo")
            clearPending(in: folder)
            return
        }

        let fm = FileManager.default
        let temporary = folder.appendingPathComponent(".revisao", isDirectory: true)
        try? fm.removeItem(at: temporary)
        let writer = try TranscriptWriter(folder: temporary, title: job.title, startedAt: job.startedAt)
        for segment in merged { try writer.append(segment) }
        try writer.finish(endedAt: job.endedAt, duration: job.duration,
                          note: "Transcrição revisada ao final com \(modelName). A versão ao vivo está em \(liveMarkdownName).")

        for (name, liveName) in [(TranscriptWriter.markdownName, liveMarkdownName),
                                 (TranscriptWriter.jsonlName, liveJSONLName)] {
            let current = folder.appendingPathComponent(name)
            let live = folder.appendingPathComponent(liveName)
            if !fm.fileExists(atPath: live.path), fm.fileExists(atPath: current.path) {
                try fm.moveItem(at: current, to: live)
            } else {
                // Revisão refeita: a versão ao vivo já está guardada.
                try? fm.removeItem(at: current)
            }
            try fm.moveItem(at: temporary.appendingPathComponent(name), to: current)
        }
        try? fm.removeItem(at: temporary)
        clearPending(in: folder)
        log.info("Revisão concluída em \(Date().timeIntervalSince(started), format: .fixed(precision: 0))s: \(merged.count) falas")
    }

    /// Transcreve uma trilha inteira, lendo o arquivo em blocos para não carregar horas de áudio na memória.
    static func transcribe(track: Track, file url: URL, engine: any TranscriptionEngine, allowedLanguages: Set<String>,
                           progress: @escaping @MainActor (Double) -> Void) async throws -> [TranscriptSegment] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let total = max(1, Double(file.length))
        let blockSize = AVAudioFrameCount(format.sampleRate * 10)
        let resampler = ASRResampler()
        var segmenter = SpeechSegmenter()
        var builder = RefinementWindowBuilder()
        var segments: [TranscriptSegment] = []
        // Último texto de cada idioma, usado como contexto (nomes, termos, pontuação).
        var previousText: [String: String] = [:]

        func transcribe(_ windows: [RefinementWindow]) async throws {
            for window in windows {
                try Task.checkCancellation()
                let texts = try await engine.transcribeTimed(window.samples, language: window.language,
                                                             previousText: previousText[window.language])
                for text in texts {
                    var language = window.language
                    var text = text
                    // Uma pausa curta pode juntar falas de idiomas diferentes no mesmo trecho; com o idioma
                    // da janela, o Whisper traduziria a frase. Cada frase confere o próprio idioma.
                    let slice = Self.slice(window.samples, from: text.start - 0.2, to: text.end + 0.2, rate: window.sampleRate)
                    if allowedLanguages.count > 1, slice.count >= Int(window.sampleRate) {
                        let detected = try await engine.detectLanguage(slice, allowedLanguages: allowedLanguages)
                        if detected != language {
                            let redone = try await engine.transcribeTimed(slice, language: detected, previousText: nil)
                            if !redone.isEmpty {
                                language = detected
                                text = TimedText(start: text.start, end: text.end,
                                                 text: redone.map(\.text).joined(separator: " "))
                            }
                        }
                    }
                    segments.append(TranscriptSegment(track: track, start: window.start + text.start,
                                                      end: min(window.start + text.end, window.end),
                                                      language: language, text: text.text))
                }
                if !texts.isEmpty { previousText[window.language] = texts.map(\.text).joined(separator: " ") }
            }
        }

        func add(_ chunks: [SpeechChunk]) async throws {
            for chunk in chunks {
                let language = try await engine.detectLanguage(chunk.samples, allowedLanguages: allowedLanguages)
                try await transcribe(builder.add(chunk, language: language))
            }
        }

        while file.framePosition < file.length {
            try Task.checkCancellation()
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: blockSize) else { break }
            try file.read(into: buffer, frameCount: blockSize)
            if buffer.frameLength == 0 { break }
            try await add(segmenter.append(resampler.convert(buffer)))
            await progress(Double(file.framePosition) / total)
        }
        try await add(segmenter.flush())
        try await transcribe(builder.flush())
        return segments
    }

    private static func slice(_ samples: [Float], from start: TimeInterval, to end: TimeInterval, rate: Double) -> [Float] {
        let lower = max(0, Int(start * rate))
        let upper = min(samples.count, Int(end * rate))
        return lower < upper ? Array(samples[lower..<upper]) : []
    }
}
