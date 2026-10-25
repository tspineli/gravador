import Foundation

/// Decide quando iniciar/parar a gravação a partir do que está usando o microfone.
/// É pura (o tempo é injetado), para poder ser testada sem áudio real.
public struct RecordingStateMachine: Sendable {
    public enum Origin: Equatable, Sendable {
        case manual
        case automatic(MeetingApp)
    }

    public enum StopReason: Equatable, Sendable {
        case manual
        case meetingEnded
    }

    public enum Action: Equatable, Sendable {
        case start(Origin)
        case stop(StopReason)
        /// Navegador usando o microfone sem reunião identificada: sugerir gravação ao usuário.
        case suggest(browserName: String)
    }

    public struct Policy: Sendable {
        /// Tempo com o microfone ativo antes de iniciar automaticamente.
        public var startDelay: TimeInterval
        /// Tempo com o microfone liberado antes de considerar que a reunião acabou.
        public var stopDelay: TimeInterval

        public init(startDelay: TimeInterval = 2, stopDelay: TimeInterval = 15) {
            self.startDelay = startDelay
            self.stopDelay = stopDelay
        }
    }

    public var policy: Policy
    public var autoStartEnabled: Bool

    public private(set) var recording: Origin?
    /// Ligado quando o usuário para manualmente durante uma reunião detectada:
    /// impede o reinício automático até o app soltar o microfone.
    public private(set) var isSuppressed = false
    public private(set) var currentMeeting: MeetingApp?

    private var meetingActiveSince: Date?
    private var meetingInactiveSince: Date?
    private var browserFirstSeen: [String: Date] = [:]
    private var suggestedBrowsers: Set<String> = []

    public init(policy: Policy = Policy(), autoStartEnabled: Bool = true) {
        self.policy = policy
        self.autoStartEnabled = autoStartEnabled
    }

    public var isRecording: Bool { recording != nil }

    /// Chamada periodicamente (~1 s) com as reuniões identificadas e os navegadores
    /// que estão usando o microfone sem reunião reconhecida.
    public mutating func observe(now: Date, meetings: [MeetingApp], unidentifiedBrowsers: Set<String>) -> [Action] {
        var actions: [Action] = []

        if let meeting = meetings.first {
            meetingInactiveSince = nil
            if meetingActiveSince == nil { meetingActiveSince = now }
            currentMeeting = meeting
            if recording == nil, !isSuppressed, autoStartEnabled,
               let since = meetingActiveSince, now.timeIntervalSince(since) >= policy.startDelay {
                recording = .automatic(meeting)
                actions.append(.start(.automatic(meeting)))
            }
        } else {
            meetingActiveSince = nil
            if currentMeeting != nil, meetingInactiveSince == nil { meetingInactiveSince = now }
            if let since = meetingInactiveSince, now.timeIntervalSince(since) >= policy.stopDelay {
                meetingInactiveSince = nil
                currentMeeting = nil
                isSuppressed = false
                if case .automatic = recording {
                    recording = nil
                    actions.append(.stop(.meetingEnded))
                }
            }
        }

        // Sugestões para navegadores não identificados, uma vez por uso contínuo do microfone.
        browserFirstSeen = browserFirstSeen.filter { unidentifiedBrowsers.contains($0.key) }
        suggestedBrowsers.formIntersection(unidentifiedBrowsers)
        for name in unidentifiedBrowsers.sorted() {
            let first = browserFirstSeen[name] ?? now
            browserFirstSeen[name] = first
            if recording == nil, !isSuppressed, autoStartEnabled, !suggestedBrowsers.contains(name),
               now.timeIntervalSince(first) >= policy.startDelay {
                suggestedBrowsers.insert(name)
                actions.append(.suggest(browserName: name))
            }
        }

        return actions
    }

    public mutating func manualStart() -> [Action] {
        guard recording == nil else { return [] }
        recording = .manual
        return [.start(.manual)]
    }

    public mutating func manualStop() -> [Action] {
        guard recording != nil else { return [] }
        recording = nil
        if currentMeeting != nil { isSuppressed = true }
        return [.stop(.manual)]
    }

    /// A gravação não pôde começar (ex.: permissão negada). Volta ao repouso sem tentar de novo nesta reunião.
    public mutating func recordingFailed() {
        recording = nil
        if currentMeeting != nil { isSuppressed = true }
    }
}
