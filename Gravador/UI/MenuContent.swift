import GravadorCore
import SwiftUI

struct MenuContent: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        switch state.status {
        case .recording(let label, _):
            Text("● Gravando \(label) — \(TimeFormatting.clock(state.elapsed))")
            Button("Parar e salvar") { state.stopManually(save: true) }
                .keyboardShortcut("s")
            Button("Parar e descartar") { state.stopManually(save: false) }
        case .starting:
            Text("Iniciando gravação…")
            Button("Cancelar") { state.stopManually(save: false) }
        case .finishing:
            Text("Finalizando transcrição…")
        case .idle:
            if let refinement = state.refinement {
                Text("Revisando transcrição… \(Int(refinement.progress * 100))%")
            }
            if let meeting = state.detectedMeeting {
                Text(state.isSuppressed ? "\(meeting.displayName) em andamento (pausado por você)" : "\(meeting.displayName) detectado")
            }
            Button("Iniciar gravação") { state.startManually() }
                .keyboardShortcut("r")
        }

        Divider()

        Button("Transcrição ao vivo…") { show(WindowID.live) }
            .keyboardShortcut("t")
        Button("Reuniões gravadas…") { show(WindowID.meetings) }
        if let folder = state.lastSavedFolder {
            Button("Abrir última reunião") { state.openInFinder(folder) }
        }

        Divider()

        modelStatus
        if let error = state.lastError {
            Text("⚠︎ \(error)")
        }

        Divider()

        Button("Configuração inicial…") { show(WindowID.setup) }
        SettingsLink { Text("Preferências…") }
            .keyboardShortcut(",")
        Button("Sair") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    @ViewBuilder
    private var modelStatus: some View {
        switch state.modelState {
        case .ready, .standby: Text("Transcrição local: pronta")
        case .loading: Text("Transcrição local: carregando modelo…")
        case .missing: Text("Transcrição: nenhum modelo instalado")
        case .failed(let message): Text("Transcrição: erro — \(message)")
        }
    }

    private func show(_ id: String) {
        openWindow(id: id)
        NSApp.activate(ignoringOtherApps: true)
    }
}
