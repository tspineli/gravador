import Foundation

/// Segura os trechos do microfone até a transcrição do sistema "alcançar" o mesmo momento,
/// para decidir se são eco (voz dos outros captada pelo alto-falante) antes de publicá-los.
///
/// O progresso do sistema avança com cada trecho transcrito e com marcações de silêncio
/// (`systemIdle`), então sem ninguém falando do outro lado o trecho do microfone sai na hora.
public struct EchoGate: Sendable {
    public var timeout: TimeInterval
    public var retention: TimeInterval = 60

    private var pending: [(segment: TranscriptSegment, receivedAt: Date)] = []
    private var recentSystem: [TranscriptSegment] = []
    public private(set) var systemProgress: TimeInterval = 0

    public init(timeout: TimeInterval = 12) {
        self.timeout = timeout
    }

    /// Trecho do sistema: sempre publicado; pode liberar trechos do microfone.
    public mutating func addSystem(_ segment: TranscriptSegment) -> [TranscriptSegment] {
        recentSystem.append(segment)
        recentSystem.removeAll { $0.end < segment.start - retention }
        systemProgress = max(systemProgress, segment.end)
        return [segment] + release(now: nil)
    }

    /// O sistema não tem fala em andamento até `until` (segundos desde o início da trilha).
    public mutating func systemIdle(until: TimeInterval) -> [TranscriptSegment] {
        systemProgress = max(systemProgress, until)
        return release(now: nil)
    }

    public mutating func addMicrophone(_ segment: TranscriptSegment, now: Date) -> [TranscriptSegment] {
        pending.append((segment, now))
        return release(now: now)
    }

    public mutating func tick(now: Date) -> [TranscriptSegment] {
        release(now: now)
    }

    /// Fim da gravação: decide tudo o que ficou pendente.
    public mutating func flush() -> [TranscriptSegment] {
        systemProgress = .infinity
        return release(now: nil)
    }

    private mutating func release(now: Date?) -> [TranscriptSegment] {
        var output: [TranscriptSegment] = []
        pending.removeAll { item in
            let caughtUp = systemProgress >= item.segment.end
            let expired = now.map { $0.timeIntervalSince(item.receivedAt) >= timeout } ?? false
            guard caughtUp || expired else { return false }
            if !TranscriptFilters.isEcho(item.segment, of: recentSystem) {
                output.append(item.segment)
            }
            return true
        }
        return output
    }
}
