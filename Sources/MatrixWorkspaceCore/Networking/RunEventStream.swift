import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A live run-event connection: an async stream of `RunEvent` plus a cancel
/// handle. Dropping the connection cancels the underlying task.
public final class RunEventConnection: @unchecked Sendable {
    public let stream: AsyncThrowingStream<RunEvent, Error>
    private let task: Task<Void, Never>

    init(stream: AsyncThrowingStream<RunEvent, Error>, task: Task<Void, Never>) {
        self.stream = stream
        self.task = task
    }

    deinit { task.cancel() }

    public func cancel() { task.cancel() }
}

/// Streaming client for `GET /api/runs/:runId/events`.
///
/// Reconnects with exponential backoff + jitter after a non-terminal end or a
/// retryable failure (429/5xx), resumes from the highest sequence seen, and
/// stops on the first terminal event.
public final class RunEventStream: @unchecked Sendable {
    public struct Configuration: Sendable {
        public var baseDelayMs: Int
        public var maxDelayMs: Int
        public var random: @Sendable () -> Double

        public init(
            baseDelayMs: Int = 500,
            maxDelayMs: Int = 8_000,
            random: @Sendable @escaping () -> Double = { Double.random(in: 0 ..< 1) }
        ) {
            self.baseDelayMs = baseDelayMs
            self.maxDelayMs = maxDelayMs
            self.random = random
        }
    }

    private let baseURL: URL
    private let sessionStore: SessionStore
    private let session: URLSession
    private let onUnauthorized: (@Sendable () -> Void)?
    private let configuration: Configuration

    public init(
        baseURL: URL,
        sessionStore: SessionStore,
        session: URLSession = .shared,
        onUnauthorized: (@Sendable () -> Void)? = nil,
        configuration: Configuration = Configuration()
    ) {
        self.baseURL = baseURL
        self.sessionStore = sessionStore
        self.session = session
        self.onUnauthorized = onUnauthorized
        self.configuration = configuration
    }

    public func connect(runId: String, from after: Int) -> RunEventConnection {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: RunEvent.self)
        let task = Task {
            await self.run(runId: runId, after: after, continuation: continuation)
        }
        return RunEventConnection(stream: stream, task: task)
    }

    // MARK: Connection loop

    private func run(
        runId: String,
        after initialAfter: Int,
        continuation: AsyncThrowingStream<RunEvent, Error>.Continuation
    ) async {
        var after = initialAfter
        var reconnectAttempt = 0
        var terminalReceived = false
        defer { continuation.finish() }

        while !Task.isCancelled && !terminalReceived {
            do {
                try Task.checkCancellation()

                guard let record = try await sessionStore.load() else {
                    await expire()
                    return
                }

                var components = URLComponents(
                    url: baseURL.appending(path: "api/runs/\(Self.pathComponent(runId))/events"),
                    resolvingAgainstBaseURL: false
                )!
                components.queryItems = [URLQueryItem(name: "after", value: String(after))]
                var request = URLRequest(url: components.url!)
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                request.setValue(record.cookie, forHTTPHeaderField: "Cookie")
                if after > 0 {
                    request.setValue(String(after), forHTTPHeaderField: "Last-Event-ID")
                }

                // `URLSession.data(for:)` is the one async response API present
                // on both Apple platforms and Linux corelibs-foundation (where
                // `bytes(for:)` is unavailable). The control plane's SSE route
                // ends the response at the terminal event, so the whole frame
                // batch arrives here and is processed in order.
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { return }

                if http.statusCode == 401 {
                    await expire()
                    return
                }
                guard http.statusCode == 200 else {
                    if http.statusCode == 429 || http.statusCode >= 500 {
                        try await backoff(&reconnectAttempt)
                        continue
                    }
                    return
                }

                var decoder = SSEFrameDecoder()
                for raw in decoder.push(data) {
                    guard let frame = SSE.parseFrame(raw),
                          let event = SSE.event(from: frame, expectedRunId: runId) else {
                        continue
                    }
                    continuation.yield(event)
                    after = max(after, event.sequence)
                    reconnectAttempt = 0
                    terminalReceived = event.isTerminal
                }

                if Task.isCancelled || terminalReceived { continue }

                // Stream ended without a terminal event: flush any partial frame
                // and reconnect.
                if let raw = decoder.flushRemaining(),
                   let frame = SSE.parseFrame(raw),
                   let event = SSE.event(from: frame, expectedRunId: runId) {
                    continuation.yield(event)
                    after = max(after, event.sequence)
                    terminalReceived = event.isTerminal
                }
                if !terminalReceived {
                    try await backoff(&reconnectAttempt)
                }
            } catch is CancellationError {
                return
            } catch {
                if !Task.isCancelled {
                    try? await backoff(&reconnectAttempt)
                }
            }
        }
    }

    private func backoff(_ attempt: inout Int) async throws {
        try Task.checkCancellation()
        let delayMs = connectBackoffDelay(
            attempt: attempt,
            baseDelayMs: configuration.baseDelayMs,
            maxDelayMs: configuration.maxDelayMs,
            random: configuration.random()
        )
        attempt = min(attempt + 1, 30)
        try await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
    }

    private func expire() async {
        try? await sessionStore.clear()
        onUnauthorized?()
    }

    private static func pathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
