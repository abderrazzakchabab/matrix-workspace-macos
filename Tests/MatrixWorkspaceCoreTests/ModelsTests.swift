import XCTest
@testable import MatrixWorkspaceCore

final class ModelsTests: XCTestCase {
    func testGithubWriteScopeSerializesWithColon() throws {
        XCTAssertEqual(GithubWriteScope.issuesWrite.rawValue, "issues:write")
        XCTAssertEqual(GithubWriteScope.pullRequestsWrite.rawValue, "pull_requests:write")

        let encoded = try JSONEncoder().encode(GithubWriteScope.pullRequestsWrite)
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), "\"pull_requests:write\"")
    }

    func testGithubMutationOperationRawValues() {
        XCTAssertEqual(GithubMutationOperation.createIssue.rawValue, "create_issue")
        XCTAssertEqual(GithubMutationOperation.createPRComment.rawValue, "create_pr_comment")
    }

    func testGithubRepositorySummaryDecodesPrivateKey() throws {
        let json = """
        {"id":7,"name":"repo","fullName":"o/repo","owner":"o","private":true,"defaultBranch":"main","description":null,"htmlUrl":"https://github.com/o/repo","archived":false}
        """
        let decoded = try JSONDecoder().decode(GithubRepositorySummary.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.isPrivate, true)
        XCTAssertEqual(decoded.fullName, "o/repo")
    }

    func testRunEventDecodesAndDetectsTerminal() throws {
        let json = """
        {"id":"ev_9","runId":"run_1","sequence":9,"type":"run.completed","version":1,"occurredAt":"2026-08-17T00:00:00.000Z","visibility":"room_and_owner","payload":{"specialist":"reader"}}
        """
        let event = try JSONDecoder().decode(RunEvent.self, from: Data(json.utf8))
        XCTAssertEqual(event.runId, "run_1")
        XCTAssertEqual(event.sequence, 9)
        XCTAssertEqual(event.eventType, .runCompleted)
        XCTAssertEqual(event.isTerminal, true)
        XCTAssertEqual(event.payload["specialist"], .string("reader"))
    }

    func testNonTerminalEventIsNotTerminal() throws {
        let json = TestSupport.eventJSON(id: "ev_1", runId: "run_1", sequence: 1, type: "specialist.progress")
        let event = try JSONDecoder().decode(RunEvent.self, from: Data(json.utf8))
        XCTAssertEqual(event.isTerminal, false)
    }

    func testTerminalSetMatchesContract() {
        XCTAssertEqual(
            Set(RunEventType.terminal),
            Set([RunEventType.runPartial, .runCompleted, .runFailed, .runCancelled])
        )
    }

    func testApiErrorDecodes() throws {
        let json = #"{"error":{"code":"SESSION_REQUIRED","message":"Sign in again","requestId":"req_1"}}"#
        let envelope = try JSONDecoder().decode(ApiErrorEnvelope.self, from: Data(json.utf8))
        XCTAssertEqual(envelope.error.code, "SESSION_REQUIRED")
        XCTAssertEqual(envelope.error.requestId, "req_1")
    }

    func testJSONValueRoundTripsAllShapes() throws {
        let json = #"{"s":"x","n":5,"b":true,"z":null,"a":[1,"two"],"o":{"k":"v"}}"#
        let value = try JSONValue.parse(json)
        XCTAssertEqual(
            value,
            .object([
                "s": .string("x"),
                "n": .number(5),
                "b": .bool(true),
                "z": .null,
                "a": .array([.number(1), .string("two")]),
                "o": .object(["k": .string("v")]),
            ])
        )
    }

    func testRunModeAndStatusRawValues() {
        XCTAssertEqual(RunMode.parallel.rawValue, "parallel")
        XCTAssertEqual(RunMode.sequential.rawValue, "sequential")
        XCTAssertEqual(RunStatus.cancelling.rawValue, "cancelling")
    }
}
