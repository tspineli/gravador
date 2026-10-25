import XCTest
@testable import GravadorCore

final class SpeechSegmenterTests: XCTestCase {
    let rate = 16_000.0

    func silence(_ seconds: Double) -> [Float] { Array(repeating: 0.0005, count: Int(seconds * rate)) }

    func tone(_ seconds: Double, amplitude: Float = 0.2) -> [Float] {
        (0..<Int(seconds * rate)).map { amplitude * sin(Float($0) * 2 * .pi * 220 / Float(rate)) }
    }

    func testCutsAtPause() {
        var seg = SpeechSegmenter()
        var chunks: [SpeechChunk] = []
        chunks += seg.append(silence(1))
        chunks += seg.append(tone(2))
        XCTAssertTrue(chunks.isEmpty, "ainda falando")
        chunks += seg.append(silence(1))
        XCTAssertEqual(chunks.count, 1)
        let c = chunks[0]
        XCTAssertEqual(c.start, 1 - 0.3, accuracy: 0.05, "inclui pre-roll")
        XCTAssertEqual(c.end, 3.15, accuracy: 0.2)
    }

    func testIgnoresShortBlips() {
        var seg = SpeechSegmenter()
        var chunks = seg.append(silence(1) + tone(0.1) + silence(1))
        chunks += seg.flush()
        XCTAssertTrue(chunks.isEmpty)
    }

    func testForcedCutOnLongSpeech() {
        var config = SpeechSegmenter.Configuration()
        config.maxChunk = 5
        var seg = SpeechSegmenter(config: config)
        var chunks = seg.append(tone(12))
        chunks += seg.flush()
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0].samples.count, 5 * 16_000, accuracy: 480)
        // Trechos contíguos, sem perder áudio.
        XCTAssertEqual(chunks[1].startSample, chunks[0].startSample + chunks[0].samples.count, accuracy: 480)
        XCTAssertEqual(chunks.map(\.samples.count).reduce(0, +), 12 * 16_000, accuracy: 960)
    }

    func testLongSpeechCutsAtShortPause() {
        var seg = SpeechSegmenter()
        // 19 s de fala, pausa de 0,3 s (curta demais para o corte normal), mais fala.
        var chunks = seg.append(silence(0.5) + tone(19) + silence(0.3) + tone(3))
        XCTAssertEqual(chunks.count, 1, "corta na pausa curta depois de 18 s")
        XCTAssertEqual(chunks[0].end, 19.5, accuracy: 0.3)
        chunks += seg.flush()
        XCTAssertEqual(chunks.count, 2)
    }

    func testShortPauseDoesNotCutBeforeSoftMax() {
        var seg = SpeechSegmenter()
        let chunks = seg.append(silence(0.5) + tone(5) + silence(0.3) + tone(3)) + seg.flush()
        XCTAssertEqual(chunks.count, 1)
    }

    func testTwoUtterances() {
        var seg = SpeechSegmenter()
        var chunks = seg.append(tone(1) + silence(1) + tone(1.5))
        chunks += seg.flush()
        XCTAssertEqual(chunks.count, 2)
        XCTAssertLessThan(chunks[0].end, chunks[1].start)
    }

    func testAppendInSmallPiecesMatchesBulk() {
        let audio = silence(0.5) + tone(1) + silence(1) + tone(0.8) + silence(1)
        var bulk = SpeechSegmenter()
        let expected = bulk.append(audio) + bulk.flush()

        var pieces = SpeechSegmenter()
        var got: [SpeechChunk] = []
        var i = 0
        while i < audio.count {
            let n = min(1_037, audio.count - i)
            got += pieces.append(Array(audio[i..<(i + n)]))
            i += n
        }
        got += pieces.flush()
        XCTAssertEqual(got, expected)
    }
}
