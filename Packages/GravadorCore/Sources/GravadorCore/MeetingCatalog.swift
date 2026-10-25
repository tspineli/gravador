import Foundation

/// Navegador conhecido. `bundlePrefixes` cobre os processos auxiliares (ex.: `com.google.Chrome.helper`),
/// que são quem de fato abre o microfone.
public struct Browser: Hashable, Sendable {
    public let name: String
    /// Bundle ID do app principal (dono das janelas).
    public let mainBundleID: String
    public let bundlePrefixes: [String]

    public init(name: String, mainBundleID: String, bundlePrefixes: [String]) {
        self.name = name
        self.mainBundleID = mainBundleID
        self.bundlePrefixes = bundlePrefixes
    }
}

/// Resultado da classificação de um processo que está usando o microfone.
public enum AudioClientKind: Equatable, Sendable {
    case nativeMeeting(MeetingApp)
    case browser(Browser)
    case other
}

public enum MeetingCatalog {
    static let nativeApps: [(prefix: String, app: MeetingApp)] = [
        ("us.zoom.", .zoom),
        ("com.microsoft.teams", .teams),
        ("com.cisco.webex", .webex),
        ("cisco-systems.spark", .webex),
        ("com.tinyspeck.slackmacgap", .slack),
    ]

    public static let browsers: [Browser] = [
        Browser(name: "Chrome", mainBundleID: "com.google.Chrome", bundlePrefixes: ["com.google.chrome"]),
        Browser(name: "Edge", mainBundleID: "com.microsoft.edgemac", bundlePrefixes: ["com.microsoft.edgemac"]),
        Browser(name: "Brave", mainBundleID: "com.brave.Browser", bundlePrefixes: ["com.brave.browser"]),
        Browser(name: "Arc", mainBundleID: "company.thebrowser.Browser", bundlePrefixes: ["company.thebrowser."]),
        Browser(name: "Vivaldi", mainBundleID: "com.vivaldi.Vivaldi", bundlePrefixes: ["com.vivaldi.vivaldi"]),
        Browser(name: "Opera", mainBundleID: "com.operasoftware.Opera", bundlePrefixes: ["com.operasoftware.opera"]),
        Browser(name: "Firefox", mainBundleID: "org.mozilla.firefox", bundlePrefixes: ["org.mozilla.firefox", "org.mozilla.plugincontainer"]),
        // No Safari o microfone é aberto pelo processo GPU compartilhado do WebKit.
        Browser(name: "Safari", mainBundleID: "com.apple.Safari", bundlePrefixes: ["com.apple.safari", "com.apple.webkit."]),
    ]

    public static func classify(bundleID: String) -> AudioClientKind {
        let id = bundleID.lowercased()
        if let match = nativeApps.first(where: { id.hasPrefix($0.prefix) }) {
            return .nativeMeeting(match.app)
        }
        if let browser = browsers.first(where: { b in b.bundlePrefixes.contains(where: { id.hasPrefix($0) }) }) {
            return .browser(browser)
        }
        return .other
    }

    /// Identifica uma reunião pelo título da janela do navegador (aba ativa).
    public static func meeting(forWindowTitle title: String) -> MeetingApp? {
        let t = title.lowercased()
        if t.hasPrefix("meet - ") || t.hasPrefix("meet – ") || t.contains("google meet") || t.contains("meet.google.com") {
            return .meet
        }
        if t.contains("microsoft teams") || t.contains("teams.microsoft.com") || t.contains("teams.live.com") {
            return .teams
        }
        if t.contains("zoom") {
            return .zoom
        }
        if t.contains("webex") {
            return .webex
        }
        return nil
    }
}
