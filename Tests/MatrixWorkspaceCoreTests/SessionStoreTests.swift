import XCTest
@testable import MatrixWorkspaceCore

final class SessionStoreTests: XCTestCase {
    func testInMemoryStoreRoundTripsAndClears() async throws {
        let store = InMemorySessionStore()
        let record = SessionRecord(cookie: "cp_session=abc123")

        var loaded = try await store.load()
        XCTAssertNil(loaded)

        try await store.save(record)
        loaded = try await store.load()
        XCTAssertEqual(loaded, record)

        try await store.clear()
        loaded = try await store.load()
        XCTAssertNil(loaded)
    }
}
