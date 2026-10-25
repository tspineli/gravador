import Foundation

/// Filtros aplicados ao texto que sai do Whisper antes de ir para a transcrição.
public enum TranscriptFilters {
    /// Frases que o Whisper costuma "alucinar" em silêncio ou ruído. Palavras curtas que
    /// alguém pode dizer de verdade ("obrigado", "tchau") ficam de fora de propósito.
    static let hallucinations: Set<String> = [
        "obrigado por assistir", "obrigada por assistir", "legendas pela comunidade amara.org",
        "thanks for watching", "thank you for watching", "you", "please subscribe",
        "subtitles by the amara.org community",
        "gracias por ver", "subtítulos realizados por la comunidad de amara.org",
        "♪", "música", "music", "silêncio", "silence",
    ]

    /// Remove marcações e espaços extras. Devolve `nil` se não sobrar nada útil.
    public static func clean(_ raw: String) -> String? {
        var text = raw
        // Tokens especiais que às vezes escapam (<|pt|>, <|endoftext|>...).
        text = text.replacingOccurrences(of: "<\\|[^|]*\\|>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if isHallucination(text) { return nil }
        return text
    }

    public static func isHallucination(_ text: String) -> Bool {
        let normalized = text.lowercased()
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        if normalized.isEmpty { return true }
        return hallucinations.contains(normalized) || hallucinations.contains(normalized + ".")
    }

    /// Sem fone, o microfone capta a voz dos outros que sai pelo alto-falante.
    /// Um trecho do microfone que coincide no tempo e no texto com um trecho do sistema é eco.
    public static func isEcho(_ mic: TranscriptSegment, of recentSystem: [TranscriptSegment], threshold: Double = 0.5) -> Bool {
        let micWords = words(mic.text)
        guard !micWords.isEmpty else { return false }
        for sys in recentSystem where sys.track == .system {
            let overlaps = sys.start < mic.end + 1.5 && mic.start < sys.end + 1.5
            guard overlaps else { continue }
            let sysWords = words(sys.text)
            let shared = micWords.intersection(sysWords).count
            // Fração das palavras do microfone que também apareceram no sistema.
            if Double(shared) / Double(micWords.count) >= threshold { return true }
        }
        return false
    }

    static func words(_ text: String) -> Set<String> {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return Set(folded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 1 })
    }
}
