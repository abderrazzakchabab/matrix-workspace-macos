import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MatrixWorkspaceCore

/// A static, request-capturing URLProtocol used to drive `URLSession` in tests.
///
/// Tests set `MockURLProtocol.handler` before issuing a request, then build a
/// `URLSession` whose `protocolClasses` contains this type.
final class MockURLProtocol: URLProtocol {
    struct StubResponse {
        let status: Int
        let headers: [String: String]
        let body: Data

        init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
            self.status = status
            self.headers = headers
            self.body = body
        }

        init(status: Int, headers: [String: String] = [:], json: String) {
            self.init(status: status, headers: headers, body: Data(json.utf8))
        }
    }

    /// Handler returns the response for a request, or `nil` to fail the request.
    static var handler: ((URLRequest) -> StubResponse?)?

    /// The most recently received request, captured during `startLoading`.
    static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockURLProtocol.lastRequest = request

        guard let stub = MockURLProtocol.handler?(request) else {
            client?.urlProtocol(
                self,
                didFailWithError: NSError(domain: NSURLErrorDomain, code: NSURLErrorBadURL)
            )
            return
        }

        if let url = request.url,
           let http = HTTPURLResponse(
               url: url,
               statusCode: stub.status,
               httpVersion: "HTTP/1.1",
               headerFields: stub.headers
           ) {
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        }
        if !stub.body.isEmpty {
            client?.urlProtocol(self, didLoad: stub.body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

enum TestSupport {
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func makeStream(
        baseURL: URL = URL(string: "https://control.example")!,
        store: SessionStore,
        session: URLSession,
        onUnauthorized: (@Sendable () -> Void)? = nil,
        configuration: RunEventStream.Configuration = .init(
            baseDelayMs: 1,
            maxDelayMs: 2,
            random: { 0.0 }
        )
    ) -> RunEventStream {
        RunEventStream(
            baseURL: baseURL,
            sessionStore: store,
            session: session,
            onUnauthorized: onUnauthorized,
            configuration: configuration
        )
    }

    /// Builds a run-event JSON object (as used in an SSE `data:` frame payload).
    static func eventJSON(
        id: String,
        runId: String,
        sequence: Int,
        type: String
    ) -> String {
        """
        {"id":"\(id)","runId":"\(runId)","sequence":\(sequence),"type":"\(type)","version":1,"occurredAt":"2026-08-17T00:00:00.000Z","visibility":"room_and_owner","payload":{}}
        """
    }

    /// Builds a complete SSE response body from `id`/`type` pairs.
    static func sseBody(_ events: [(sequence: Int, type: String)], runId: String = "run_1") -> String {
        events.map {
            "id: \($0.sequence)\nevent: \($0.type)\ndata: \(eventJSON(id: "ev_\($0.sequence)", runId: runId, sequence: $0.sequence, type: $0.type))\n\n"
        }.joined()
    }
}
