import AppKit
import Combine
import GravadorCore
import OSLog
import ServiceManagement
import UserNotifications

/// Estado central do app: liga detecção → máquina de estados → gravador, e expõe tudo para a UI.
@MainActor
final class AppState: ObservableObject {
    enum Status: Equatable {
        case idle
        case starting
        case recording(label: String, startedAt: Date)
        case finishing
    }

    enum ModelState: Equatable {
        case missing
        case loading
        case ready
        case failed(String)
    }

    static let shared = AppState()

    @Published private(set) var status: Status = .idle
    @Published private(set) var liveSegments: [TranscriptSegment] = []
    @Published private(set) var modelState: ModelState = .missing
    @Published private(set) var installedModels: [String] = []
    @Published private(set) var lastError: String?
    @Published private(set) var lastSavedFolder: URL?
    @Published private(set) var microphoneClients: [String] = []
    @Published private(set) var detectedMeeting: MeetingApp?
    @Published private(set) var isSuppressed = false
    @Published private(set) var importingModel = false
    @Published private(set) var now = Date()

    let outputFolder = OutputFolder()

    private let log = Logger(subsystem: "com.tiagospineli.gravador", category: "app")
    private let detector = MeetingDetector()
    private var stateMachine = RecordingStateMachine()
    private var recorder: MeetingRecorder?
    private var engine: WhisperKitEngine?
    private var timer: Timer?
    private let notifications = NotificationController()

    private init() {}

    var isRecording: Bool {
        if case .recording = status { return true }
        return false
    }

    var elapsed: TimeInterval {
        if case .recording(_, let startedAt) = status { return now.timeIntervalSince(startedAt) }
        return 0
    }

    // MARK: - Ciclo de vida

    func launch() {
        Preferences.registerDefaults()
        notifications.onRecordRequested = { [weak self] in self?.startManually() }
        notifications.setUp()
        refreshModels()
        loadSelectedModel()

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer?.tolerance = 0.2
        tick()
    }

    private func tick() {
        now = Date()
        detector.enabledApps = Preferences.enabledApps
        detector.detectBrowsers = Preferences.detectBrowsers
        stateMachine.autoStartEnabled = Preferences.autoStart
        stateMachine.policy.stopDelay = Preferences.stopDelay

        let observation = detector.observe()
        microphoneClients = observation.microphoneClients
        let actions = stateMachine.observe(now: now, meetings: observation.meetings,
                                           unidentifiedBrowsers: observation.unidentifiedBrowsers)
        detectedMeeting = stateMachine.currentMeeting
        isSuppressed = stateMachine.isSuppressed
        perform(actions, save: true)
    }

    // MARK: - Ações do usuário

    func startManually() {
        perform(stateMachine.manualStart(), save: true)
    }

    func stopManually(save: Bool) {
        perform(stateMachine.manualStop(), save: save)
        isSuppressed = stateMachine.isSuppressed
    }

    private func perform(_ actions: [RecordingStateMachine.Action], save: Bool) {
        for action in actions {
            switch action {
            case .start(let origin):
                beginRecording(origin: origin)
            case .stop(let reason):
                endRecording(save: save, reason: reason)
            case .suggest(let browser):
                notifications.suggestRecording(browser: browser)
            }
        }
    }

    // MARK: - Gravação

    private func beginRecording(origin: RecordingStateMachine.Origin) {
        let label: String
        switch origin {
        case .manual: label = detectedMeeting?.displayName ?? "Manual"
        case .automatic(let app): label = app.displayName
        }

        let root = outputFolder.url ?? fallbackFolder()
        let startedAt = Date()
        let folder = MeetingFolderNaming.folder(in: root, startedAt: startedAt, label: label)
        let options = MeetingRecorder.Options(voiceProcessing: Preferences.voiceProcessing,
                                              microphoneUID: Preferences.microphoneUID,
                                              allowedLanguages: Preferences.allowedLanguages)
        let recorder = MeetingRecorder(folder: folder, label: label, engine: engine, options: options) { [weak self] segment in
            self?.append(segment)
        }
        self.recorder = recorder
        liveSegments = []
        lastError = nil
        status = .starting

        Task {
            do {
                try await recorder.start()
                guard self.recorder === recorder else {
                    // Parado enquanto ainda iniciava: descarta o pouco que foi capturado.
                    await recorder.stop(save: false)
                    return
                }
                status = .recording(label: label, startedAt: recorder.startedAt)
                if case .automatic = origin, Preferences.notifyOnAutoStart {
                    notifications.recordingStarted(label: label)
                }
                if engine == nil {
                    lastError = "Gravando só o áudio: nenhum modelo de transcrição instalado (Preferências › Transcrição)."
                }
            } catch {
                log.error("Falha ao iniciar: \(error.localizedDescription, privacy: .public)")
                await recorder.stop(save: false)
                self.recorder = nil
                stateMachine.recordingFailed()
                status = .idle
                lastError = error.localizedDescription
                notifications.recordingFailed(message: error.localizedDescription)
            }
        }
    }

    private func endRecording(save: Bool, reason: RecordingStateMachine.StopReason) {
        guard let recorder else { return }
        self.recorder = nil
        if status == .starting {
            // A tarefa de início percebe que foi cancelada e limpa sozinha.
            status = .idle
            return
        }
        status = .finishing
        Task {
            await recorder.stop(save: save)
            status = .idle
            if save {
                lastSavedFolder = recorder.folder
                notifications.recordingSaved(label: recorder.label, folder: recorder.folder, automatic: reason == .meetingEnded)
            }
        }
    }

    private func append(_ segment: TranscriptSegment) {
        let index = liveSegments.firstIndex { $0.start > segment.start } ?? liveSegments.endIndex
        liveSegments.insert(segment, at: index)
    }

    /// Sem pasta escolhida, salva dentro do container do app (e avisa nas Preferências).
    private func fallbackFolder() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Gravador Reuniões", isDirectory: true)
    }

    // MARK: - Modelo

    func refreshModels() {
        installedModels = ModelStore.installedModels()
        if Preferences.selectedModel == nil || !installedModels.contains(Preferences.selectedModel ?? "") {
            Preferences.selectedModel = installedModels.last
        }
    }

    func selectModel(_ name: String) {
        Preferences.selectedModel = name
        loadSelectedModel()
    }

    func loadSelectedModel() {
        guard let name = Preferences.selectedModel, installedModels.contains(name) else {
            engine = nil
            modelState = .missing
            return
        }
        let engine = WhisperKitEngine(modelFolder: ModelStore.folder(named: name))
        self.engine = engine
        modelState = .loading
        Task {
            do {
                try await engine.load()
                if self.engine === engine { modelState = .ready }
            } catch {
                if self.engine === engine { modelState = .failed(error.localizedDescription) }
            }
        }
    }

    func importModel() {
        let panel = NSOpenPanel()
        panel.title = "Importar modelo do Whisper"
        panel.message = "Escolha a pasta baixada pelo scripts/fetch-model.sh (ex.: openai_whisper-large-v3-v20240930_turbo)."
        panel.prompt = "Importar"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let source = panel.url else { return }

        importingModel = true
        lastError = nil
        Task.detached(priority: .userInitiated) {
            let result = Result { try ModelStore.importModel(from: source) }
            await MainActor.run {
                self.importingModel = false
                switch result {
                case .success(let name):
                    self.refreshModels()
                    self.selectModel(name)
                case .failure(let error):
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Modo de capturas de tela

    /// Preenche o estado com dados de exemplo para o modo `--screenshots` (documentação).
    func applyDemo(status: Status, segments: [TranscriptSegment], detected: MeetingApp?, suppressed: Bool,
                   models: [String], microphoneClients: [String]) {
        self.status = status
        liveSegments = segments
        detectedMeeting = detected
        isSuppressed = suppressed
        installedModels = models
        modelState = models.isEmpty ? .missing : .ready
        self.microphoneClients = microphoneClients
        now = Date()
    }

    // MARK: - Sistema

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                lastError = "Não foi possível alterar o início automático: \(error.localizedDescription)"
            }
            objectWillChange.send()
        }
    }

    func openInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
