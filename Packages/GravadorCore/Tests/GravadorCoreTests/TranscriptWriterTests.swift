import XCTest
@testable import GravadorCore

final class TranscriptWriterTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("gravador-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testAppendsAndReadsBack() throws {
        let folder = root.appendingPathComponent("reuniao")
        let start = Date()
        let a = TranscriptSegment(track: .system, start: 1, end: 3, language: "pt", text: "Bom dia")
        let b = TranscriptSegment(track: .microphone, start: 4, end: 6, language: "en", text: "Good morning")

        do {
            let writer = try TranscriptWriter(folder: folder, title: "Teste", startedAt: start)
            try writer.append(a)
        }
        // Reabrir (como após um crash) continua do fim, sem sobrescrever.
        do {
            let writer = try TranscriptWriter(folder: folder, title: "Teste", startedAt: start)
            try writer.append(b)
            try writer.finish(endedAt: start.addingTimeInterval(6), duration: 6)
        }

        XCTAssertEqual(TranscriptWriter.readSegments(in: folder), [a, b])
        let md = try String(contentsOf: folder.appendingPathComponent(TranscriptWriter.markdownName), encoding: .utf8)
        XCTAssertEqual(md.components(separatedBy: "# Teste").count - 1, 1, "cabeçalho único")
        XCTAssertTrue(md.contains("**[00:01] Outros:** Bom dia"))
        XCTAssertTrue(md.contains("**[00:04] Eu:** Good morning"))
        XCTAssertTrue(md.contains("duração 00:06"))
    }

    func testFinishSortsChronologically() throws {
        let folder = root.appendingPathComponent("ordem")
        let writer = try TranscriptWriter(folder: folder, title: "Ordem", startedAt: Date())
        try writer.append(TranscriptSegment(track: .system, start: 20, end: 22, language: "pt", text: "segundo"))
        try writer.append(TranscriptSegment(track: .microphone, start: 5, end: 7, language: "pt", text: "primeiro"))
        try writer.finish(endedAt: Date(), duration: 30)
        let md = try String(contentsOf: folder.appendingPathComponent(TranscriptWriter.markdownName), encoding: .utf8)
        let first = try XCTUnwrap(md.range(of: "primeiro")), second = try XCTUnwrap(md.range(of: "segundo"))
        XCTAssertLessThan(first.lowerBound, second.lowerBound)
    }

    func testFolderNamingIsUnique() throws {
        let date = Date(timeIntervalSince1970: 1_761_400_000)
        let first = MeetingFolderNaming.folder(in: root, startedAt: date, label: "Zoom")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        let second = MeetingFolderNaming.folder(in: root, startedAt: date, label: "Zoom")
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(second.lastPathComponent.hasSuffix("- Zoom (2)"))
        XCTAssertTrue(first.lastPathComponent.contains("h"))
    }
}
