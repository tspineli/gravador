import Foundation
import GravadorCore

/// Chaves e valores padrão das Preferências (UserDefaults, usados também via @AppStorage).
enum Preferences {
    enum Key {
        static let autoStart = "autoStart"
        static let detectBrowsers = "detectBrowsers"
        static let voiceProcessing = "voiceProcessing"
        static let stopDelay = "stopDelaySeconds"
        /// Modelo da transcrição ao vivo (nome mantido por compatibilidade).
        static let selectedModel = "selectedModel"
        /// Modelo da revisão final. Vazio = revisão desligada; ausente = escolher automaticamente.
        static let refineModel = "refineModel"
        static let notifyOnAutoStart = "notifyOnAutoStart"
        static let microphoneUID = "microphoneUID"
        static func appEnabled(_ app: MeetingApp) -> String { "app.\(app.rawValue).enabled" }
        static func language(_ code: String) -> String { "language.\(code).enabled" }
    }

    static func registerDefaults() {
        var defaults: [String: Any] = [
            Key.autoStart: true,
            Key.detectBrowsers: true,
            Key.voiceProcessing: false,
            Key.stopDelay: 15.0,
            Key.notifyOnAutoStart: true,
        ]
        for app in MeetingApp.allCases { defaults[Key.appEnabled(app)] = true }
        for lang in LanguagePicker.supported { defaults[Key.language(lang.code)] = true }
        UserDefaults.standard.register(defaults: defaults)
    }

    private static var store: UserDefaults { .standard }

    static var autoStart: Bool { store.bool(forKey: Key.autoStart) }
    static var detectBrowsers: Bool { store.bool(forKey: Key.detectBrowsers) }
    static var voiceProcessing: Bool { store.bool(forKey: Key.voiceProcessing) }
    static var notifyOnAutoStart: Bool { store.bool(forKey: Key.notifyOnAutoStart) }
    static var stopDelay: TimeInterval { max(5, store.double(forKey: Key.stopDelay)) }

    /// `nil` (ou vazio) = entrada padrão do sistema.
    static var microphoneUID: String? {
        let uid = store.string(forKey: Key.microphoneUID)
        return uid?.isEmpty == false ? uid : nil
    }

    static var selectedModel: String? {
        get { store.string(forKey: Key.selectedModel) }
        set { store.set(newValue, forKey: Key.selectedModel) }
    }

    static var refineModel: String? {
        get { store.string(forKey: Key.refineModel) }
        set { store.set(newValue, forKey: Key.refineModel) }
    }

    static var enabledApps: Set<MeetingApp> {
        Set(MeetingApp.allCases.filter { store.bool(forKey: Key.appEnabled($0)) })
    }

    static var allowedLanguages: Set<String> {
        let codes = LanguagePicker.supported.map(\.code).filter { store.bool(forKey: Key.language($0)) }
        return codes.isEmpty ? ["pt"] : Set(codes)
    }
}
