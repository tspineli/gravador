import Foundation

/// Trilha de áudio gravada. O microfone é sempre "Eu"; o áudio do sistema são os demais participantes.
public enum Track: String, Codable, Sendable, CaseIterable {
    case microphone = "mic"
    case system = "sistema"

    public var speakerLabel: String {
        switch self {
        case .microphone: return "Eu"
        case .system: return "Outros"
        }
    }
}

/// Trecho transcrito, com tempos relativos ao início da gravação.
public struct TranscriptSegment: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var track: Track
    public var start: TimeInterval
    public var end: TimeInterval
    public var language: String
    public var text: String

    public init(id: UUID = UUID(), track: Track, start: TimeInterval, end: TimeInterval, language: String, text: String) {
        self.id = id
        self.track = track
        self.start = start
        self.end = end
        self.language = language
        self.text = text
    }
}

/// Aplicativo de reunião reconhecido.
public enum MeetingApp: String, Codable, Sendable, CaseIterable, Identifiable {
    case zoom
    case teams
    case meet
    case webex
    case slack

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .zoom: return "Zoom"
        case .teams: return "Teams"
        case .meet: return "Google Meet"
        case .webex: return "Webex"
        case .slack: return "Slack"
        }
    }
}

public enum TimeFormatting {
    /// `mm:ss`, ou `h:mm:ss` a partir de uma hora.
    public static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}
