import XCTest
@testable import GravadorCore

final class RecordingStateMachineTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    func testAutoStartsAfterDelayAndStopsWhenMeetingEnds() {
        var sm = RecordingStateMachine(policy: .init(startDelay: 2, stopDelay: 15))
        XCTAssertEqual(sm.observe(now: at(0), meetings: [.zoom], unidentifiedBrowsers: []), [])
        XCTAssertEqual(sm.observe(now: at(1), meetings: [.zoom], unidentifiedBrowsers: []), [])
        XCTAssertEqual(sm.observe(now: at(2), meetings: [.zoom], unidentifiedBrowsers: []), [.start(.automatic(.zoom))])
        XCTAssertEqual(sm.observe(now: at(3), meetings: [.zoom], unidentifiedBrowsers: []), [])

        // Mic liberado: espera o stopDelay inteiro.
        XCTAssertEqual(sm.observe(now: at(10), meetings: [], unidentifiedBrowsers: []), [])
        XCTAssertEqual(sm.observe(now: at(24), meetings: [], unidentifiedBrowsers: []), [])
        XCTAssertEqual(sm.observe(now: at(25), meetings: [], unidentifiedBrowsers: []), [.stop(.meetingEnded)])
        XCTAssertFalse(sm.isRecording)
    }

    func testBriefMicReleaseDoesNotStop() {
        var sm = RecordingStateMachine(policy: .init(startDelay: 0, stopDelay: 15))
        XCTAssertEqual(sm.observe(now: at(0), meetings: [.teams], unidentifiedBrowsers: []), [.start(.automatic(.teams))])
        _ = sm.observe(now: at(5), meetings: [], unidentifiedBrowsers: [])
        _ = sm.observe(now: at(15), meetings: [], unidentifiedBrowsers: [])
        XCTAssertEqual(sm.observe(now: at(16), meetings: [.teams], unidentifiedBrowsers: []), [])
        XCTAssertEqual(sm.observe(now: at(25), meetings: [.teams], unidentifiedBrowsers: []), [])
        XCTAssertTrue(sm.isRecording)
    }

    func testManualStopSuppressesUntilMicReleased() {
        var sm = RecordingStateMachine(policy: .init(startDelay: 2, stopDelay: 15))
        _ = sm.observe(now: at(0), meetings: [.meet], unidentifiedBrowsers: [])
        XCTAssertEqual(sm.observe(now: at(2), meetings: [.meet], unidentifiedBrowsers: []), [.start(.automatic(.meet))])

        XCTAssertEqual(sm.manualStop(), [.stop(.manual)])
        XCTAssertTrue(sm.isSuppressed)

        // Continua na reunião: não pode reiniciar sozinho.
        for s in stride(from: 3.0, through: 60, by: 1) {
            XCTAssertEqual(sm.observe(now: at(s), meetings: [.meet], unidentifiedBrowsers: []), [])
        }

        // Saiu da reunião e o stopDelay passou: supressão é limpa.
        _ = sm.observe(now: at(61), meetings: [], unidentifiedBrowsers: [])
        _ = sm.observe(now: at(76), meetings: [], unidentifiedBrowsers: [])
        XCTAssertFalse(sm.isSuppressed)

        // Próxima reunião volta a gravar automaticamente.
        _ = sm.observe(now: at(100), meetings: [.meet], unidentifiedBrowsers: [])
        XCTAssertEqual(sm.observe(now: at(102), meetings: [.meet], unidentifiedBrowsers: []), [.start(.automatic(.meet))])
    }

    func testManualStartIsNotStoppedAutomatically() {
        var sm = RecordingStateMachine(policy: .init(startDelay: 2, stopDelay: 15))
        XCTAssertEqual(sm.manualStart(), [.start(.manual)])
        XCTAssertEqual(sm.manualStart(), [])
        _ = sm.observe(now: at(0), meetings: [.zoom], unidentifiedBrowsers: [])
        _ = sm.observe(now: at(5), meetings: [.zoom], unidentifiedBrowsers: [])
        _ = sm.observe(now: at(6), meetings: [], unidentifiedBrowsers: [])
        XCTAssertEqual(sm.observe(now: at(60), meetings: [], unidentifiedBrowsers: []), [])
        XCTAssertEqual(sm.recording, .manual)
        XCTAssertEqual(sm.manualStop(), [.stop(.manual)])
    }

    func testAutoStartDisabled() {
        var sm = RecordingStateMachine(policy: .init(startDelay: 0, stopDelay: 15), autoStartEnabled: false)
        XCTAssertEqual(sm.observe(now: at(0), meetings: [.zoom], unidentifiedBrowsers: ["Chrome"]), [])
        XCTAssertEqual(sm.observe(now: at(10), meetings: [.zoom], unidentifiedBrowsers: ["Chrome"]), [])
    }

    func testBrowserSuggestionOncePerMicUse() {
        var sm = RecordingStateMachine(policy: .init(startDelay: 2, stopDelay: 15))
        XCTAssertEqual(sm.observe(now: at(0), meetings: [], unidentifiedBrowsers: ["Chrome"]), [])
        XCTAssertEqual(sm.observe(now: at(2), meetings: [], unidentifiedBrowsers: ["Chrome"]), [.suggest(browserName: "Chrome")])
        XCTAssertEqual(sm.observe(now: at(30), meetings: [], unidentifiedBrowsers: ["Chrome"]), [])
        // Soltou o mic e voltou: sugere de novo.
        _ = sm.observe(now: at(31), meetings: [], unidentifiedBrowsers: [])
        _ = sm.observe(now: at(32), meetings: [], unidentifiedBrowsers: ["Chrome"])
        XCTAssertEqual(sm.observe(now: at(34), meetings: [], unidentifiedBrowsers: ["Chrome"]), [.suggest(browserName: "Chrome")])
    }

    func testFailedStartSuppresses() {
        var sm = RecordingStateMachine(policy: .init(startDelay: 0, stopDelay: 15))
        XCTAssertEqual(sm.observe(now: at(0), meetings: [.zoom], unidentifiedBrowsers: []), [.start(.automatic(.zoom))])
        sm.recordingFailed()
        XCTAssertEqual(sm.observe(now: at(1), meetings: [.zoom], unidentifiedBrowsers: []), [])
    }
}
