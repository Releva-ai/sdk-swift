import XCTest
@testable import RelevaSDK

/// End-to-end tests for `NetworkService` against a stubbed `URLProtocol`:
/// what goes on the wire (URL, method, headers, body) and how every response
/// class comes back out (success decode, 401, non-2xx, transport failure, retry).
final class NetworkServiceTests: XCTestCase {
    private var session: URLSession!
    private var service: NetworkService!

    override func setUp() {
        super.setUp()
        session = StubURLProtocol.makeSession()
        service = makeService()
    }

    /// `invalidateAndCancel()`, not `finishTasksAndInvalidate()`, and before `reset()`:
    /// `StubURLProtocol`'s state is `static`, so a request still in flight when a test
    /// ends writes into the *next* test's fixture. Awaiting every call makes that far
    /// less likely than it was under completion handlers, but a cancelled `Task.sleep`
    /// in `executeRequest` can still leave the loop unwinding, so cancelling first is
    /// what makes it impossible rather than merely unlikely.
    override func tearDown() {
        session?.invalidateAndCancel()
        session = nil
        service = nil
        StubURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeService(config: RelevaConfig = RelevaConfig()) -> NetworkService {
        NetworkService(realm: "us", accessToken: "test-token", config: config, session: session)
    }

    private func jsonBody(of request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody, "request had no body")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func json(_ string: String) throws -> Data {
        try XCTUnwrap(string.data(using: .utf8))
    }

    /// The error `work` threw, or `nil` if it returned. Replaces the `NetworkResult`
    /// switches: `XCTAssertThrowsError` has no `async` overload, so every failure-path
    /// test would otherwise repeat the same `do`/`catch`.
    private func captureError(_ work: () async throws -> Void) async -> Error? {
        do {
            try await work()
            return nil
        } catch {
            return error
        }
    }

    // MARK: - Request shape

    func testPushRequestPostsToPushEndpointWithHeadersAndPayload() async throws {
        let body = try json(#"{"recommenders":[{"token":"t1","name":"n1","response":[]}],"banners":[]}"#)
        StubURLProtocol.stub { _ in .response(statusCode: 200, body: body) }

        let response = try await service.sendPushRequest(
            ["page": ["url": "https://example.com/product/1"]],
            context: ["profile": ["id": "user-1"]]
        )

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

        XCTAssertEqual(response.recommenderCount, 1)
        XCTAssertEqual(response.recommenders.first?.token, "t1")
    }

    // Overlaps `EndpointOverrideTests.testEndpointOverrideTakesPrecedence`, which pins the same
    // precedence at the `getBaseURL()` seam. Kept here too because the two seams can drift; see
    // `testClearingTheEndpointOverrideSendsTheNextRequestBackToTheRealm` below for the
    // previously-uncovered wire-level case of clearing the override.
    func testRequestsGoToTheEndpointOverrideRatherThanTheCustomEndpoint() async throws {
        StubURLProtocol.stub { _ in .response(statusCode: 200, body: Data("{}".utf8)) }

        service = makeService(config: RelevaConfig(customEndpoint: "https://custom.example.com"))
        service.setEndpointOverride("https://override.example.com")

        try await service.registerPushToken("fcm-token", deviceType: .ios, deviceId: "device-1", profileId: "user-1")

        let request = try XCTUnwrap(StubURLProtocol.receivedRequests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://override.example.com/api/v0/appPush/tokens")
    }

    func testClearingTheEndpointOverrideSendsTheNextRequestBackToTheRealm() async throws {
        // `EndpointOverrideTests.testClearEndpointOverride` already pins this at the
        // `getBaseURL()` seam; this pins it at the wire, which is the seam a
        // resolver-level bug wouldn't necessarily show up at.
        StubURLProtocol.stub { _ in .response(statusCode: 200, body: Data("{}".utf8)) }

        service.setEndpointOverride("https://override.example.com")
        service.setEndpointOverride(nil)

        try await service.registerPushToken("fcm-token", deviceType: .ios, deviceId: "device-1", profileId: "user-1")

        let request = try XCTUnwrap(StubURLProtocol.receivedRequests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://us.releva.ai/api/v0/appPush/tokens")
    }

    func testRegisterPushTokenPostsTheTokenPayload() async throws {
        StubURLProtocol.stub { _ in .response(statusCode: 200, body: Data("{}".utf8)) }

        // Returning normally is the success signal now that the `Bool` is gone; it was
        // `true` on every path that reached the old completion handler.
        try await service.registerPushToken("fcm-token", deviceType: .ios, deviceId: "device-1", profileId: nil)

        let request = try XCTUnwrap(StubURLProtocol.receivedRequests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://us.releva.ai/api/v0/appPush/tokens")
        XCTAssertEqual(request.httpMethod, "POST")

        let payload = try jsonBody(of: request)
        XCTAssertEqual(payload["pushToken"] as? String, "fcm-token")
        XCTAssertEqual(payload["deviceType"] as? String, "ios")
        XCTAssertEqual(payload["deviceId"] as? String, "device-1")
        XCTAssertNil(payload["profileId"], "a nil profileId must be omitted, not sent as null")
    }

    func testInboxUnreadCountPercentEncodesUserIdAndReadsCount() async throws {
        let body = try json(#"{"count":7}"#)
        StubURLProtocol.stub { _ in .response(statusCode: 200, body: body) }

        let count = try await service.fetchInboxUnreadCount(userId: "user one")

        let request = try XCTUnwrap(StubURLProtocol.receivedRequests.first)
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://us.releva.ai/api/v0/inbox/unread-count?userId=user%20one"
        )
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(count, 7)
    }

    func testEngagementEventsFireDeduplicatedGetCallbacks() async throws {
        StubURLProtocol.stub { _ in .response(statusCode: 200, body: Data()) }

        let events = [
            EngagementEvent(type: .clicked, callbackUrl: "https://example.com/cb/1", notificationId: "n1"),
            EngagementEvent(type: .opened, callbackUrl: "https://example.com/cb/1", notificationId: "n2"),
            EngagementEvent(type: .delivered, callbackUrl: "https://example.com/cb/2", notificationId: "n3")
        ]

        try await service.sendEngagementEvents(events)

        let requests = StubURLProtocol.receivedRequests
        XCTAssertEqual(requests.count, 2, "the two events sharing a callback URL must collapse into one GET")
        XCTAssertEqual(
            Set(requests.compactMap { $0.url?.absoluteString }),
            ["https://example.com/cb/1", "https://example.com/cb/2"]
        )
        XCTAssertEqual(Set(requests.compactMap { $0.httpMethod }), ["GET"])
    }

    // MARK: - Engagement callback fan-out

    /// One callback failing must neither cancel its siblings nor be reported as success.
    func testEngagementEventsFailWhenOneCallbackHitsATransportError() async {
        StubURLProtocol.stub { request in
            if request.url?.absoluteString == "https://example.com/cb/2" {
                return .failure(URLError(.notConnectedToInternet))
            }
            return .response(statusCode: 200, body: Data())
        }

        let thrown = await sendEngagementEvents(callbackUrls: [
            "https://example.com/cb/1",
            "https://example.com/cb/2"
        ])

        XCTAssertEqual(StubURLProtocol.receivedRequests.count, 2, "a failing callback must not stop the others")
        assertBatchFailed(thrown)
    }

    func testEngagementEventsFailWhenOneCallbackReturnsAnErrorStatus() async {
        StubURLProtocol.stub { request in
            if request.url?.absoluteString == "https://example.com/cb/2" {
                return .response(statusCode: 500, body: Data())
            }
            return .response(statusCode: 200, body: Data())
        }

        let thrown = await sendEngagementEvents(callbackUrls: [
            "https://example.com/cb/1",
            "https://example.com/cb/2"
        ])

        XCTAssertEqual(StubURLProtocol.receivedRequests.count, 2)
        assertBatchFailed(thrown)
    }

    /// The path the `allSucceeded` data race lived on before 3.1.1's lock, and before this
    /// release replaced the lock with a `TaskGroup`: several callbacks failing at once.
    /// The verdicts are now per-child return values folded by `for await`, so there is no
    /// shared flag left to race on — but the case is still the one a regression would
    /// break first, so it stays covered.
    func testEngagementEventsFailWhenSeveralCallbacksFailAtOnce() async {
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

        let thrown = await sendEngagementEvents(callbackUrls: [
            "https://example.com/cb/1",
            "https://example.com/cb/2",
            "https://example.com/cb/3",
            "https://example.com/cb/4"
        ])

        XCTAssertEqual(StubURLProtocol.receivedRequests.count, 4)
        assertBatchFailed(thrown)
    }

    /// `URL(string:)` failing takes `continue` before `group.addTask`, so no child task is
    /// ever created for it and nothing contributes a `false` verdict. That makes a malformed
    /// URL indistinguishable from a fully-delivered one to the caller — both return without
    /// throwing, with only an `enableDebugLogging` `print` behind the loss. This test pins
    /// that as the *current* behaviour, not the desired contract; making it count as a
    /// failure would be a real behaviour change and is out of scope for the async migration.
    func testEngagementEventsSkipAnUnparseableCallbackUrl() async {
        XCTAssertNil(URL(string: Self.unparseableCallbackUrl), "the fixture must be one URL(string:) rejects")
        StubURLProtocol.stub { _ in .response(statusCode: 200, body: Data()) }

        let thrown = await sendEngagementEvents(callbackUrls: [
            Self.unparseableCallbackUrl,
            "https://example.com/cb/1"
        ])

        XCTAssertEqual(
            StubURLProtocol.receivedRequests.compactMap { $0.url?.absoluteString },
            ["https://example.com/cb/1"],
            "the unparseable URL is skipped, the rest of the batch still fires"
        )
        assertBatchSucceeded(thrown)
    }

    /// An empty `TaskGroup`'s `for await` finishes immediately, so this pins that the caller
    /// still gets an answer rather than hanging. Same caveat as the test above: a batch that
    /// delivered *nothing* still returns without throwing, pinned as current behaviour rather
    /// than endorsed as desired.
    ///
    /// Under completion handlers this also carried the "called back exactly once" assertion,
    /// which `await` now guarantees structurally — a single resumption of a single call — so
    /// that half of the test is gone rather than restated.
    func testEngagementEventsCompleteOnceWhenEveryCallbackUrlIsUnparseable() async {
        XCTAssertNil(URL(string: Self.unparseableCallbackUrl), "the fixture must be one URL(string:) rejects")
        StubURLProtocol.stub { _ in .response(statusCode: 200, body: Data()) }

        let thrown = await sendEngagementEvents(callbackUrls: [Self.unparseableCallbackUrl])

        XCTAssertTrue(StubURLProtocol.receivedRequests.isEmpty, "nothing parseable to fire")
        assertBatchSucceeded(thrown)
    }

    // MARK: - Engagement callback helpers

    /// A callback URL `URL(string:)` rejects, taking `sendEngagementEvents`' skip path.
    private static let unparseableCallbackUrl = ""

    /// Sends one event per callback URL and returns the error it threw, or `nil`.
    private func sendEngagementEvents(callbackUrls: [String]) async -> Error? {
        let events = callbackUrls.map { EngagementEvent(type: .clicked, callbackUrl: $0) }
        return await captureError { try await service.sendEngagementEvents(events) }
    }

    /// Asserts the one failure `sendEngagementEvents` reports, message included: every
    /// reason a callback can fail collapses into this single error.
    private func assertBatchFailed(
        _ thrown: Error?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let thrown = thrown else {
            XCTFail("expected failure", file: file, line: line)
            return
        }

        guard let relevaError = thrown as? RelevaError,
              case .networkError(let message) = relevaError else {
            XCTFail("expected .networkError, got \(thrown)", file: file, line: line)
            return
        }

        XCTAssertEqual(message, "Failed to send some events", file: file, line: line)
    }

    private func assertBatchSucceeded(
        _ thrown: Error?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if let thrown = thrown {
            XCTFail("expected success, got \(thrown)", file: file, line: line)
        }
    }

    // MARK: - Response mapping

    func testUnauthorizedResponseMapsToUnauthorized() async throws {
        StubURLProtocol.stub { _ in .response(statusCode: 401, body: Data()) }

        let thrown = await captureError { try await service.inboxTrackAction(messageId: "m1", userId: "user-1") }

        XCTAssertEqual(RelevaErrorKind(try XCTUnwrap(thrown)), .unauthorized)
    }

    func testUnexpectedStatusCodeMapsToServerErrorCarryingTheBody() async throws {
        let body = try json(#"{"error":"no such message"}"#)
        StubURLProtocol.stub { _ in .response(statusCode: 404, body: body) }

        let thrown = await captureError { try await service.inboxTrackAction(messageId: "m1", userId: "user-1") }

        let relevaError = try XCTUnwrap(thrown as? RelevaError)
        guard case .serverError(let code, let message) = relevaError else {
            XCTFail("expected .serverError, got \(relevaError)")
            return
        }
        XCTAssertEqual(code, 404)
        XCTAssertEqual(message, #"{"error":"no such message"}"#)
    }

    func testTransportFailureMapsToNetworkError() async throws {
        StubURLProtocol.stub { _ in .failure(URLError(.notConnectedToInternet)) }

        // inboxTrackAction is the one endpoint with retryAttempts: 0, so this asserts the
        // terminal mapping without waiting out a retry backoff.
        let thrown = await captureError { try await service.inboxTrackAction(messageId: "m1", userId: "user-1") }

        XCTAssertEqual(StubURLProtocol.receivedRequests.count, 1, "retryAttempts: 0 must not retry")
        XCTAssertEqual(RelevaErrorKind(try XCTUnwrap(thrown)), .networkError)
    }

    func testUndecodableSuccessBodyMapsToInvalidResponse() async throws {
        StubURLProtocol.stub { _ in .response(statusCode: 200, body: Data("not json".utf8)) }

        let thrown = await captureError { _ = try await service.sendPushRequest([:], context: [:]) }

        XCTAssertEqual(RelevaErrorKind(try XCTUnwrap(thrown)), .invalidResponse)
    }

    func testServerErrorIsRetriedAndThenSurfaced() async throws {
        StubURLProtocol.stub { _ in .response(statusCode: 500, body: Data("boom".utf8)) }

        // sendNpsSubmission passes retryAttempts: 1, so a 5xx is retried exactly once
        // after a 2 s backoff before the error is surfaced.
        let thrown = await captureError {
            try await service.sendNpsSubmission(["score": 9], token: "nps-token")
        }

        XCTAssertEqual(StubURLProtocol.receivedRequests.count, 2, "a 5xx must be retried once")
        XCTAssertEqual(
            StubURLProtocol.receivedRequests.first?.url?.absoluteString,
            "https://us.releva.ai/api/v0/nps/nps-token/submissions"
        )
        let relevaError = try XCTUnwrap(thrown as? RelevaError)
        guard case .serverError(let code, let message) = relevaError else {
            XCTFail("expected .serverError, got \(relevaError)")
            return
        }
        XCTAssertEqual(code, 500)
        XCTAssertEqual(message, "boom")
    }
}
