import Foundation

struct TranscriptionOutput {
    let text: String
    let language: String
}

/// Trecho com tempo relativo ao início do áudio enviado.
struct TimedText {
    let start: TimeInterval
    let end: TimeInterval
    let text: String
}

/// Motor de reconhecimento de fala. Atrás de um protocolo para poder trocar o Whisper por outro
/// (ex.: Parakeet via FluidAudio) sem mexer no resto do pipeline.
protocol TranscriptionEngine: Actor {
    var isReady: Bool { get }
    func load() async throws
    /// Libera a memória do modelo. Uma chamada seguinte a `transcribe` carrega de novo.
    func unload() async
    /// Ao vivo. `samples`: 16 kHz mono. `allowedLanguages`: códigos ISO 639-1; um único código fixa o idioma.
    func transcribe(_ samples: [Float], allowedLanguages: Set<String>) async throws -> TranscriptionOutput?
    func detectLanguage(_ samples: [Float], allowedLanguages: Set<String>) async throws -> String
    /// Revisão: até 30 s de áudio num idioma já conhecido, com o texto anterior como contexto.
    func transcribeTimed(_ samples: [Float], language: String, previousText: String?) async throws -> [TimedText]
}
