import Foundation
import GravadorCore
import OSLog

/// Junta o que está usando o microfone com o catálogo de apps e os títulos de janela dos navegadores.
@MainActor
final class MeetingDetector {
    struct Observation {
        var meetings: [MeetingApp] = []
        var unidentifiedBrowsers: Set<String> = []
        /// Bundle IDs usando o microfone (para o diagnóstico nas Preferências).
        var microphoneClients: [String] = []
    }

    private let log = Logger(subsystem: "com.tiagospineli.gravador", category: "detection")
    private var lastClients: [String] = []

    var enabledApps: Set<MeetingApp> = Set(MeetingApp.allCases)
    var detectBrowsers = true

    /// Navegadores já confirmados como reunião. Ficam confirmados enquanto mantiverem o microfone,
    /// mesmo que o usuário troque de aba (o título deixa de bater).
    private var confirmedBrowsers: [String: MeetingApp] = [:]

    func observe() -> Observation {
        let clients = AudioProcessMonitor.microphoneClients()
        var result = Observation()
        result.microphoneClients = Array(Set(clients.map { $0.bundleID.isEmpty ? "processo sem bundle (pid \($0.pid))" : $0.bundleID })).sorted()
        if result.microphoneClients != lastClients {
            lastClients = result.microphoneClients
            log.info("Usando o microfone: \(self.lastClients.joined(separator: ", "), privacy: .public)")
        }

        var activeBrowsers: [String: Browser] = [:]
        for client in clients {
            switch MeetingCatalog.classify(bundleID: client.bundleID) {
            case .nativeMeeting(let app):
                if enabledApps.contains(app), !result.meetings.contains(app) { result.meetings.append(app) }
            case .browser(let browser):
                activeBrowsers[browser.name] = browser
            case .other:
                break
            }
        }

        confirmedBrowsers = confirmedBrowsers.filter { activeBrowsers[$0.key] != nil }
        guard detectBrowsers else { return result }

        for (name, browser) in activeBrowsers.sorted(by: { $0.key < $1.key }) {
            let meeting = confirmedBrowsers[name] ?? BrowserMeetingClassifier.meeting(in: browser)
            if let meeting {
                confirmedBrowsers[name] = meeting
                if enabledApps.contains(meeting), !result.meetings.contains(meeting) { result.meetings.append(meeting) }
            } else {
                result.unidentifiedBrowsers.insert(name)
            }
        }
        return result
    }
}
