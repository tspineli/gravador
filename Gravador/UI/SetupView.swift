import AVFoundation
import SwiftUI

/// Configuração inicial: pasta de saída, modelo de transcrição e permissões.
struct SetupView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var folderPath = ""
    @State private var micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var titleAccess = BrowserMeetingClassifier.hasWindowTitleAccess

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Gravador de Reuniões").font(.title.bold())
                Text("Grava e transcreve suas reuniões 100% no seu Mac. Nada é enviado para a internet.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            step(1, done: state.outputFolder.url != nil, title: "Pasta das reuniões",
                 detail: state.outputFolder.url == nil ? "Onde salvar áudio e transcrições." : folderPath) {
                Button(state.outputFolder.url == nil ? "Escolher…" : "Trocar…") {
                    state.outputFolder.choose()
                    folderPath = state.outputFolder.displayPath
                }
            }

            step(2, done: !state.installedModels.isEmpty, title: "Modelo de transcrição",
                 detail: modelDetail) {
                if state.importingModel {
                    ProgressView().controlSize(.small)
                } else {
                    Button(state.installedModels.isEmpty ? "Importar…" : "Outro…") { state.importModel() }
                }
            }

            step(3, done: micStatus == .authorized, title: "Microfone",
                 detail: micStatus == .denied ? "Negado: libere em Ajustes do Sistema › Privacidade › Microfone." : "Para gravar a sua voz.") {
                if micStatus == .notDetermined {
                    Button("Permitir…") {
                        Task {
                            _ = await MicrophoneCapture.requestAccess()
                            micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                        }
                    }
                }
            }

            step(4, done: titleAccess, title: "Reuniões no navegador (opcional)",
                 detail: "Permissão \"Gravação de Tela\" só para ler o título das abas (Meet/Teams/Zoom web). Sem ela, você confirma por notificação.") {
                if !titleAccess {
                    Button("Permitir…") {
                        BrowserMeetingClassifier.requestWindowTitleAccess()
                        titleAccess = BrowserMeetingClassifier.hasWindowTitleAccess
                    }
                }
            }

            Text("O áudio do sistema (a voz dos outros) é autorizado pelo macOS na primeira gravação.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Concluir") { dismissWindow(id: WindowID.setup) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 540)
        .onAppear {
            folderPath = state.outputFolder.displayPath
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private var modelDetail: String {
        if let error = state.lastError, state.installedModels.isEmpty { return error }
        if state.installedModels.isEmpty {
            return "Rode scripts/fetch-model.sh no Terminal (download único, ~2,2 GB) e importe as duas pastas baixadas."
        }
        return state.installedModels.joined(separator: ", ")
    }

    private func step<Action: View>(_ number: Int, done: Bool, title: String, detail: String,
                                    @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle")
                .font(.title2)
                .foregroundStyle(done ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            action()
        }
    }
}
