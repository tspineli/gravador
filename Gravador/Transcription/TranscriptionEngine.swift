import Foundation

struct TranscriptionOutput {
    let text: String
    let language: String
}

/// Motor de reconhecimento de fala. Atrás de um protocolo para poder trocar o Whisper por outro
/// (ex.: Parakeet via FluidAudio) sem mexer no resto do pipeline.
protocol TranscriptionEngine: Actor {
    var isReady: Bool { get }
    func load() async throws
    /// `samples`: 16 kHz mono. `allowedLanguages`: códigos ISO 639-1; um único código fixa o idioma.
    func transcribe(_ samples: [Float], allowedLanguages: Set<String>) async throws -> TranscriptionOutput?
}
