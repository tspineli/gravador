import AVFoundation
import GravadorCore

/// Autoteste do pipeline de transcrição dentro do sandbox, sem reunião:
/// `Gravador.app/Contents/MacOS/Gravador --selftest <áudio> [modelo]`
/// Lê o arquivo, corta com o SpeechSegmenter, transcreve com o WhisperKit e imprime as falas.
enum SelfTest {
    static var requestedFile: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--selftest"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static var requestedCaptureSeconds: Double? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--capture-test"), i + 1 < args.count else { return nil }
        return Double(args[i + 1])
    }

    /// Grava de verdade (mic + sistema) por alguns segundos e escreve o resultado em
    /// `<container>/tmp/capture-test.txt`. Rodar com `open Gravador.app --args --capture-test 20`
    /// para que as permissões sejam pedidas em nome do Gravador.
    @MainActor
    static func runCapture(seconds: Double) async -> Int32 {
        var report: [String] = []
        func note(_ line: String) { print("CAPTURE: \(line)"); report.append(line) }
        defer {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("capture-test.txt")
            try? report.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        }

        let engine = ModelStore.installedModels().last.map { WhisperKitEngine(modelFolder: ModelStore.folder(named: $0)) }
        try? await engine?.load()
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = MeetingFolderNaming.folder(in: docs.appendingPathComponent("Gravador Reuniões"),
                                                startedAt: Date(), label: "Teste de captura")
        var segments: [TranscriptSegment] = []
        let recorder = MeetingRecorder(folder: folder, label: "Teste de captura", engine: engine,
                                       options: .init(voiceProcessing: Preferences.voiceProcessing,
                                                      microphoneUID: Preferences.microphoneUID,
                                                      allowedLanguages: Preferences.allowedLanguages)) { segment in
            segments.append(segment)
            note("[\(TimeFormatting.clock(segment.start))] \(segment.track.speakerLabel) (\(segment.language)): \(segment.text)")
        }
        do {
            try await recorder.start()
            note("gravando \(Int(seconds))s em \(folder.path)")
            try await Task.sleep(for: .seconds(seconds))
            await recorder.stop(save: true)
            let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            for file in files.sorted() {
                let size = (try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent(file).path)[.size] as? Int) ?? 0
                note("arquivo \(file): \(size) bytes")
            }
            note("\(segments.count) trechos (eu: \(segments.filter { $0.track == .microphone }.count), outros: \(segments.filter { $0.track == .system }.count))")
            return 0
        } catch {
            note("erro: \(error.localizedDescription)")
            return 1
        }
    }

    static func run(file: String) async -> Int32 {
        do {
            let args = CommandLine.arguments
            let modelName = args.last.flatMap { ModelStore.installedModels().contains($0) ? $0 : nil }
                ?? ModelStore.installedModels().last
            guard let modelName else {
                print("SELFTEST: nenhum modelo em \(ModelStore.modelsRoot.path)")
                return 2
            }
            print("SELFTEST: modelo \(modelName)")
            let engine = WhisperKitEngine(modelFolder: ModelStore.folder(named: modelName))
            let loadStart = Date()
            try await engine.load()
            print(String(format: "SELFTEST: modelo carregado em %.1fs", Date().timeIntervalSince(loadStart)))

            let audio = try AVAudioFile(forReading: URL(fileURLWithPath: file))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat,
                                                frameCapacity: AVAudioFrameCount(audio.length)) else { return 3 }
            try audio.read(into: buffer)
            let samples = ASRResampler().convert(buffer)
            print(String(format: "SELFTEST: %.1fs de áudio", Double(samples.count) / 16_000))

            var segmenter = SpeechSegmenter()
            let chunks = segmenter.append(samples) + segmenter.flush()
            let start = Date()
            for chunk in chunks {
                let t0 = Date()
                let output = try await engine.transcribe(chunk.samples, allowedLanguages: Preferences.allowedLanguages)
                let line = output.map { "[\($0.language)] \($0.text)" } ?? "(vazio)"
                print(String(format: "SELFTEST: %@–%@ (%.2fs) %@", TimeFormatting.clock(chunk.start),
                             TimeFormatting.clock(chunk.end), Date().timeIntervalSince(t0), line))
            }
            print(String(format: "SELFTEST: %d trechos em %.1fs", chunks.count, Date().timeIntervalSince(start)))
            return 0
        } catch {
            print("SELFTEST: erro \(error)")
            return 1
        }
    }
}
