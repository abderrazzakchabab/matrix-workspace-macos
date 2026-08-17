import Foundation

/// One parsed Server-Sent-Events frame (`id`, `event`, and `data` joined with
/// newlines). Mirrors `parseSseFrame` in the mobile client's `run-events.ts`.
public struct SSEFrame: Sendable, Equatable {
    public let id: String?
    public let event: String?
    public let data: String

    public init(id: String?, event: String?, data: String) {
        self.id = id
        self.event = event
        self.data = data
    }
}

public enum SSE {
    /// Parse a raw SSE frame into its `id` / `event` / `data` fields.
    ///
    /// Field values are taken after an optional single leading space; `data`
    /// lines are concatenated with `\n`. A frame with no `data` returns `nil`.
    public static func parseFrame(_ rawFrame: String) -> SSEFrame? {
        var id: String? = nil
        var event: String? = nil
        var dataLines: [String] = []

        let normalized = rawFrame.replacingOccurrences(of: "\r\n", with: "\n")
        for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let line = rawLine
            if line.isEmpty || line.hasPrefix(":") { continue }

            let field: String
            var value: String
            if let separator = line.firstIndex(of: ":") {
                field = String(line[line.startIndex ..< separator])
                value = String(line[line.index(after: separator)...])
                if value.hasPrefix(" ") { value.removeFirst() }
            } else {
                field = line
                value = ""
            }

            switch field {
            case "id":
                if !value.contains("\0") { id = value }
            case "event":
                event = value
            case "data":
                dataLines.append(value)
            default:
                break
            }
        }

        guard !dataLines.isEmpty else { return nil }
        return SSEFrame(id: id, event: event, data: dataLines.joined(separator: "\n"))
    }

    /// Validate a parsed frame against the run-event wire contract and decode it.
    ///
    /// Rejects: a missing/non-digit `id`, a missing `event`, `data` that is not
    /// a run event, a `runId` mismatch, a `sequence` that disagrees with the
    /// frame `id`, or an `event` field that disagrees with `type`. Mirrors
    /// `eventFromFrame` in the mobile client.
    public static func event(from frame: SSEFrame, expectedRunId: String) -> RunEvent? {
        guard let id = frame.id, !id.isEmpty, id.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            return nil
        }
        guard let sequence = Int(id) else { return nil }
        guard let eventField = frame.event else { return nil }
        guard let data = frame.data.data(using: .utf8) else { return nil }
        guard let event = try? JSONDecoder().decode(RunEvent.self, from: data) else { return nil }
        guard event.runId == expectedRunId else { return nil }
        guard event.sequence == sequence else { return nil }
        guard eventField == event.type else { return nil }
        return event
    }
}

/// Incrementally splits a UTF-8 byte stream into complete SSE frames.
///
/// SSE line endings (`\n`, `\r\n`, or `\r`) are normalized to `\n`; a blank
/// line terminates a frame. This is safe at the byte level because `0x0A` and
/// `0x0D` never appear as UTF-8 continuation bytes, so a `\n` boundary never
/// splits a multi-byte character.
public struct SSEFrameDecoder: Sendable {
    private var buffer: [UInt8] = []
    private var pendingCR = false

    public init() {}

    /// Consume one byte; returns the raw bytes of a completed frame, if any.
    public mutating func push(_ byte: UInt8) -> String? {
        if pendingCR {
            pendingCR = false
            if byte == 0x0A {
                return finishLine()          // \r\n -> \n
            }
            buffer.append(0x0D)              // lone \r is literal content (TS parity)
        }
        switch byte {
        case 0x0D:
            pendingCR = true
            return nil
        case 0x0A:
            return finishLine()
        default:
            buffer.append(byte)
            return nil
        }
    }

    /// Consume a sequence of bytes, returning every completed frame.
    public mutating func push<S: Sequence>(_ bytes: S) -> [String] where S.Element == UInt8 {
        var frames: [String] = []
        for byte in bytes {
            if let frame = push(byte) { frames.append(frame) }
        }
        return frames
    }

    /// Flush a trailing partial frame (mirrors the mobile client's flush path).
    public mutating func flushRemaining() -> String? {
        if pendingCR {
            pendingCR = false
            buffer.append(0x0D)
        }
        let remaining = String(decoding: buffer, as: UTF8.self)
        buffer.removeAll(keepingCapacity: true)
        let trimmed = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private mutating func finishLine() -> String? {
        buffer.append(0x0A)
        guard buffer.count >= 2, buffer[buffer.count - 2] == 0x0A else { return nil }
        let frame = String(decoding: buffer.dropLast(2), as: UTF8.self)
        buffer.removeAll(keepingCapacity: true)
        return frame
    }
}

/// Exponential backoff with jitter, mirroring the mobile client's reconnect
/// schedule. `attempt` is capped at 30; the delay is clamped to
/// `[100, maxDelayMs]`.
public func connectBackoffDelay(attempt: Int, baseDelayMs: Int, maxDelayMs: Int, random: Double) -> Int {
    let base = max(baseDelayMs, 100)
    let maxDelay = max(base, maxDelayMs)
    let capped = min(max(attempt, 0), 30)
    let shift = min(capped, 20)   // bound the doubling to avoid overflow
    let exponential = min(maxDelay, base * (1 << shift))
    let jittered = Double(exponential) * (0.5 + min(1, max(0, random)) * 0.5)
    return min(maxDelay, max(100, Int(jittered.rounded())))
}
