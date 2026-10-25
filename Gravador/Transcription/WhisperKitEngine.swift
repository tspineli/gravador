import Foundation
import GravadorCore
import OSLog
import WhisperKit

/// Whisper via WhisperKit (Core ML / Neural Engine), carregado só de uma pasta local.
/// `download: false` + sandbox sem rede: o modelo nunca é buscado na internet.
actor WhisperKitEngine: TranscriptionEngine {
    private static let log = Logger(subsystem: "com.tiagospineli.gravador", category: "whisper")

    let modelFolder: URL
    private var whisper: WhisperKit?
    private var loading: Task<WhisperKit, Error>?

    init(modelFolder: URL) {
        self.modelFolder = modelFolder
    }

    var isReady: Bool { whisper != nil }

    /// Carrega o modelo uma única vez, mesmo com chamadas concorrentes. A primeira carga depois
    /// de instalar (ou de uma atualização do macOS) compila o modelo para o chip e pode levar minutos.
    func load() async throws {
        if whisper != nil { return }
        if loading == nil {
            let folder = modelFolder
            loading = Task {
                let config = WhisperKitConfig(
                    modelFolder: folder.path,
                    tokenizerFolder: folder,
                    verbose: false,
                    logLevel: .error,
                    prewarm: false,
                    load: true,
                    download: false
                )
                return try await WhisperKit(config)
            }
        }
        let start = Date()
        do {
            whisper = try await loading!.value
            Self.log.info("Modelo pronto em \(Date().timeIntervalSince(start), format: .fixed(precision: 1))s")
        } catch {
            loading = nil
            throw error
        }
    }

    func unload() async {
        guard let whisper else { return }
        await whisper.unloadModels()
        self.whisper = nil
        loading = nil
        Self.log.info("Modelo liberado da memória")
    }

    private func loaded() async throws -> WhisperKit {
        if whisper == nil { try await load() }
        guard let whisper else { throw CancellationError() }
        return whisper
    }

    func detectLanguage(_ samples: [Float], allowedLanguages: Set<String>) async throws -> String {
        if allowedLanguages.count == 1, let only = allowedLanguages.first { return only }
        let detected = try await loaded().detectLangauge(audioArray: samples)
        return LanguagePicker.pick(probabilities: detected.langProbs,
                                   allowed: allowedLanguages.isEmpty ? ["pt", "en", "es"] : allowedLanguages,
                                   fallback: allowedLanguages.contains(detected.language) ? detected.language : "pt")
    }

    func transcribeTimed(_ samples: [Float], language: String, previousText: String?) async throws -> [TimedText] {
        let whisper = try await loaded()
        let prompt = previousText.flatMap { text in whisper.tokenizer?.encode(text: " " + text) }
        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            temperatureFallbackCount: 3,
            usePrefillPrompt: true,
            detectLanguage: false,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            promptTokens: prompt,
            suppressBlank: true,
            // O VAD já garante que há fala. Com o limiar padrão, um trecho que começa no meio
            // de uma frase tem a primeira palavra improvável e é descartado inteiro.
            firstTokenLogProbThreshold: nil
        )
        let results = try await whisper.transcribe(audioArray: samples, decodeOptions: options)
        return results.flatMap(\.segments).compactMap { segment in
            TranscriptFilters.clean(segment.text).map {
                TimedText(start: TimeInterval(segment.start), end: TimeInterval(segment.end), text: $0)
            }
        }
    }

    func transcribe(_ samples: [Float], allowedLanguages: Set<String>) async throws -> TranscriptionOutput? {
        let whisper = try await loaded()
        let language = try await detectLanguage(samples, allowedLanguages: allowedLanguages)

        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            temperatureFallbackCount: 3,
            usePrefillPrompt: true,
            detectLanguage: false,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            suppressBlank: true,
            // O VAD já garante que há fala. Com o limiar padrão, um trecho que começa no meio
            // de uma frase tem a primeira palavra improvável e é descartado inteiro.
            firstTokenLogProbThreshold: nil
        )
        let results = try await whisper.transcribe(audioArray: samples, decodeOptions: options)
        let text = results.map(\.text).joined(separator: " ")
        guard let cleaned = TranscriptFilters.clean(text) else { return nil }
        return TranscriptionOutput(text: cleaned, language: language)
    }
}
