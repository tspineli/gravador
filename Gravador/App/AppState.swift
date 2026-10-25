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
        /// Instalado e fora da memória: carrega ao começar a gravar.
        case standby
        case loading
        case ready
        case failed(String)
    }

    struct RefinementStatus: Equatable {
        let title: String
        var progress: Double
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
    @Published private(set) var refinement: RefinementStatus?
    /// Pasta da última reunião revisada (a lista de reuniões recarrega quando muda).
    @Published private(set) var lastRefinedFolder: URL?
    @Published private(set) var now = Date()

    let outputFolder = OutputFolder()

    private let log = Logger(subsystem: "com.tiagospineli.gravador", category: "app")
    private let detector = MeetingDetector()
    private var stateMachine = RecordingStateMachine()
    private var recorder: MeetingRecorder?
    /// Modelo da transcrição ao vivo: só fica na memória durante a gravação.
    private var engine: WhisperKitEngine?
    private var pendingRefinements: [URL] = []
    private var refineTask: Task<Void, Never>?
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
        pendingRefinements = TranscriptRefiner.pendingFolders(in: outputFolder.url ?? fallbackFolder())
        runPendingRefinements()

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
        // Uma revisão em andamento cede o Neural Engine à reunião e é retomada depois.
        refineTask?.cancel()
        let engine = makeLiveEngine()
        self.engine = engine
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
                    await release(engine)
                    runPendingRefinements()
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
                await release(engine)
                runPendingRefinements()
                lastError = error.localizedDescription
                notifications.recordingFailed(message: error.localizedDescription)
            }
        }
    }

    private func endRecording(save: Bool, reason: RecordingStateMachine.StopReason) {
        guard let recorder else { return }
        self.recorder = nil
        let engine = self.engine
        self.engine = nil
        if status == .starting {
            // A tarefa de início percebe que foi cancelada e limpa sozinha.
            status = .idle
            return
        }
        status = .finishing
        Task {
            await recorder.stop(save: save)
            await release(engine)
            status = .idle
            if save {
                lastSavedFolder = recorder.folder
                notifications.recordingSaved(label: recorder.label, folder: recorder.folder, automatic: reason == .meetingEnded)
                scheduleRefinement(of: recorder)
            }
            runPendingRefinements()
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

    /// Padrões: o menor modelo ao vivo (menos memória durante a reunião) e o maior na revisão final.
    func refreshModels() {
        installedModels = ModelStore.installedModels()
        let bySize = installedModels.map { ($0, ModelStore.size(named: $0)) }.sorted { $0.1 < $1.1 }.map(\.0)
        if !installedModels.contains(Preferences.selectedModel ?? "") {
            Preferences.selectedModel = bySize.first
        }
        if let refine = Preferences.refineModel, refine.isEmpty || installedModels.contains(refine) {
            // Escolha do usuário (inclusive "desligada").
        } else {
            Preferences.refineModel = bySize.last
        }
        if engine == nil { modelState = installedModels.isEmpty ? .missing : .standby }
    }

    func selectModel(_ name: String) {
        Preferences.selectedModel = name
    }

    /// `""` desliga a revisão final.
    func selectRefineModel(_ name: String) {
        Preferences.refineModel = name
        runPendingRefinements()
    }

    private var refineModelName: String? {
        guard let name = Preferences.refineModel, !name.isEmpty, installedModels.contains(name) else { return nil }
        return name
    }

    private func makeLiveEngine() -> WhisperKitEngine? {
        guard let name = Preferences.selectedModel, installedModels.contains(name) else {
            modelState = .missing
            return nil
        }
        let engine = WhisperKitEngine(modelFolder: ModelStore.folder(named: name))
        modelState = .loading
        Task {
            do {
                try await engine.load()
                if self.engine === engine { modelState = .ready }
            } catch {
                if self.engine === engine { modelState = .failed(error.localizedDescription) }
            }
        }
        return engine
    }

    /// Tira o modelo ao vivo da memória quando a gravação termina.
    private func release(_ engine: WhisperKitEngine?) async {
        await engine?.unload()
        if self.engine == nil { modelState = installedModels.isEmpty ? .missing : .standby }
    }

    // MARK: - Revisão final

    private func scheduleRefinement(of recorder: MeetingRecorder) {
        guard refineModelName != nil else { return }
        let ended = recorder.endedAt ?? Date()
        let job = TranscriptRefiner.Job(title: MeetingFolderNaming.title(startedAt: recorder.startedAt, label: recorder.label),
                                        startedAt: recorder.startedAt, endedAt: ended,
                                        duration: ended.timeIntervalSince(recorder.startedAt))
        do {
            try TranscriptRefiner.markPending(folder: recorder.folder, job: job)
            pendingRefinements.append(recorder.folder)
        } catch {
            log.error("Não foi possível agendar a revisão: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Revisa as reuniões pendentes, uma por vez, enquanto nada estiver gravando.
    private func runPendingRefinements() {
        guard refineTask == nil, status == .idle, !pendingRefinements.isEmpty, let name = refineModelName else { return }
        let engine = WhisperKitEngine(modelFolder: ModelStore.folder(named: name))
        refineTask = Task {
            while let folder = pendingRefinements.first, !Task.isCancelled {
                guard let job = TranscriptRefiner.pendingJob(in: folder) else {
                    pendingRefinements.removeFirst()
                    continue
                }
                refinement = RefinementStatus(title: job.title, progress: 0)
                do {
                    try await TranscriptRefiner.refine(folder: folder, job: job, engine: engine, modelName: name,
                                                       allowedLanguages: Preferences.allowedLanguages) { [weak self] progress in
                        self?.refinement?.progress = progress
                    }
                    pendingRefinements.removeFirst()
                    lastRefinedFolder = folder
                } catch {
                    // Cancelada por uma nova gravação: continua pendente e é retomada depois.
                    if Task.isCancelled { break }
                    log.error("Revisão falhou: \(error.localizedDescription, privacy: .public)")
                    lastError = "A revisão final falhou; a transcrição ao vivo foi mantida. (\(error.localizedDescription))"
                    TranscriptRefiner.clearPending(in: folder)
                    pendingRefinements.removeFirst()
                }
            }
            await engine.unload()
            refinement = nil
            refineTask = nil
            runPendingRefinements()
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
                case .success:
                    self.refreshModels()
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
        modelState = models.isEmpty ? .missing : .standby
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
