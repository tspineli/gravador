import AppKit
import UserNotifications

/// Notificações locais (UserNotifications é 100% local; nada passa por servidor).
@MainActor
final class NotificationController: NSObject, UNUserNotificationCenterDelegate {
    private enum ID {
        static let suggestCategory = "SUGGEST_RECORDING"
        static let savedCategory = "RECORDING_SAVED"
        static let recordAction = "RECORD"
        static let openAction = "OPEN_FOLDER"
    }

    var onRecordRequested: (() -> Void)?

    private var center: UNUserNotificationCenter { .current() }

    func setUp() {
        center.delegate = self
        let record = UNNotificationAction(identifier: ID.recordAction, title: "Gravar", options: [])
        let open = UNNotificationAction(identifier: ID.openAction, title: "Abrir pasta", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: ID.suggestCategory, actions: [record], intentIdentifiers: []),
            UNNotificationCategory(identifier: ID.savedCategory, actions: [open], intentIdentifiers: []),
        ])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func suggestRecording(browser: String) {
        post(title: "Reunião no \(browser)?",
             body: "O \(browser) está usando o microfone. Clique em Gravar para gravar e transcrever.",
             category: ID.suggestCategory)
    }

    func recordingStarted(label: String) {
        post(title: "Gravando reunião (\(label))",
             body: "A transcrição está rodando localmente. Use o menu ● na barra para parar.")
    }

    func recordingSaved(label: String, folder: URL, automatic: Bool) {
        post(title: automatic ? "Reunião encerrada (\(label))" : "Gravação salva (\(label))",
             body: folder.lastPathComponent, category: ID.savedCategory, userInfo: ["folder": folder.path])
    }

    func recordingFailed(message: String) {
        post(title: "Não foi possível gravar", body: message)
    }

    private func post(title: String, body: String, category: String? = nil, userInfo: [String: String] = [:]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = userInfo
        if let category { content.categoryIdentifier = category }
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let category = response.notification.request.content.categoryIdentifier
        let folder = response.notification.request.content.userInfo["folder"] as? String
        Task { @MainActor in
            if action == ID.recordAction || (action == UNNotificationDefaultActionIdentifier && category == ID.suggestCategory) {
                self.onRecordRequested?()
            } else if let folder, action == ID.openAction || action == UNNotificationDefaultActionIdentifier {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder)])
            }
            completionHandler()
        }
    }
}
