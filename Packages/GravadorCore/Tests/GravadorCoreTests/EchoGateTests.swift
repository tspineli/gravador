import XCTest
@testable import GravadorCore

final class EchoGateTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_000)

    func mic(_ start: TimeInterval, _ end: TimeInterval, _ text: String) -> TranscriptSegment {
        TranscriptSegment(track: .microphone, start: start, end: end, language: "pt", text: text)
    }

    func sys(_ start: TimeInterval, _ end: TimeInterval, _ text: String) -> TranscriptSegment {
        TranscriptSegment(track: .system, start: start, end: end, language: "pt", text: text)
    }

    func testMicReleasedImmediatelyWhenSystemIsSilent() {
        var gate = EchoGate()
        _ = gate.systemIdle(until: 30)
        let m = mic(10, 12, "Bom dia a todos")
        XCTAssertEqual(gate.addMicrophone(m, now: now), [m])
    }

    func testMicWaitsForSystemThenDropsEcho() {
        var gate = EchoGate()
        let echo = mic(10, 14, "vamos revisar o orçamento do trimestre")
        XCTAssertEqual(gate.addMicrophone(echo, now: now), [], "sistema ainda não chegou em 14s")
        let s = sys(10.2, 14.1, "Vamos revisar o orçamento do trimestre")
        XCTAssertEqual(gate.addSystem(s), [s], "eco descartado, só o sistema sai")
    }

    func testMicWaitsForSystemThenKeepsRealSpeech() {
        var gate = EchoGate()
        let real = mic(10, 12, "Concordo, pode seguir")
        XCTAssertEqual(gate.addMicrophone(real, now: now), [])
        XCTAssertEqual(gate.systemIdle(until: 12.5), [real])
    }

    func testTimeoutReleases() {
        var gate = EchoGate(timeout: 5)
        let m = mic(10, 12, "Alguém me ouve?")
        _ = gate.addMicrophone(m, now: now)
        XCTAssertEqual(gate.tick(now: now.addingTimeInterval(4)), [])
        XCTAssertEqual(gate.tick(now: now.addingTimeInterval(5)), [m])
    }

    func testFlushReleasesPending() {
        var gate = EchoGate()
        let m = mic(50, 52, "Valeu, até amanhã")
        _ = gate.addMicrophone(m, now: now)
        XCTAssertEqual(gate.flush(), [m])
    }
}
