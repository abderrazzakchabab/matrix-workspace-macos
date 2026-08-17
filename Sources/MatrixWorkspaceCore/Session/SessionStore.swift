import Foundation

/// The control-plane session reference: the cookie returned by
/// `POST /api/auth/matrix/session` (first `name=value` segment of `Set-Cookie`).
public struct SessionRecord: Codable, Sendable, Equatable {
    public let cookie: String

    public init(cookie: String) {
        self.cookie = cookie
    }
}

/// Persists the control-plane session cookie. `KeychainSessionStore` backs the
/// macOS app; `InMemorySessionStore` is used by tests and the Linux core.
public protocol SessionStore: Sendable {
    func load() async throws -> SessionRecord?
    func save(_ record: SessionRecord) async throws
    func clear() async throws
}

/// Thread-safe, non-persistent store. Exported for tests and for callers that
/// manage persistence elsewhere.
public actor InMemorySessionStore: SessionStore {
    private var record: SessionRecord?

    public init() {}

    public func load() async throws -> SessionRecord? {
        record
    }

    public func save(_ record: SessionRecord) async throws {
        self.record = record
    }

    public func clear() async throws {
        record = nil
    }
}
