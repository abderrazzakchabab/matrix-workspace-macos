import XCTest
@testable import MatrixWorkspaceCore

final class RunEventStreamTests: XCTestCase {
    private let baseURL = URL(string: "https://control.example")!

    override func setUp() {
        super.setUp()
        MockURLProtocol.lastRequest = nil
        MockURLProtocol.handler = nil
    }

    private func authenticatedStore() async throws -> InMemorySessionStore {
        let store = InMemorySessionStore()
        try await store.save(SessionRecord(cookie: "cp_session=abc123"))
        return store
    }

    private func collect(_ connection: RunEventConnection) async throws -> [RunEvent] {
        var events: [RunEvent] = []
        for try await event in connection.stream {
            events.append(event)
        }
        return events
    }

    func testHappyPathYieldsEventsInOrderUntilTerminal() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "cp_session=abc123")
            let body = TestSupport.sseBody([
                (1, "run.started"), (2, "specialist.progress"), (3, "run.completed")
            ])
            return MockURLProtocol.StubResponse(status: 200, headers: ["Content-Type": "text/event-stream"], body: Data(body.utf8))
        }

        let store = try await authenticatedStore()
        let stream = TestSupport.makeStream(baseURL: baseURL, store: store, session: TestSupport.makeSession())
        let events = try await collect(stream.connect(runId: "run_1", from: 0))

        XCTAssertEqual(events.map { $0.sequence }, [1, 2, 3])
        XCTAssertEqual(events.last?.eventType, .runCompleted)
    }

    func testResumeSendsAfterQueryAndLastEventId() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/runs/run_1/events")
            let after = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "after" })?.value
            XCTAssertEqual(after, "7")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Last-Event-ID"), "7")
            let body = TestSupport.sseBody([(8, "run.completed")])
            return MockURLProtocol.StubResponse(status: 200, body: Data(body.utf8))
        }

        let store = try await authenticatedStore()
        let stream = TestSupport.makeStream(baseURL: baseURL, store: store, session: TestSupport.makeSession())
        let events = try await collect(stream.connect(runId: "run_1", from: 7))

        XCTAssertEqual(events.map { $0.sequence }, [8])
    }

    func testSkipsMalformedFrames() async throws {
        MockURLProtocol.handler = { _ in
            let body = ": keepalive\n\nid: not-a-number\ndata: {}\n\n"
                + TestSupport.sseBody([(1, "run.started"), (2, "run.completed")])
            return MockURLProtocol.StubResponse(status: 200, body: Data(body.utf8))
        }

        let store = try await authenticatedStore()
        let stream = TestSupport.makeStream(baseURL: baseURL, store: store, session: TestSupport.makeSession())
        let events = try await collect(stream.connect(runId: "run_1", from: 0))

        XCTAssertEqual(events.map { $0.sequence }, [1, 2])
    }

    func test401ExpiresSessionAndEndsEmpty() async throws {
        MockURLProtocol.handler = { _ in
            MockURLProtocol.StubResponse(status: 401, body: Data())
        }

        final class Box: @unchecked Sendable { var called = false }
        let box = Box()

        let store = try await authenticatedStore()
        let stream = TestSupport.makeStream(
            baseURL: baseURL,
            store: store,
            session: TestSupport.makeSession(),
            onUnauthorized: { box.called = true }
        )
        let events = try await collect(stream.connect(runId: "run_1", from: 0))

        XCTAssertTrue(events.isEmpty)
        let afterLoad = try await store.load()
        XCTAssertNil(afterLoad)
        XCTAssertEqual(box.called, true)
    }

    func testNonRetryableStatusEndsWithoutEvents() async throws {
        MockURLProtocol.handler = { _ in MockURLProtocol.StubResponse(status: 404, body: Data()) }

        let store = try await authenticatedStore()
        let stream = TestSupport.makeStream(baseURL: baseURL, store: store, session: TestSupport.makeSession())
        let events = try await collect(stream.connect(runId: "run_1", from: 0))

        XCTAssertTrue(events.isEmpty)
    }

    func testReconnectsAfterRetryableFailure() async throws {
        var calls = 0
        MockURLProtocol.handler = { _ in
            calls += 1
            if calls == 1 {
                return MockURLProtocol.StubResponse(status: 500, body: Data())
            }
            let body = TestSupport.sseBody([(1, "run.completed")])
            return MockURLProtocol.StubResponse(status: 200, body: Data(body.utf8))
        }

        let store = try await authenticatedStore()
        let stream = TestSupport.makeStream(baseURL: baseURL, store: store, session: TestSupport.makeSession())
        let events = try await collect(stream.connect(runId: "run_1", from: 0))

        XCTAssertEqual(events.map { $0.sequence }, [1])
        XCTAssertGreaterThanOrEqual(calls, 2)
    }
}
