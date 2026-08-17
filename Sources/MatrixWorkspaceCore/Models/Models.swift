import Foundation

// MARK: - Uniform API error

/// Every control-plane endpoint returns this envelope on failure.
public struct ApiErrorInfo: Codable, Sendable, Equatable {
    public let code: String
    public let message: String
    public let requestId: String
    public let details: [String: JSONValue]?

    public init(code: String, message: String, requestId: String, details: [String: JSONValue]? = nil) {
        self.code = code
        self.message = message
        self.requestId = requestId
        self.details = details
    }
}

public struct ApiErrorEnvelope: Codable, Sendable, Equatable {
    public let error: ApiErrorInfo
}

// MARK: - Matrix session

public struct MatrixUser: Codable, Sendable, Equatable {
    public let id: String
    public let homeserverUrl: String
}

public struct MatrixSessionResponse: Codable, Sendable, Equatable {
    public let user: MatrixUser
    public let sessionExpiresAt: String
}

// MARK: - Workspaces and rooms

public struct WorkspaceSelection: Codable, Sendable, Equatable {
    public let workspaceId: String
    public let name: String
    public let ownerId: String
    public let status: String
    public let createdAt: String
}

public struct RoomSummary: Codable, Sendable, Equatable {
    public let roomId: String
    public let homeserverUrl: String
    public let displayName: String?
    public let workspaceId: String?
}

public struct RoomBinding: Codable, Sendable, Equatable {
    public let roomId: String
    public let workspaceId: String
}
