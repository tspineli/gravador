import Foundation

/// Restringe a detecção de idioma do Whisper aos idiomas permitidos nas Preferências.
/// Evita, por exemplo, que português seja reconhecido como galego.
public enum LanguagePicker {
    public static let supported: [(code: String, name: String)] = [
        ("pt", "Português"),
        ("en", "Inglês"),
        ("es", "Espanhol"),
    ]

    public static func pick(probabilities: [String: Float], allowed: Set<String>, fallback: String) -> String {
        let candidates = probabilities.filter { allowed.contains($0.key) }
        return candidates.max(by: { $0.value < $1.value })?.key ?? fallback
    }
}
