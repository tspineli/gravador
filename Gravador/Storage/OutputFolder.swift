import AppKit
import Foundation

/// Pasta onde as reuniões são salvas. No sandbox, o acesso fora do container exige que o usuário
/// escolha a pasta uma vez; guardamos um bookmark com escopo de segurança para as próximas vezes.
@MainActor
final class OutputFolder {
    private static let bookmarkKey = "outputFolderBookmark"
    private var accessed: URL?
    /// Usado só pelo modo `--screenshots`, para mostrar reuniões de exemplo.
    var overrideURL: URL?

    /// Pasta atual, ou `nil` se o usuário ainda não escolheu.
    var url: URL? {
        if let overrideURL { return overrideURL }
        if let accessed { return accessed }
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { return nil }
        guard url.startAccessingSecurityScopedResource() else { return nil }
        if stale { save(url) }
        accessed = url
        return url
    }

    var displayPath: String {
        if overrideURL != nil { return "~/Documents/Gravador Reuniões" }
        guard let url else { return "Não escolhida" }
        return (url.path as NSString).abbreviatingWithTildeInPath
    }

    /// Abre o seletor de pasta. Sugere ~/Documents/Gravador Reuniões.
    @discardableResult
    func choose() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Onde salvar as reuniões?"
        panel.message = "Escolha (ou crie) a pasta onde as gravações e transcrições serão salvas."
        panel.prompt = "Usar esta pasta"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let picked = panel.url else { return nil }
        accessed?.stopAccessingSecurityScopedResource()
        accessed = nil
        save(picked)
        return url
    }

    private func save(_ url: URL) {
        if let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        }
    }
}
