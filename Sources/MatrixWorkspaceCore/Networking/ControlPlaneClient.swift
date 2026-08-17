import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A structured control-plane error: HTTP status plus the optional uniform
/// `{error:{code,message,requestId}}` payload.
public struct ControlPlaneError: Error, CustomStringConvertible, Equatable {
    public let status: Int
    public let code: String?
    public let message: String

    public init(status: Int, code: String?, message: String) {
        self.status = status
        self.code = code
        self.message = message
    }

    public var description: String { message }
}

// MARK: - Wire request bodies

struct MatrixSessionRequest: Encodable {
    let homeserverUrl: String
    let accessToken: String
}

struct CreateWorkspaceRequest: Encodable {
    let name: String
    let policy: [String: JSONValue]
}

struct BindRoomRequest: Encodable {
    let workspaceId: String
}

struct LaunchRunRequest: Encodable {
    let prompt: String
    let mode: RunMode
    let specialistIds: [String]
    let roomId: String?
    let githubContext: GithubContext?
    let idempotencyKey: String
}

struct GithubWriteGrantRequest: Encodable {
    let repository: String
    let scope: GithubWriteScope
}

struct RunApprovalRequest: Encodable {
    let approvalType: String
    let scope: GithubWriteScope
    let decision: ApprovalDecision
    let confirmationText: String
    let commandHash: String
}

public struct GithubMutationRequest: Encodable, Sendable {
    public let idempotencyKey: String
    public let approvalId: String
    public let repository: String
    public let runId: String?
    public let operation: GithubMutationOperation
    public let arguments: [String: JSONValue]

    public init(
        idempotencyKey: String,
        approvalId: String,
        repository: String,
        runId: String?,
        operation: GithubMutationOperation,
        arguments: [String: JSONValue]
    ) {
        self.idempotencyKey = idempotencyKey
        self.approvalId = approvalId
        self.repository = repository
        self.runId = runId
        self.operation = operation
        self.arguments = arguments
    }
}

struct RoomsResponse: Decodable {
    let rooms: [RoomSummary]
}

struct RunDetailResponse: Decodable {
    let runId: String
    let matrixDeliveries: [RunMatrixDelivery]
}

// MARK: - Client

/// HTTP client for the Matrix Agent Workspace control plane.
///
/// Cookie auth model: `createMatrixSession` stores the `Set-Cookie` value; every
/// authenticated request sends it as a `Cookie` header. Any `401` clears the
/// session and invokes `onUnauthorized`.
public final class ControlPlaneClient: @unchecked Sendable {
    public let baseURL: URL
    public let sessionStore: SessionStore

    private let session: URLSession
    private let onUnauthorized: (@Sendable () -> Void)?

    public init(
        baseURL: URL,
        sessionStore: SessionStore,
        session: URLSession = .shared,
        onUnauthorized: (@Sendable () -> Void)? = nil
    ) {
        self.baseURL = baseURL
        self.sessionStore = sessionStore
        self.session = session
        self.onUnauthorized = onUnauthorized
    }

    // MARK: Auth

    /// `POST /api/auth/matrix/session` — exchange a Matrix access token for a
    /// control-plane session cookie.
    public func createMatrixSession(homeserverUrl: String, accessToken: String) async throws -> MatrixSessionResponse {
        var request = URLRequest(url: url("api/auth/matrix/session"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            MatrixSessionRequest(homeserverUrl: homeserverUrl, accessToken: accessToken)
        )

        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        let body = try Self.decode(MatrixSessionResponse.self, from: data, response: response)

        guard let cookie = Self.sessionCookie(from: http) else {
            throw ControlPlaneError(
                status: http?.statusCode ?? 0,
                code: "SESSION_REFERENCE_MISSING",
                message: "The control plane did not return a session reference"
            )
        }
        try await sessionStore.save(SessionRecord(cookie: cookie))
        return body
    }

    // MARK: Workspaces & rooms

    /// `POST /api/workspaces` — create a workspace with the fixed read-only
    /// policy the mobile client uses. There is no list endpoint; callers track
    /// created workspaces locally.
    public func createWorkspace(name: String) async throws -> WorkspaceSelection {
        let policy: [String: JSONValue] = [
            "readOnly": .bool(true),
            "failurePolicy": .string("partial"),
            "promptInjectionMode": .string("fail_run"),
        ]
        let body = try JSONEncoder().encode(
            CreateWorkspaceRequest(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                policy: policy
            )
        )
        let (data, response) = try await authenticatedRequest(url("api/workspaces"), method: "POST", body: body)
        return try Self.decode(WorkspaceSelection.self, from: data, response: response)
    }

    /// `GET /api/rooms` — rooms the Matrix user has joined plus known bindings.
    public func getRooms() async throws -> [RoomSummary] {
        let (data, response) = try await authenticatedRequest(url("api/rooms"))
        return try Self.decode(RoomsResponse.self, from: data, response: response).rooms
    }

    /// `POST /api/rooms/:roomId/binding` — bind a Matrix room to a workspace.
    public func bindRoom(roomId: String, workspaceId: String) async throws -> RoomBinding {
        let body = try JSONEncoder().encode(BindRoomRequest(workspaceId: workspaceId))
        let (data, response) = try await authenticatedRequest(
            url("api/rooms/\(Self.pathComponent(roomId))/binding"),
            method: "POST",
            body: body
        )
        return try Self.decode(RoomBinding.self, from: data, response: response)
    }

    // MARK: Runs

    /// `POST /api/workspaces/:workspaceId/runs` — launch a run.
    public func launchRun(workspaceId: String, request: RunRequest, idempotencyKey: String) async throws -> RunResponse {
        let body = try JSONEncoder().encode(
            LaunchRunRequest(
                prompt: request.prompt,
                mode: request.mode,
                specialistIds: request.specialistIds,
                roomId: request.roomId,
                githubContext: request.githubContext,
                idempotencyKey: idempotencyKey
            )
        )
        let (data, response) = try await authenticatedRequest(
            url("api/workspaces/\(Self.pathComponent(workspaceId))/runs"),
            method: "POST",
            body: body
        )
        return try Self.decode(RunResponse.self, from: data, response: response)
    }

    /// `POST /api/runs/:runId/cancel` — request cancellation.
    public func cancelRun(runId: String) async throws -> CancellationResponse {
        let (data, response) = try await authenticatedRequest(
            url("api/runs/\(Self.pathComponent(runId))/cancel"),
            method: "POST"
        )
        return try Self.decode(CancellationResponse.self, from: data, response: response)
    }

    /// `GET /api/runs/:runId` — run detail plus Matrix delivery status.
    public func getRunMatrixDeliveries(runId: String) async throws -> RunMatrixDeliveriesResponse {
        let (data, response) = try await authenticatedRequest(url("api/runs/\(Self.pathComponent(runId))"))
        let detail = try Self.decode(RunDetailResponse.self, from: data, response: response)
        return RunMatrixDeliveriesResponse(runId: detail.runId, deliveries: detail.matrixDeliveries)
    }

    // MARK: GitHub read

    public func listGithubRepositories(
        workspaceId: String,
        installationId: String,
        cursor: String? = nil
    ) async throws -> GithubPage<GithubRepositorySummary> {
        let (data, response) = try await authenticatedRequest(
            githubReadURL(path: "api/github/repositories", workspaceId: workspaceId, installationId: installationId, cursor: cursor)
        )
        return try Self.decode(GithubPage<GithubRepositorySummary>.self, from: data, response: response)
    }

    public func listGithubIssues(
        workspaceId: String,
        installationId: String,
        owner: String,
        repo: String,
        cursor: String? = nil
    ) async throws -> GithubPage<GithubIssueSummary> {
        let path = "api/github/repositories/\(Self.pathComponent(owner))/\(Self.pathComponent(repo))/issues"
        let (data, response) = try await authenticatedRequest(
            githubReadURL(path: path, workspaceId: workspaceId, installationId: installationId, cursor: cursor)
        )
        return try Self.decode(GithubPage<GithubIssueSummary>.self, from: data, response: response)
    }

    public func listGithubPullRequests(
        workspaceId: String,
        installationId: String,
        owner: String,
        repo: String,
        cursor: String? = nil
    ) async throws -> GithubPage<GithubPullRequestSummary> {
        let path = "api/github/repositories/\(Self.pathComponent(owner))/\(Self.pathComponent(repo))/pulls"
        let (data, response) = try await authenticatedRequest(
            githubReadURL(path: path, workspaceId: workspaceId, installationId: installationId, cursor: cursor)
        )
        return try Self.decode(GithubPage<GithubPullRequestSummary>.self, from: data, response: response)
    }

    // MARK: GitHub write flow

    /// `POST /api/workspaces/:workspaceId/github-grants` — request a write grant.
    public func requestGithubWriteGrant(
        workspaceId: String,
        repository: String,
        scope: GithubWriteScope
    ) async throws -> GithubWriteGrantResult {
        let body = try JSONEncoder().encode(GithubWriteGrantRequest(repository: repository, scope: scope))
        let (data, response) = try await authenticatedRequest(
            url("api/workspaces/\(Self.pathComponent(workspaceId))/github-grants"),
            method: "POST",
            body: body
        )
        return try Self.decode(GithubWriteGrantResult.self, from: data, response: response)
    }

    /// `POST /api/runs/:runId/approvals` — record an approval/denial.
    public func createRunApproval(
        runId: String,
        scope: GithubWriteScope,
        decision: ApprovalDecision,
        confirmationText: String,
        commandHash: String
    ) async throws -> RunApprovalResult {
        let body = try JSONEncoder().encode(
            RunApprovalRequest(
                approvalType: "github_mutation",
                scope: scope,
                decision: decision,
                confirmationText: confirmationText,
                commandHash: commandHash
            )
        )
        let (data, response) = try await authenticatedRequest(
            url("api/runs/\(Self.pathComponent(runId))/approvals"),
            method: "POST",
            body: body
        )
        return try Self.decode(RunApprovalResult.self, from: data, response: response)
    }

    /// `POST /api/workspaces/:workspaceId/github/mutations` — enqueue a mutation.
    /// 202 = newly queued, 200 = idempotent replay.
    public func enqueueGithubMutation(
        workspaceId: String,
        request: GithubMutationRequest
    ) async throws -> GithubMutationResult {
        let body = try JSONEncoder().encode(request)
        let (data, response) = try await authenticatedRequest(
            url("api/workspaces/\(Self.pathComponent(workspaceId))/github/mutations"),
            method: "POST",
            body: body
        )
        let decoded = try Self.decode(GithubMutationEnqueueResponse.self, from: data, response: response)
        return GithubMutationResult(
            commandId: decoded.commandId,
            status: decoded.status,
            replayed: response.statusCode == 200
        )
    }

    // MARK: Audit

    /// `GET /api/workspaces/:workspaceId/audit` — keyset-paginated audit trail.
    public func listAuditRecords(
        workspaceId: String,
        cursor: String? = nil
    ) async throws -> GithubPage<AuditRecordItem> {
        var components = URLComponents(
            url: baseURL.appending(path: "api/workspaces/\(Self.pathComponent(workspaceId))/audit"),
            resolvingAgainstBaseURL: false
        )!
        if let cursor {
            components.queryItems = [URLQueryItem(name: "cursor", value: cursor)]
        }
        let (data, response) = try await authenticatedRequest(components.url!)
        return try Self.decode(GithubPage<AuditRecordItem>.self, from: data, response: response)
    }

    // MARK: Health

    /// `GET /api/health` — unauthenticated liveness probe.
    public func health() async throws -> Bool {
        let (_, response) = try await session.data(for: URLRequest(url: url("api/health")))
        return (response as? HTTPURLResponse).map { (200 ..< 300).contains($0.statusCode) } ?? false
    }

    // MARK: Internals

    private func url(_ path: String) -> URL {
        baseURL.appending(path: path)
    }

    private func githubReadURL(
        path: String,
        workspaceId: String,
        installationId: String,
        cursor: String?
    ) -> URL {
        var components = URLComponents(
            url: baseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        )!
        var query = [
            URLQueryItem(name: "workspaceId", value: workspaceId),
            URLQueryItem(name: "installationId", value: installationId),
        ]
        if let cursor {
            query.append(URLQueryItem(name: "cursor", value: cursor))
        }
        components.queryItems = query
        return components.url!
    }

    private func authenticatedRequest(
        _ url: URL,
        method: String = "GET",
        body: Data? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        guard let record = try await sessionStore.load() else {
            await clearSession()
            throw ControlPlaneError(status: 401, code: "SESSION_REQUIRED", message: "Sign in again to continue")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(record.cookie, forHTTPHeaderField: "Cookie")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ControlPlaneError(status: 0, code: nil, message: "Non-HTTP response")
        }
        if http.statusCode == 401 {
            await clearSession()
        }
        return (data, http)
    }

    private func clearSession() async {
        try? await sessionStore.clear()
        onUnauthorized?()
    }

    private static func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        response: URLResponse
    ) throws -> T {
        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            let apiError = try? JSONDecoder().decode(ApiErrorEnvelope.self, from: data)
            throw ControlPlaneError(
                status: http.statusCode,
                code: apiError?.error.code,
                message: apiError?.error.message ?? "Control plane request failed (\(http.statusCode))"
            )
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func sessionCookie(from response: HTTPURLResponse?) -> String? {
        guard let setCookie = response?.value(forHTTPHeaderField: "Set-Cookie") else { return nil }
        return setCookie
            .split(separator: ";", maxSplits: 1)
            .first
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static func pathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
