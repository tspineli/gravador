import AVFoundation
import GravadorCore
import SwiftUI

struct SettingsView: View {
    enum Tab: Hashable {
        case general, transcription, storage, privacy
    }

    @State private var selection: Tab
    private let height: CGFloat

    init(tab: Tab = .general, height: CGFloat = 460) {
        _selection = State(initialValue: tab)
        self.height = height
    }

    var body: some View {
        TabView(selection: $selection) {
            GeneralSettings().tabItem { Label("Geral", systemImage: "gearshape") }.tag(Tab.general)
            TranscriptionSettings().tabItem { Label("Transcrição", systemImage: "text.bubble") }.tag(Tab.transcription)
            StorageSettings().tabItem { Label("Armazenamento", systemImage: "folder") }.tag(Tab.storage)
            PrivacySettings().tabItem { Label("Privacidade", systemImage: "lock.shield") }.tag(Tab.privacy)
        }
        .frame(width: 560, height: height)
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }
}

private struct GeneralSettings: View {
    @EnvironmentObject private var state: AppState
    @AppStorage(Preferences.Key.autoStart) private var autoStart = true
    @AppStorage(Preferences.Key.detectBrowsers) private var detectBrowsers = true
    @AppStorage(Preferences.Key.stopDelay) private var stopDelay = 15.0
    @AppStorage(Preferences.Key.notifyOnAutoStart) private var notifyOnAutoStart = true
    @State private var hasTitleAccess = BrowserMeetingClassifier.hasWindowTitleAccess

    var body: some View {
        Form {
            Section {
                Toggle("Iniciar a gravação automaticamente ao detectar uma reunião", isOn: $autoStart)
                Toggle("Avisar com notificação quando começar a gravar sozinho", isOn: $notifyOnAutoStart)
                    .disabled(!autoStart)
                LabeledContent("Encerrar após o microfone ficar livre por") {
                    Stepper("\(Int(stopDelay)) s", value: $stopDelay, in: 5...120, step: 5)
                }
                .disabled(!autoStart)
            } footer: {
                FooterText("Parar manualmente durante uma reunião impede que ela volte a gravar sozinha até você sair da chamada.")
            }

            Section("Apps monitorados") {
                ForEach(MeetingApp.allCases) { app in
                    AppToggle(app: app)
                }
            }

            Section {
                Toggle("Detectar reuniões no navegador (Meet, Teams e Zoom web)", isOn: $detectBrowsers)
                HStack {
                    Image(systemName: hasTitleAccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(hasTitleAccess ? .green : .orange)
                    Text(hasTitleAccess
                         ? "Leitura dos títulos de janela liberada: reuniões web iniciam sozinhas."
                         : "Sem acesso aos títulos de janela: no navegador você recebe uma notificação para confirmar.")
                    Spacer()
                    if !hasTitleAccess {
                        Button("Permitir…") {
                            BrowserMeetingClassifier.requestWindowTitleAccess()
                            hasTitleAccess = BrowserMeetingClassifier.hasWindowTitleAccess
                        }
                    }
                }
                .font(.callout)
            } footer: {
                FooterText("A permissão aparece como \"Gravação de Tela\", mas só é usada para ler o título das janelas do navegador. Nenhuma imagem da tela é capturada.")
            }

            Section {
                Toggle("Abrir ao iniciar sessão no Mac", isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.launchAtLogin = $0 }
                ))
            }
        }
        .formStyle(.grouped)
        .onAppear { hasTitleAccess = BrowserMeetingClassifier.hasWindowTitleAccess }
    }
}

private struct AppToggle: View {
    let app: MeetingApp
    @AppStorage private var enabled: Bool

    init(app: MeetingApp) {
        self.app = app
        _enabled = AppStorage(wrappedValue: true, Preferences.Key.appEnabled(app))
    }

    var body: some View {
        Toggle(app.displayName, isOn: $enabled)
    }
}

private struct TranscriptionSettings: View {
    @EnvironmentObject private var state: AppState
    @AppStorage(Preferences.Key.voiceProcessing) private var voiceProcessing = false
    @AppStorage(Preferences.Key.selectedModel) private var selectedModel = ""
    @AppStorage(Preferences.Key.microphoneUID) private var microphoneUID = ""
    @State private var inputDevices: [InputDevice] = []

    var body: some View {
        Form {
            Section {
                if state.installedModels.isEmpty {
                    Text("Nenhum modelo instalado. Rode `scripts/fetch-model.sh` no Terminal e importe a pasta baixada.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Modelo", selection: Binding(
                        get: { selectedModel },
                        set: { state.selectModel($0) }
                    )) {
                        ForEach(state.installedModels, id: \.self) { Text($0).tag($0) }
                    }
                }
                HStack {
                    modelStatus
                    Spacer()
                    if state.importingModel {
                        ProgressView().controlSize(.small)
                        Text("Importando…")
                    } else {
                        Button("Importar modelo…") { state.importModel() }
                    }
                }
            } header: {
                Text("Modelo (Whisper, roda no próprio Mac)")
            }

            Section {
                ForEach(LanguagePicker.supported, id: \.code) { lang in
                    LanguageToggle(code: lang.code, name: lang.name)
                }
            } header: {
                Text("Idiomas das reuniões")
            } footer: {
                FooterText("O idioma é detectado a cada fala entre os marcados. Marcar só um fixa o idioma e deixa a transcrição mais rápida.")
            }

            Section {
                Picker("Microfone (sua voz)", selection: $microphoneUID) {
                    Text("Padrão do sistema").tag("")
                    ForEach(inputDevices) { Text($0.name).tag($0.uid) }
                }
                Toggle("Cancelamento de eco no microfone", isOn: $voiceProcessing)
            } header: {
                Text("Microfone")
            } footer: {
                FooterText("Útil sem fone de ouvido, quando o microfone capta a voz dos outros pelo alto-falante. O app também descarta falas repetidas entre as trilhas. Use o mesmo microfone configurado no Zoom/Teams/Meet. Vale a partir da próxima gravação.")
            }
        }
        .formStyle(.grouped)
        .onAppear { inputDevices = Screenshots.demoInputDevices ?? AudioObjects.inputDevices() }
    }

    @ViewBuilder
    private var modelStatus: some View {
        switch state.modelState {
        case .ready: Label("Pronto", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .loading: Label("Carregando (a 1ª vez pode levar minutos)…", systemImage: "hourglass")
        case .missing: Label("Sem modelo", systemImage: "xmark.circle").foregroundStyle(.secondary)
        case .failed(let message): Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }
}

private struct LanguageToggle: View {
    let name: String
    @AppStorage private var enabled: Bool

    init(code: String, name: String) {
        self.name = name
        _enabled = AppStorage(wrappedValue: true, Preferences.Key.language(code))
    }

    var body: some View {
        Toggle(name, isOn: $enabled)
    }
}

private struct StorageSettings: View {
    @EnvironmentObject private var state: AppState
    @State private var path = ""

    var body: some View {
        Form {
            Section {
                LabeledContent("Pasta das reuniões") {
                    Text(path).truncationMode(.middle).lineLimit(1)
                }
                HStack {
                    Button("Escolher pasta…") {
                        state.outputFolder.choose()
                        path = state.outputFolder.displayPath
                    }
                    if let url = state.outputFolder.url {
                        Button("Mostrar no Finder") { state.openInFinder(url) }
                    }
                }
            } footer: {
                FooterText("Cada reunião vira uma pasta com mic.m4a (você), sistema.m4a (os outros), transcricao.md e transcricao.jsonl. Sem pasta escolhida, as gravações ficam dentro do container do app.")
            }
        }
        .formStyle(.grouped)
        .onAppear { path = state.outputFolder.displayPath }
    }
}

private struct PrivacySettings: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            Section {
                Label("O app não tem permissão de acesso à rede (sandbox sem network). Áudio, transcrição e arquivos nunca saem deste Mac.",
                      systemImage: "network.slash")
                Label("A transcrição roda com Whisper localmente, no Neural Engine.", systemImage: "cpu")
            }

            Section("Permissões") {
                PermissionRow(title: "Microfone", granted: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized)
                PermissionRow(title: "Títulos de janela (Gravação de Tela)", granted: BrowserMeetingClassifier.hasWindowTitleAccess)
                Text("Gravação de áudio do sistema: o macOS pede na primeira gravação (Privacidade e Segurança › Gravação de Tela e Áudio do Sistema).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Diagnóstico: usando o microfone agora") {
                if state.microphoneClients.isEmpty {
                    Text("Nenhum app").foregroundStyle(.secondary)
                } else {
                    ForEach(state.microphoneClients, id: \.self) { Text($0).font(.callout.monospaced()) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct PermissionRow: View {
    let title: String
    let granted: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(granted ? .green : .secondary)
        }
    }
}

/// Rodapé de seção alinhado à esquerda (no Form agrupado o padrão fica à direita).
private struct FooterText: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
