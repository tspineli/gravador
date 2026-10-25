import AppKit
import CoreGraphics
import GravadorCore

/// Decide se um navegador que está usando o microfone está numa reunião, pelo título das janelas.
/// Os títulos só ficam visíveis com a permissão de Gravação de Tela; sem ela, retorna `nil` sempre.
enum BrowserMeetingClassifier {
    static var hasWindowTitleAccess: Bool { CGPreflightScreenCaptureAccess() }

    @discardableResult
    static func requestWindowTitleAccess() -> Bool { CGRequestScreenCaptureAccess() }

    static func meeting(in browser: Browser) -> MeetingApp? {
        guard hasWindowTitleAccess else { return nil }
        let pids = Set(NSRunningApplication.runningApplications(withBundleIdentifier: browser.mainBundleID)
            .map(\.processIdentifier))
        guard !pids.isEmpty,
              let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }

        for window in windows {
            guard let owner = window[kCGWindowOwnerPID as String] as? pid_t, pids.contains(owner),
                  let title = window[kCGWindowName as String] as? String, !title.isEmpty else { continue }
            if let meeting = MeetingCatalog.meeting(forWindowTitle: title) { return meeting }
        }
        return nil
    }
}
