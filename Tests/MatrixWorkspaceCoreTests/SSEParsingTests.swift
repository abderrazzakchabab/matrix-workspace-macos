import XCTest
@testable import MatrixWorkspaceCore

final class SSEParsingTests: XCTestCase {
    // MARK: frame parsing

    func testParseFrameExtractsIdEventAndData() throws {
        let frame = SSE.parseFrame("id: 3\nevent: run.completed\ndata: {}\n")
        XCTAssertEqual(frame?.id, "3")
        XCTAssertEqual(frame?.event, "run.completed")
        XCTAssertEqual(frame?.data, "{}")
    }

    func testParseFrameJoinsMultipleDataLines() {
        let frame = SSE.parseFrame("data: hello\ndata: world\n\n")
        XCTAssertEqual(frame?.data, "hello\nworld")
    }

    func testParseFrameStripsSingleLeadingSpaceOnly() {
        let frame = SSE.parseFrame("data:{\"k\":\"v\"}\n")
        XCTAssertEqual(frame?.data, "{\"k\":\"v\"}")
        let spaced = SSE.parseFrame("data: {\"a\":1}\n")
        XCTAssertEqual(spaced?.data, "{\"a\":1}")
    }

    func testParseFrameIgnoresCommentAndNoDataReturnsNil() {
        XCTAssertNil(SSE.parseFrame(": keepalive\n\n"))
        XCTAssertNil(SSE.parseFrame("id: 1\n\n"))
    }

    func testParseFrameHandlesCRLF() {
        let frame = SSE.parseFrame("id: 7\r\nevent: run.started\r\ndata: {}\r\n\r\n")
        XCTAssertEqual(frame?.id, "7")
        XCTAssertEqual(frame?.event, "run.started")
    }

    // MARK: event validation

    private func event(id: String?, event field: String?, data: String, runId: String = "run_1") -> RunEvent? {
        SSE.event(from: SSEFrame(id: id, event: field, data: data), expectedRunId: runId)
    }

    func testEventRejectsNonDigitId() {
        let data = TestSupport.eventJSON(id: "e", runId: "run_1", sequence: 1, type: "run.started")
        XCTAssertNil(event(id: "abc", event: "run.started", data: data))
        XCTAssertNil(event(id: nil, event: "run.started", data: data))
    }

    func testEventRejectsMissingEventField() {
        let data = TestSupport.eventJSON(id: "e", runId: "run_1", sequence: 1, type: "run.started")
        XCTAssertNil(event(id: "1", event: nil, data: data))
    }

    func testEventRejectsRunIdMismatch() {
        let data = TestSupport.eventJSON(id: "e", runId: "run_other", sequence: 1, type: "run.started")
        XCTAssertNil(event(id: "1", event: "run.started", data: data))
    }

    func testEventRejectsSequenceMismatch() {
        let data = TestSupport.eventJSON(id: "e", runId: "run_1", sequence: 2, type: "run.started")
        XCTAssertNil(event(id: "1", event: "run.started", data: data))
    }

    func testEventRejectsFieldMismatch() {
        let data = TestSupport.eventJSON(id: "e", runId: "run_1", sequence: 1, type: "run.started")
        XCTAssertNil(event(id: "1", event: "specialist.progress", data: data))
    }

    func testEventAcceptsValidFrame() {
        let data = TestSupport.eventJSON(id: "e", runId: "run_1", sequence: 1, type: "run.started")
        let decoded = event(id: "1", event: "run.started", data: data)
        XCTAssertEqual(decoded?.sequence, 1)
    }

    // MARK: byte decoder

    func testDecoderNormalizesLFAndCRLF() {
        var lf = SSEFrameDecoder()
        XCTAssertEqual(lf.push(Array("id: 1\ndata: {}\n\n".utf8)), ["id: 1\ndata: {}"])

        var crlf = SSEFrameDecoder()
        XCTAssertEqual(crlf.push(Array("id: 2\r\ndata: {}\r\n\r\n".utf8)), ["id: 2\ndata: {}"])
    }

    func testDecoderEmitsNothingUntilBlankLine() {
        var decoder = SSEFrameDecoder()
        XCTAssertEqual(decoder.push(Array("id: 1\n".utf8)), [])
        XCTAssertEqual(decoder.push(Array("data: {}\n".utf8)), [])
        XCTAssertEqual(decoder.push(Array("\n".utf8)), ["id: 1\ndata: {}"])
    }

    func testDecoderFlushRemainingPartialFrame() {
        var decoder = SSEFrameDecoder()
        _ = decoder.push(Array("id: 1\ndata: partial".utf8))
        XCTAssertEqual(decoder.flushRemaining(), "id: 1\ndata: partial")
        XCTAssertNil(decoder.flushRemaining())
    }

    func testDecoderPreservesMultibyteUTF8() {
        var decoder = SSEFrameDecoder()
        let bytes = Array("data: café ☕\n\n".utf8)
        let frames: [String] = []
        var collected = frames
        for i in 0 ..< bytes.count {
            if let f = decoder.push(bytes[i]) { collected.append(f) }
        }
        XCTAssertEqual(collected, ["data: café ☕"])
    }

    // MARK: backoff

    func testBackoffClampsToBounds() {
        XCTAssertEqual(connectBackoffDelay(attempt: 0, baseDelayMs: 500, maxDelayMs: 8000, random: 0.0), 250)
        XCTAssertEqual(connectBackoffDelay(attempt: 0, baseDelayMs: 500, maxDelayMs: 8000, random: 1.0), 500)
        // Capped at maxDelay even for a large attempt count.
        let capped = connectBackoffDelay(attempt: 30, baseDelayMs: 500, maxDelayMs: 8000, random: 1.0)
        XCTAssertLessThanOrEqual(capped, 8000)
        // Never below the 100ms floor.
        XCTAssertEqual(connectBackoffDelay(attempt: 0, baseDelayMs: 1, maxDelayMs: 1, random: 0.0), 100)
    }
}
