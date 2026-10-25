import XCTest
@testable import GravadorCore

final class RefinementTests: XCTestCase {
    func chunk(_ start: TimeInterval, _ duration: TimeInterval, value: Float = 0.5) -> SpeechChunk {
        SpeechChunk(startSample: Int(start * 16_000), samples: Array(repeating: value, count: Int(duration * 16_000)),
                    sampleRate: 16_000)
    }

    func testJoinsCloseChunksAndFillsGapWithSilence() {
        var builder = RefinementWindowBuilder()
        XCTAssertEqual(builder.add(chunk(1, 3), language: "pt"), [])
        XCTAssertEqual(builder.add(chunk(5, 2), language: "pt"), [])
        let windows = builder.flush()
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].start, 1)
        XCTAssertEqual(windows[0].end, 7, accuracy: 0.001, "o tempo da segunda fala fica no lugar certo")
        XCTAssertEqual(windows[0].samples[Int(3.5 * 16_000)], 0, "a pausa vira silêncio")
    }

    func testLanguageChangeStartsNewWindow() {
        var builder = RefinementWindowBuilder()
        _ = builder.add(chunk(0, 3), language: "pt")
        let closed = builder.add(chunk(3.5, 3), language: "en")
        XCTAssertEqual(closed.map(\.language), ["pt"])
        XCTAssertEqual(builder.flush().map(\.language), ["en"])
    }

    func testLongPauseAndMaxWindowStartNewWindow() {
        var builder = RefinementWindowBuilder()
        _ = builder.add(chunk(0, 3), language: "pt")
        XCTAssertEqual(builder.add(chunk(10, 3), language: "pt").count, 1, "pausa de 7 s")
        XCTAssertEqual(builder.add(chunk(14, 26), language: "pt").count, 1, "passaria de 28 s")
        XCTAssertEqual(builder.flush().first?.start, 14)
    }

    func testMergeDropsEchoAndSorts() {
        let echo = TranscriptSegment(track: .microphone, start: 10, end: 14, language: "pt", text: "vamos revisar o orçamento")
        let mine = TranscriptSegment(track: .microphone, start: 2, end: 4, language: "pt", text: "Bom dia")
        let other = TranscriptSegment(track: .system, start: 10.3, end: 14, language: "pt", text: "Vamos revisar o orçamento.")
        XCTAssertEqual(TranscriptMerge.merge(microphone: [echo, mine], system: [other]), [mine, other])
    }

    func testFinishWithNote() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let writer = try TranscriptWriter(folder: folder, title: "Teste", startedAt: Date())
        try writer.append(TranscriptSegment(track: .system, start: 1, end: 2, language: "pt", text: "Olá"))
        try writer.finish(endedAt: Date(), duration: 60, note: "Revisada com o modelo X")
        let text = try String(contentsOf: folder.appendingPathComponent(TranscriptWriter.markdownName), encoding: .utf8)
        XCTAssertTrue(text.contains("_Revisada com o modelo X_"))
    }
}
