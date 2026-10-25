import XCTest
@testable import GravadorCore

final class CatalogAndFiltersTests: XCTestCase {
    func testClassifiesNativeApps() {
        XCTAssertEqual(MeetingCatalog.classify(bundleID: "us.zoom.xos"), .nativeMeeting(.zoom))
        XCTAssertEqual(MeetingCatalog.classify(bundleID: "com.microsoft.teams2"), .nativeMeeting(.teams))
        XCTAssertEqual(MeetingCatalog.classify(bundleID: "com.microsoft.teams"), .nativeMeeting(.teams))
        XCTAssertEqual(MeetingCatalog.classify(bundleID: "Cisco-Systems.Spark"), .nativeMeeting(.webex))
        XCTAssertEqual(MeetingCatalog.classify(bundleID: "com.apple.dt.Xcode"), .other)
    }

    func testClassifiesBrowserHelpers() {
        guard case .browser(let chrome) = MeetingCatalog.classify(bundleID: "com.google.Chrome.helper") else {
            return XCTFail("Chrome helper")
        }
        XCTAssertEqual(chrome.mainBundleID, "com.google.Chrome")
        guard case .browser(let safari) = MeetingCatalog.classify(bundleID: "com.apple.WebKit.GPU") else {
            return XCTFail("WebKit GPU")
        }
        XCTAssertEqual(safari.name, "Safari")
        // Edge não pode ser confundido com Teams (ambos com.microsoft.*).
        guard case .browser(let edge) = MeetingCatalog.classify(bundleID: "com.microsoft.edgemac.helper") else {
            return XCTFail("Edge helper")
        }
        XCTAssertEqual(edge.name, "Edge")
    }

    func testWindowTitles() {
        XCTAssertEqual(MeetingCatalog.meeting(forWindowTitle: "Meet - abc-defg-hij"), .meet)
        XCTAssertEqual(MeetingCatalog.meeting(forWindowTitle: "Meet – Daily do time"), .meet)
        XCTAssertEqual(MeetingCatalog.meeting(forWindowTitle: "Reunião | Microsoft Teams"), .teams)
        XCTAssertEqual(MeetingCatalog.meeting(forWindowTitle: "Zoom Meeting"), .zoom)
        XCTAssertNil(MeetingCatalog.meeting(forWindowTitle: "YouTube"))
    }

    func testCleanText() {
        XCTAssertEqual(TranscriptFilters.clean("  <|pt|> Bom dia,   pessoal. "), "Bom dia, pessoal.")
        XCTAssertNil(TranscriptFilters.clean("Legendas pela comunidade Amara.org"))
        XCTAssertNil(TranscriptFilters.clean(" you "))
        XCTAssertNil(TranscriptFilters.clean("[Música]"))
        XCTAssertEqual(TranscriptFilters.clean("Obrigado."), "Obrigado.")
    }

    func testEchoDetection() {
        let sys = TranscriptSegment(track: .system, start: 10, end: 14, language: "pt", text: "Vamos revisar o orçamento do próximo trimestre")
        let echo = TranscriptSegment(track: .microphone, start: 10.4, end: 14.2, language: "pt", text: "vamos revisar o orcamento do proximo trimestre")
        let real = TranscriptSegment(track: .microphone, start: 15, end: 17, language: "pt", text: "Concordo, pode compartilhar a planilha?")
        let late = TranscriptSegment(track: .microphone, start: 40, end: 44, language: "pt", text: "Vamos revisar o orçamento do próximo trimestre")
        XCTAssertTrue(TranscriptFilters.isEcho(echo, of: [sys]))
        XCTAssertFalse(TranscriptFilters.isEcho(real, of: [sys]))
        XCTAssertFalse(TranscriptFilters.isEcho(late, of: [sys]))
    }

    func testLanguagePicker() {
        let probs: [String: Float] = ["gl": 0.5, "pt": 0.4, "es": 0.1]
        XCTAssertEqual(LanguagePicker.pick(probabilities: probs, allowed: ["pt", "en", "es"], fallback: "pt"), "pt")
        XCTAssertEqual(LanguagePicker.pick(probabilities: [:], allowed: ["pt"], fallback: "en"), "en")
    }

    func testClockFormatting() {
        XCTAssertEqual(TimeFormatting.clock(5), "00:05")
        XCTAssertEqual(TimeFormatting.clock(754.9), "12:34")
        XCTAssertEqual(TimeFormatting.clock(3_725), "1:02:05")
    }
}
