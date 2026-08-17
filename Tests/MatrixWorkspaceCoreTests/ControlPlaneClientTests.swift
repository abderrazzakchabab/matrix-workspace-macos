import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MatrixWorkspaceCore

final class ControlPlaneClientTests: XCTestCase {
    private let baseURL = URL(string: "https://control.example")!

    override func setUp() {
        super.setUp()
        MockURLProtocol.lastRequest = nil
        MockURLProtocol.handler = nil
    }

    private func makeClient(store: SessionStore = InMemorySessionStore()) -> (ControlPlaneClient, SessionStore) {
        (ControlPlaneClient(baseURL: baseURL, sessionStore: store, session: TestSupport.makeSession()), store)
    }

    private func requestBody() throws -> [String: JSONValue] {
        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        let data = try XCTUnwrap(request.httpBody)
        return try JSONDecoder().decode([String: JSONValue].self, from: data)
    }

    func testCreateMatrixSessionSavesCookieAndDecodes() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/auth/matrix/session")
            XCTAssertEqual(request.httpMethod, "POST")
            return MockURLProtocol.StubResponse(
                status: 200,
                headers: ["Set-Cookie": "cp_session=abc123; Path=/; HttpOnly"],
                json: #"{"user":{"id":"@alice:matrix.example.org","homeserverUrl":"https://matrix.example.org"},"sessionExpiresAt":"2026-08-18T00:00:00.000Z"}"#
            )
        }

        let (client, store) = makeClient()
        let response = try await client.createMatrixSession(
            homeserverUrl: "https://matrix.example.org",
            accessToken: "syt_token"
        )

        XCTAssertEqual(response.user.id, "@alice:matrix.example.org")
        let record = try await store.load()
        XCTAssertEqual(record?.cookie, "cp_session=abc123")
    }

    func testCreateWorkspaceSendsTrimmedNameAndPolicy() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/workspaces")
            return MockURLProtocol.StubResponse(
                status: 201,
                json: #"{"requestId":"req_1","workspaceId":"ws_1","name":"my workspace","ownerId":"@alice:matrix.example.org","status":"active","createdAt":"2026-08-17T00:00:00.000Z"}"#
            )
        }

        let store = InMemorySessionStore()
        try await store.save(SessionRecord(cookie: "cp_session=abc123"))
        let (client, _) = makeClient(store: store)

        let workspace = try await client.createWorkspace(name: "  my workspace  ")
        XCTAssertEqual(workspace.workspaceId, "ws_1")
        XCTAssertEqual(workspace.status, "active")

        let body = try requestBody()
        XCTAssertEqual(body["name"], .string("my workspace"))
        XCTAssertEqual(body["policy"], .object([
            "readOnly": .bool(true),
            "failurePolicy": .string("partial"),
            "promptInjectionMode": .string("fail_run"),
        ]))
    }

    func testAuthenticatedRequestSendsCookieHeader() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "cp_session=abc123")
            return MockURLProtocol.StubResponse(
                status: 200,
                json: #"{"requestId":"r","rooms":[]}"#
            )
        }

        let store = InMemorySessionStore()
        try await store.save(SessionRecord(cookie: "cp_session=abc123"))
        let (client, _) = makeClient(store: store)

        let rooms = try await client.getRooms()
        XCTAssertEqual(rooms, [])
    }

    func testLaunchRunEncodesBodyAndDecodes() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/workspaces/ws_1/runs")
            return MockURLProtocol.StubResponse(
                status: 201,
                json: #"{"runId":"run_1","status":"queued","nextSequence":0}"#
            )
        }

        let store = InMemorySessionStore()
        try await store.save(SessionRecord(cookie: "cp_session=abc123"))
        let (client, _) = makeClient(store: store)

        let run = try await client.launchRun(
            workspaceId: "ws_1",
            request: RunRequest(prompt: "fix the bug", mode: .parallel, specialistIds: ["reader"]),
            idempotencyKey: "key_1"
        )
        XCTAssertEqual(run.runId, "run_1")
        XCTAssertEqual(run.status, .queued)

        let body = try requestBody()
        XCTAssertEqual(body["prompt"], .string("fix the bug"))
        XCTAssertEqual(body["mode"], .string("parallel"))
        XCTAssertEqual(body["idempotencyKey"], .string("key_1"))
    }

    func testBindRoomPercentEncodesRoomId() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/rooms/%21abc%3Amatrix.example.org/binding")
            return MockURLProtocol.StubResponse(
                status: 200,
                json: #"{"roomId":"!abc:matrix.example.org","workspaceId":"ws_1"}"#
            )
        }

        let store = InMemorySessionStore()
        try await store.save(SessionRecord(cookie: "cp_session=abc123"))
        let (client, _) = makeClient(store: store)

        let binding = try await client.bindRoom(roomId: "!abc:matrix.example.org", workspaceId: "ws_1")
        XCTAssertEqual(binding.roomId, "!abc:matrix.example.org")
    }

    func testEnqueueMutationReplaysOn200() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/workspaces/ws_1/github/mutations")
            return MockURLProtocol.StubResponse(
                status: 200,
                json: #"{"commandId":"cmd_1","status":"completed"}"#
            )
        }

        let store = InMemorySessionStore()
        try await store.save(SessionRecord(cookie: "cp_session=abc123"))
        let (client, _) = makeClient(store: store)

        let result = try await client.enqueueGithubMutation(
            workspaceId: "ws_1",
            request: GithubMutationRequest(
                idempotencyKey: "key_1",
                approvalId: "appr_1",
                repository: "o/repo",
                runId: nil,
                operation: .createIssue,
                arguments: ["title": .string("hi")]
            )
        )
        XCTAssertEqual(result.replayed, true)
    }

    func testEnqueueMutationNotReplayedOn202() async throws {
        MockURLProtocol.handler = { _ in
            MockURLProtocol.StubResponse(status: 202, json: #"{"commandId":"cmd_1","status":"queued"}"#)
        }
        let store = InMemorySessionStore()
        try await store.save(SessionRecord(cookie: "cp_session=abc123"))
        let (client, _) = makeClient(store: store)
        let result = try await client.enqueueGithubMutation(
            workspaceId: "ws_1",
            request: GithubMutationRequest(
                idempotencyKey: "key_1", approvalId: "appr_1", repository: "o/repo",
                runId: nil, operation: .commentIssue, arguments: [:]
            )
        )
        XCTAssertEqual(result.replayed, false)
    }

    func testErrorDecodesApiEnvelope() async throws {
        MockURLProtocol.handler = { _ in
            MockURLProtocol.StubResponse(
                status: 422,
                json: #"{"error":{"code":"VALIDATION_ERROR","message":"Invalid workspace","requestId":"req_9"}}"#
            )
        }

        let store = InMemorySessionStore()
        try await store.save(SessionRecord(cookie: "cp_session=abc123"))
        let (client, _) = makeClient(store: store)

        do {
            _ = try await client.createWorkspace(name: "x")
            XCTFail("expected ControlPlaneError")
        } catch let error as ControlPlaneError {
            XCTAssertEqual(error.status, 422)
            XCTAssertEqual(error.code, "VALIDATION_ERROR")
            XCTAssertEqual(error.message, "Invalid workspace")
        }
    }

    func test401ClearsSessionAndInvokesCallback() async throws {
        MockURLProtocol.handler = { _ in MockURLProtocol.StubResponse(status: 401, json: #"{"error":{"code":"SESSION_REQUIRED","message":"Sign in","requestId":"r"}}"#) }

        final class Box: @unchecked Sendable { var called = false }
        let box = Box()

        let store = InMemorySessionStore()
        try await store.save(SessionRecord(cookie: "cp_session=abc123"))
        let client = ControlPlaneClient(
            baseURL: baseURL,
            sessionStore: store,
            session: TestSupport.makeSession(),
            onUnauthorized: { box.called = true }
        )

        do {
            _ = try await client.getRooms()
            XCTFail("expected ControlPlaneError")
        } catch let error as ControlPlaneError {
            XCTAssertEqual(error.status, 401)
        }
        let afterLoad = try await store.load()
        XCTAssertNil(afterLoad)
        XCTAssertEqual(box.called, true)
    }
}
