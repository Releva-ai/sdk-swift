import Foundation

/// A `URLProtocol` that answers every request from a handler installed by the test.
///
/// Injecting `StubURLProtocol.makeSession()` into `NetworkService` keeps the real
/// `URLSession` plumbing in play — URL, method, headers, body, status-code handling —
/// while guaranteeing no test performs real network I/O.
///
/// Call `stub(_:)` in the test and `reset()` in `tearDown`.
final class StubURLProtocol: URLProtocol {

    /// What the stub answers a request with.
    enum Stub {
        /// An HTTP response with this status code and body.
        case response(statusCode: Int, body: Data)
        /// A transport-level failure, as `URLSession` surfaces it (no HTTP response).
        case failure(Error)
    }

    enum StubError: Error {
        /// A request was made but the test installed no handler.
        case notStubbed(URLRequest)
        /// The stubbed status code / URL could not be turned into an `HTTPURLResponse`.
        case malformedStub(URLRequest)
    }

    private static let lock = NSLock()
    private static var handler: ((URLRequest) -> Stub)?
    private static var requests: [URLRequest] = []

    // MARK: - Test API

    /// A session that routes every request through this protocol.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    /// Install the handler for the current test and clear any recorded requests.
    static func stub(_ handler: @escaping (URLRequest) -> Stub) {
        lock.lock()
        defer { lock.unlock() }
        self.handler = handler
        requests = []
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        handler = nil
        requests = []
    }

    /// The requests served so far, in the order they started loading, each with its
    /// body in `httpBody`.
    static var receivedRequests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    /// `URLSession` moves `httpBody` into `httpBodyStream` before handing the request
    /// to a protocol, and that stream is only readable while the load is in flight, so
    /// the body is read here and folded back into the recorded copy.
    private static func record(_ request: URLRequest) -> Stub {
        var recorded = request
        if recorded.httpBody == nil, let stream = request.httpBodyStream {
            recorded.httpBody = drain(stream)
        }

        lock.lock()
        requests.append(recorded)
        let handler = self.handler
        lock.unlock()

        guard let handler = handler else { return .failure(StubError.notStubbed(recorded)) }
        return handler(recorded)
    }

    private static func drain(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        switch StubURLProtocol.record(request) {
        case .response(let statusCode, let body):
            guard let url = request.url,
                  let response = HTTPURLResponse(
                      url: url,
                      statusCode: statusCode,
                      httpVersion: "HTTP/1.1",
                      headerFields: nil
                  ) else {
                client?.urlProtocol(self, didFailWithError: StubError.malformedStub(request))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)

        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        // Nothing to cancel: responses are delivered synchronously in startLoading().
    }
}
