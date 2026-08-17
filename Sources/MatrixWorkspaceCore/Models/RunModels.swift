import Foundation

// MARK: - Run request / response

public enum RunMode: String, Codable, Sendable, Equatable {
    case parallel
    case sequential
}

/// Optional GitHub context attached to a run.
public struct GithubContext: Codable, Sendable, Equatable {
    public let repository: String

    public init(repository: String) {
        self.repository = repository
    }
}

/// The run-creation body, mirroring `packages/contracts/src/run.ts` (RunRequest).
public struct RunRequest: Codable, Sendable, Equatable {
    public let prompt: String
    public let mode: RunMode
    public let specialistIds: [String]
    public let roomId: String?
    public let githubContext: GithubContext?

    public init(
        prompt: String,
        mode: RunMode,
        specialistIds: [String],
        roomId: String? = nil,
        githubContext: GithubContext? = nil
    ) {
        self.prompt = prompt
        self.mode = mode
        self.specialistIds = specialistIds
        self.roomId = roomId
        self.githubContext = githubContext
    }
}

public enum RunStatus: String, Codable, Sendable, Equatable {
    case queued
    case running
    case cancelling
    case completed
    case failed
    case cancelled
    case partial
}

public struct RunResponse: Codable, Sendable, Equatable {
    public let runId: String
    public let status: RunStatus
    public let roomId: String?
    public let nextSequence: Int
}

public struct CancellationResponse: Codable, Sendable, Equatable {
    public let runId: String
    public let status: String
}

// MARK: - Run events

/// The 18 run-event type strings, mirroring `RUN_EVENT_TYPES` in `events.ts`.
public enum RunEventType: String, Sendable, CaseIterable {
    case runQueued = "run.queued"
    case runStarted = "run.started"
    case specialistStarted = "specialist.started"
    case specialistProgress = "specialist.progress"
    case specialistCompleted = "specialist.completed"
    case specialistFailed = "specialist.failed"
    case runPartial = "run.partial"
    case runCheckpointed = "run.checkpointed"
    case runRetryScheduled = "run.retry_scheduled"
    case runCancellationRequested = "run.cancellation_requested"
    case runCancelled = "run.cancelled"
    case runCompleted = "run.completed"
    case runFailed = "run.failed"
    case approvalRequested = "approval.requested"
    case approvalRecorded = "approval.recorded"
    case mutationQueued = "mutation.queued"
    case mutationCompleted = "mutation.completed"
    case mutationFailed = "mutation.failed"

    /// Event types that end a run and stop the event stream.
    public static let terminal: Set<RunEventType> = [
        .runPartial, .runCompleted, .runFailed, .runCancelled
    ]
}

/// A single durable run event, mirroring the `RunEvent` zod schema in `events.ts`.
public struct RunEvent: Codable, Sendable, Equatable {
    public let id: String
    public let runId: String
    public let sequence: Int
    public let type: String
    public let version: Int
    public let occurredAt: String
    public let visibility: String
    public let payload: [String: JSONValue]

    public var eventType: RunEventType? { RunEventType(rawValue: type) }
    public var isTerminal: Bool { eventType.map { RunEventType.terminal.contains($0) } ?? false }

    public init(
        id: String,
        runId: String,
        sequence: Int,
        type: String,
        version: Int,
        occurredAt: String,
        visibility: String,
        payload: [String: JSONValue]
    ) {
        self.id = id
        self.runId = runId
        self.sequence = sequence
        self.type = type
        self.version = version
        self.occurredAt = occurredAt
        self.visibility = visibility
        self.payload = payload
    }
}

// MARK: - Matrix delivery status

public enum MatrixDeliveryStatus: String, Codable, Sendable, Equatable {
    case pending
    case delivered
    case failed
    case dead
}

public struct RunMatrixDelivery: Codable, Sendable, Equatable {
    public let sequence: Int
    public let status: MatrixDeliveryStatus
}

public struct RunMatrixDeliveriesResponse: Codable, Sendable, Equatable {
    public let runId: String
    public let deliveries: [RunMatrixDelivery]
}
