import XCTest
@testable import RelevaSDK

/// End-to-end tests for `NetworkService` against a stubbed `URLProtocol`:
/// what goes on the wire (URL, method, headers, body) and how every response
/// class comes back out (success decode, 401, non-2xx, transport failure, retry).
final class NetworkServiceTests: XCTestCase {

    private var session: URLSession!

    /// Held for the lifetime of the test: `NetworkService` captures itself weakly in its
    /// `dataTask` callbacks, so a service that goes out of scope silently never completes.
    private var service: NetworkService!

    override func setUp() {
        super.setUp()
        session = StubURLProtocol.makeSession()
        service = makeService()
    }

    /// `invalidateAndCancel()`, not `finishTasksAndInvalidate()`, and before `reset()`:
    /// `StubURLProtocol`'s state is `static`, so a request still in flight when a test
    /// ends writes into the *next* test's fixture. That only happens after a
    /// `waitForExpectations` timeout, which is exactly when a second, misattributed
    /// failure is least welcome. Cancelling first means nothing can still be writing
    /// when the shared state is cleared.
    override func tearDown() {
        session?.invalidateAndCancel()
        session = nil
        service = nil
        StubURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeService(config: RelevaConfig = RelevaConfig()) -> NetworkService {
        return NetworkService(realm: "us", accessToken: "test-token", config: config, session: session)
    }

    private func jsonBody(of request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody, "request had no body")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func json(_ string: String) throws -> Data {
        return try XCTUnwrap(string.data(using: .utf8))
    }

    // MARK: - Request shape

    func testPushRequestPostsToPushEndpointWithHeadersAndPayload() throws {
        let body = try json(#"{"recommenders":[{"token":"t1","name":"n1","response":[]}],"banners":[]}"#)
        StubURLProtocol.stub { _ in .response(statusCode: 200, body: body) }

        let done = expectation(description: "push completes")
        var result: NetworkService.NetworkResult<RelevaResponse>?

        service.sendPushRequest(
            ["page": ["url": "https://example.com/product/1"]],
            context: ["profile": ["id": "user-1"]]
        ) {
            result = $0
            done.fulfill()
        }
        waitForExpectations(timeout: 5)

        let request = try XCTUnwrap(StubURLProtocol.receivedRequests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://us.releva.ai/api/v0/push")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        // Pins the header format; the version digits are SDKVersionChangelogTests' job.
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "RelevaSDK-iOS/\(SDKVersion.current)")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Platform"), "iOS/ios")

        let payload = try jsonBody(of: request)
        let context = try XCTUnwrap(payload["context"] as? [String: Any])
        XCTAssertEqual((context["profile"] as? [String: Any])?["id"] as? String, "user-1")
        XCTAssertEqual((context["page"] as? [String: Any])?["url"] as? String, "https://example.com/product/1")

        let client = try XCTUnwrap((payload["options"] as? [String: Any])?["client"] as? [String: Any])
        XCTAssertEqual(client["vendor"] as? String, "Releva")
        XCTAssertEqual(client["platform"] as? String, "ios")
        XCTAssertEqual(client["version"] as? String, SDKVersion.current)

        switch try XCTUnwrap(result) {
        case .success(let response):
            XCTAssertEqual(response.recommenderCount, 1)
            XCTAssertEqual(response.recommenders.first?.token, "t1")
        case .failure(let error):
            XCTFail("expected success, got \(error)")
        }
    }

    // Overlaps `EndpointOverrideTests.testEndpointOverrideTakesPrecedence`, which pins the same
    // precedence at the `getBaseURL()` seam. Kept here too because the two seams can drift; see
    // `testClearingTheEndpointOverrideSendsTheNextRequestBackToTheRealm` below for the
    // previously-uncovered wire-level case of clearing the override.
    func testRequestsGoToTheEndpointOverrideRatherThanTheCustomEndpoint() throws {
        StubURLProtocol.stub { _ in .response(statusCode: 200, body: Data("{}".utf8)) }

        service = makeService(config: RelevaConfig(customEndpoint: "https://custom.example.com"))
        service.setEndpointOverride("https://override.example.com")

        let done = expectation(description: "token registration completes")
        service.registerPushToken("fcm-token", deviceType: .ios, deviceId: "device-1", profileId: "user-1") { _ in
            done.fulfill()
        }
        waitForExpectations(timeout: 5)

        let request = try XCTUnwrap(StubURLProtocol.receivedRequests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://override.example.com/api/v0/appPush/tokens")
    }

    func testClearingTheEndpointOverrideSendsTheNextRequestBackToTheRealm() throws {
        // `EndpointOverrideTests.testClearEndpointOverride` already pins this at the
        // `getBaseURL()` seam; this pins it at the wire, which is the seam a
        // resolver-level bug wouldn't necessarily show up at.
        StubURLProtocol.stub { _ in .response(statusCode: 200, body: Data("{}".utf8)) }

        service.setEndpointOverride("https://override.example.com")
        service.setEndpointOverride(nil)

        let done = expectation(description: "token registration completes")
        service.registerPushToken("fcm-token", deviceType: .ios, deviceId: "device-1", profileId: "user-1") { _ in
            done.fulfill()
        }
        waitForExpectations(timeout: 5)

        let request = try XCTUnwrap(StubURLProtocol.receivedRequests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://us.releva.ai/api/v0/appPush/tokens")
    }

    func testRegisterPushTokenPostsTheTokenPayload() throws {
        StubURLProtocol.stub { _ in .response(statusCode: 200, body: Data("{}".utf8)) }

        let done = expectation(description: "token registration completes")
        var result: NetworkService.NetworkResult<Bool>?

        service.registerPushToken("fcm-token", deviceType: .ios, deviceId: "device-1", profileId: nil) {
            result = $0
            done.fulfill()
        }
        waitForExpectations(timeout: 5)

        let request = try XCTUnwrap(StubURLProtocol.receivedRequests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://us.releva.ai/api/v0/appPush/tokens")
        XCTAssertEqual(request.httpMethod, "POST")

        let payload = try jsonBody(of: request)
        XCTAssertEqual(payload["pushToken"] as? String, "fcm-token")
        XCTAssertEqual(payload["deviceType"] as? String, "ios")
        XCTAssertEqual(payload["deviceId"] as? String, "device-1")
        XCTAssertNil(payload["profileId"], "a nil profileId must be omitted, not sent as null")

        switch try XCTUnwrap(result) {
        case .success(let ok):
            XCTAssertTrue(ok)
        case .failure(let error):
            XCTFail("expected success, got \(error)")
        }
    }

    func testInboxUnreadCountPercentEncodesUserIdAndReadsCount() throws {
        let body = try json(#"{"count":7}"#)
        StubURLProtocol.stub { _ in .response(statusCode: 200, body: body) }

        let done = expectation(description: "unread count completes")
        var result: NetworkService.NetworkResult<Int>?

        service.fetchInboxUnreadCount(userId: "user one") {
            result = $0
            done.fulfill()
        }
        waitForExpectations(timeout: 5)

        let request = try XCTUnwrap(StubURLProtocol.receivedRequests.first)
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://us.releva.ai/api/v0/inbox/unread-count?userId=user%20one"
        )
        XCTAssertEqual(request.httpMethod, "GET")

        switch try XCTUnwrap(result) {
        case .success(let count):
            XCTAssertEqual(count, 7)
        case .failure(let error):
            XCTFail("expected success, got \(error)")
        }
    }

    func testEngagementEventsFireDeduplicatedGetCallbacks() throws {
        StubURLProtocol.stub { _ in .response(statusCode: 200, body: Data()) }

        let events = [
            EngagementEvent(type: .clicked, callbackUrl: "https://example.com/cb/1", notificationId: "n1"),
            EngagementEvent(type: .opened, callbackUrl: "https://example.com/cb/1", notificationId: "n2"),
            EngagementEvent(type: .delivered, callbackUrl: "https://example.com/cb/2", notificationId: "n3"),
        ]

        let done = expectation(description: "engagement events complete")
        var result: NetworkService.NetworkResult<Bool>?

        service.sendEngagementEvents(events) {
            result = $0
            done.fulfill()
        }
        waitForExpectations(timeout: 5)

        let requests = StubURLProtocol.receivedRequests
        XCTAssertEqual(requests.count, 2, "the two events sharing a callback URL must collapse into one GET")
        XCTAssertEqual(
            Set(requests.compactMap { $0.url?.absoluteString }),
            ["https://example.com/cb/1", "https://example.com/cb/2"]
        )
        XCTAssertEqual(Set(requests.compactMap { $0.httpMethod }), ["GET"])

        switch try XCTUnwrap(result) {
        case .success(let ok):
            XCTAssertTrue(ok)
        case .failure(let error):
            XCTFail("expected success, got \(error)")
        }
    }

    // MARK: - Engagement callback fan-out

    /// One callback failing must neither cancel its siblings nor be reported as success.
    func testEngagementEventsFailWhenOneCallbackHitsATransportError() throws {
        StubURLProtocol.stub { request in
            if request.url?.absoluteString == "https://example.com/cb/2" {
                return .failure(URLError(.notConnectedToInternet))
            }
            return .response(statusCode: 200, body: Data())
        }

        let result = try sendEngagementEvents(callbackUrls: [
            "https://example.com/cb/1",
            "https://example.com/cb/2",
        ])

        XCTAssertEqual(StubURLProtocol.receivedRequests.count, 2, "a failing callback must not stop the others")
        assertBatchFailed(result)
    }

    func testEngagementEventsFailWhenOneCallbackReturnsAnErrorStatus() throws {
        StubURLProtocol.stub { request in
            if request.url?.absoluteString == "https://example.com/cb/2" {
                return .response(statusCode: 500, body: Data())
            }
            return .response(statusCode: 200, body: Data())
        }

        let result = try sendEngagementEvents(callbackUrls: [
            "https://example.com/cb/1",
            "https://example.com/cb/2",
        ])

        XCTAssertEqual(StubURLProtocol.receivedRequests.count, 2)
        assertBatchFailed(result)
    }

    /// The path the `allSucceeded` data race lived on: several `URLSession` completion
    /// handlers, running concurrently on its delegate queue, all recording a failure.
    func testEngagementEventsFailWhenSeveralCallbacksFailAtOnce() throws {
        StubURLProtocol.stub { request in
            switch request.url?.absoluteString ?? "" {
            case "https://example.com/cb/2":
                return .failure(URLError(.timedOut))
            case "https://example.com/cb/3":
                return .response(statusCode: 404, body: Data())
            case "https://example.com/cb/4":
                return .failure(URLError(.cannotConnectToHost))
            default:
                return .response(statusCode: 200, body: Data())
            }
        }

        let result = try sendEngagementEvents(callbackUrls: [
            "https://example.com/cb/1",
            "https://example.com/cb/2",
            "https://example.com/cb/3",
            "https://example.com/cb/4",
        ])

        XCTAssertEqual(StubURLProtocol.receivedRequests.count, 4)
        assertBatchFailed(result)
    }

    func testEngagementEventsSkipAnUnparseableCallbackUrl() throws {
        XCTAssertNil(URL(string: Self.unparseableCallbackUrl), "the fixture must be one URL(string:) rejects")
        StubURLProtocol.stub { _ in .response(statusCode: 200, body: Data()) }

        let result = try sendEngagementEvents(callbackUrls: [
            Self.unparseableCallbackUrl,
            "https://example.com/cb/1",
        ])

        XCTAssertEqual(
            StubURLProtocol.receivedRequests.compactMap { $0.url?.absoluteString },
            ["https://example.com/cb/1"],
            "the unparseable URL is skipped, the rest of the batch still fires"
        )
        assertBatchSucceeded(result)
    }

    /// `group.notify` with no `enter()` at all fires immediately, so this pins that the
    /// caller still hears back exactly once (the helper's expectation fails on a second call).
    func testEngagementEventsCompleteOnceWhenEveryCallbackUrlIsUnparseable() throws {
        XCTAssertNil(URL(string: Self.unparseableCallbackUrl), "the fixture must be one URL(string:) rejects")
        StubURLProtocol.stub { _ in .response(statusCode: 200, body: Data()) }

        let result = try sendEngagementEvents(callbackUrls: [Self.unparseableCallbackUrl])

        XCTAssertTrue(StubURLProtocol.receivedRequests.isEmpty, "nothing parseable to fire")
        assertBatchSucceeded(result)
    }

    // MARK: - Engagement callback helpers

    /// A callback URL `URL(string:)` rejects, taking `sendEngagementEvents`' skip path.
    private static let unparseableCallbackUrl = ""

    /// Sends one event per callback URL and returns the single result.
    ///
    /// The expectation allows no over-fulfilment, so a second call to `completion` fails
    /// the test — that is how the "completes exactly once" cases above are asserted.
    private func sendEngagementEvents(
        callbackUrls: [String]
    ) throws -> NetworkService.NetworkResult<Bool> {
        let events = callbackUrls.map { EngagementEvent(type: .clicked, callbackUrl: $0) }

        let done = expectation(description: "engagement events complete")
        var result: NetworkService.NetworkResult<Bool>?

        service.sendEngagementEvents(events) {
            result = $0
            done.fulfill()
        }
        waitForExpectations(timeout: 5)

        return try XCTUnwrap(result)
    }

    /// Asserts the one failure `sendEngagementEvents` reports, message included: every
    /// reason a callback can fail collapses into this single result.
    private func assertBatchFailed(
        _ result: NetworkService.NetworkResult<Bool>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch result {
        case .success:
            XCTFail("expected failure", file: file, line: line)
        case .failure(let error):
            if case .networkError(let message) = error {
                XCTAssertEqual(message, "Failed to send some events", file: file, line: line)
            } else {
                XCTFail("expected .networkError, got \(error)", file: file, line: line)
            }
        }
    }

    private func assertBatchSucceeded(
        _ result: NetworkService.NetworkResult<Bool>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch result {
        case .success(let ok):
            XCTAssertTrue(ok, file: file, line: line)
        case .failure(let error):
            XCTFail("expected success, got \(error)", file: file, line: line)
        }
    }

    // MARK: - Response mapping

    func testUnauthorizedResponseMapsToUnauthorized() throws {
        StubURLProtocol.stub { _ in .response(statusCode: 401, body: Data()) }

        let done = expectation(description: "inbox action completes")
        var result: NetworkService.NetworkResult<Bool>?

        service.inboxTrackAction(messageId: "m1", userId: "user-1") {
            result = $0
            done.fulfill()
        }
        waitForExpectations(timeout: 5)

        switch try XCTUnwrap(result) {
        case .success:
            XCTFail("expected failure")
        case .failure(let error):
            if case .unauthorized = error {} else {
                XCTFail("expected .unauthorized, got \(error)")
            }
        }
    }

    func testUnexpectedStatusCodeMapsToServerErrorCarryingTheBody() throws {
        let body = try json(#"{"error":"no such message"}"#)
        StubURLProtocol.stub { _ in .response(statusCode: 404, body: body) }

        let done = expectation(description: "inbox action completes")
        var result: NetworkService.NetworkResult<Bool>?

        service.inboxTrackAction(messageId: "m1", userId: "user-1") {
            result = $0
            done.fulfill()
        }
        waitForExpectations(timeout: 5)

        switch try XCTUnwrap(result) {
        case .success:
            XCTFail("expected failure")
        case .failure(let error):
            if case .serverError(let code, let message) = error {
                XCTAssertEqual(code, 404)
                XCTAssertEqual(message, #"{"error":"no such message"}"#)
            } else {
                XCTFail("expected .serverError, got \(error)")
            }
        }
    }

    func testTransportFailureMapsToNetworkError() throws {
        StubURLProtocol.stub { _ in .failure(URLError(.notConnectedToInternet)) }

        // inboxTrackAction is the one endpoint with retryAttempts: 0, so this asserts the
        // terminal mapping without waiting out a retry backoff.
        let done = expectation(description: "inbox action completes")
        var result: NetworkService.NetworkResult<Bool>?

        service.inboxTrackAction(messageId: "m1", userId: "user-1") {
            result = $0
            done.fulfill()
        }
        waitForExpectations(timeout: 5)

        XCTAssertEqual(StubURLProtocol.receivedRequests.count, 1, "retryAttempts: 0 must not retry")
        switch try XCTUnwrap(result) {
        case .success:
            XCTFail("expected failure")
        case .failure(let error):
            if case .networkError = error {} else {
                XCTFail("expected .networkError, got \(error)")
            }
        }
    }

    func testUndecodableSuccessBodyMapsToInvalidResponse() throws {
        StubURLProtocol.stub { _ in .response(statusCode: 200, body: Data("not json".utf8)) }

        let done = expectation(description: "push completes")
        var result: NetworkService.NetworkResult<RelevaResponse>?

        service.sendPushRequest([:], context: [:]) {
            result = $0
            done.fulfill()
        }
        waitForExpectations(timeout: 5)

        switch try XCTUnwrap(result) {
        case .success:
            XCTFail("expected failure")
        case .failure(let error):
            if case .invalidResponse = error {} else {
                XCTFail("expected .invalidResponse, got \(error)")
            }
        }
    }

    func testServerErrorIsRetriedAndThenSurfaced() throws {
        StubURLProtocol.stub { _ in .response(statusCode: 500, body: Data("boom".utf8)) }

        // sendNpsSubmission passes retryAttempts: 1, so a 5xx is retried exactly once
        // after a 2 s backoff before the error is surfaced.
        let done = expectation(description: "nps submission completes")
        var result: NetworkService.NetworkResult<Bool>?

        service.sendNpsSubmission(["score": 9], token: "nps-token") {
            result = $0
            done.fulfill()
        }
        waitForExpectations(timeout: 20)

        XCTAssertEqual(StubURLProtocol.receivedRequests.count, 2, "a 5xx must be retried once")
        XCTAssertEqual(
            StubURLProtocol.receivedRequests.first?.url?.absoluteString,
            "https://us.releva.ai/api/v0/nps/nps-token/submissions"
        )
        switch try XCTUnwrap(result) {
        case .success:
            XCTFail("expected failure")
        case .failure(let error):
            if case .serverError(let code, let message) = error {
                XCTAssertEqual(code, 500)
                XCTAssertEqual(message, "boom")
            } else {
                XCTFail("expected .serverError, got \(error)")
            }
        }
    }
}
