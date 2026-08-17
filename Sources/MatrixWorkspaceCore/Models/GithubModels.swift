import Foundation

// MARK: - GitHub write scope / operations

/// A GitHub write grant scope. Serializes to `issues:write` / `pull_requests:write`.
public enum GithubWriteScope: String, Codable, Sendable, Equatable {
    case issuesWrite = "issues:write"
    case pullRequestsWrite = "pull_requests:write"
}

public enum GithubMutationOperation: String, Codable, Sendable, Equatable {
    case createIssue = "create_issue"
    case updateIssue = "update_issue"
    case commentIssue = "comment_issue"
    case createPRComment = "create_pr_comment"
}

// MARK: - Keyset-paginated page

public struct GithubPage<T: Codable & Sendable & Equatable>: Codable, Sendable, Equatable {
    public let items: [T]
    public let nextCursor: String?

    public init(items: [T], nextCursor: String?) {
        self.items = items
        self.nextCursor = nextCursor
    }
}

// MARK: - Read summaries

public struct GithubRepositorySummary: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let fullName: String
    public let owner: String
    public let isPrivate: Bool
    public let defaultBranch: String
    public let description: String?
    public let htmlUrl: String
    public let archived: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, fullName, owner, isPrivate = "private", defaultBranch, description, htmlUrl, archived
    }
}

public struct GithubIssueSummary: Codable, Sendable, Equatable {
    public let id: Int
    public let number: Int
    public let title: String
    public let state: String
    public let author: String?
    public let labels: [String]
    public let htmlUrl: String
    public let createdAt: String
    public let updatedAt: String
}

public struct GithubPullRequestSummary: Codable, Sendable, Equatable {
    public let id: Int
    public let number: Int
    public let title: String
    public let state: String
    public let draft: Bool
    public let author: String?
    public let head: String
    public let base: String
    public let htmlUrl: String
    public let createdAt: String
    public let updatedAt: String
}

// MARK: - Write-flow results

public struct GithubWriteGrantResult: Codable, Sendable, Equatable {
    public let grantId: String
    public let status: String
    public let repository: String
    public let scope: GithubWriteScope
}

public enum ApprovalDecision: String, Codable, Sendable, Equatable {
    case approved
    case denied
}

public struct RunApprovalResult: Codable, Sendable, Equatable {
    public let approvalId: String
    public let status: String
    public let expiresAt: String
    public let scope: GithubWriteScope
}

/// Wire response to a mutation enqueue (HTTP 202 for new, 200 for replay).
public struct GithubMutationEnqueueResponse: Codable, Sendable, Equatable {
    public let commandId: String
    public let status: String
}

/// The client-computed result: `replayed` is derived from the HTTP status.
public struct GithubMutationResult: Sendable, Equatable {
    public let commandId: String
    public let status: String
    public let replayed: Bool

    public init(commandId: String, status: String, replayed: Bool) {
        self.commandId = commandId
        self.status = status
        self.replayed = replayed
    }
}

// MARK: - Audit trail

public struct AuditRecordItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let actorMatrixId: String?
    public let scope: String?
    public let repository: String?
    public let operation: String?
    public let approvalId: String?
    public let commandId: String?
    public let outcome: String
    public let details: [String: JSONValue]
    public let createdAt: String
}
