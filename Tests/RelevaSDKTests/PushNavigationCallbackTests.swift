import UserNotifications
import XCTest
@testable import RelevaSDK

/// The two ways an app can take a push navigation other than by observing `NotificationCenter`:
/// `urlHandler`, which gets first refusal on every link, and `onNavigation`, which reports every
/// destination in typed form. Both are driven here through `handleNotificationResponse(_:)`,
/// which runs the same routing a tap on the SDK's own delegate does.
@MainActor
final class PushNavigationCallbackTests: XCTestCase {
    private var savedShared: RelevaClient?

    override func setUp() {
        super.setUp()
        savedShared = RelevaClient.shared
        RelevaClient.shared = nil
    }

    override func tearDown() {
        RelevaClient.shared = savedShared
        super.tearDown()
    }

    /// A client with the notification service `enablePushEngagementTracking()` would install —
    /// that method resolves `UNUserNotificationCenter.current()`, which needs a host app this
    /// bundle has none of.
    private func makeClient() -> RelevaClient {
        let client = RelevaClient(
            realm: "test",
            accessToken: "test-token",
            config: RelevaConfig(enableTracking: false, enablePushNotifications: true, customEndpoint: "http://127.0.0.1:9")
        )
        client.notificationService = NotificationService(config: client.config)
        return client
    }

    private func urlPush(_ url: String) -> [AnyHashable: Any] {
        ["target": "url", "navigate_to_url": url]
    }

    // MARK: - urlHandler

    /// The universal-link case. What the SDK does *not* do with a claimed URL — open it
    /// externally — is not observable here (it reaches `UIApplication` by reflection), but it is
    /// downstream of the post this asserts the absence of.
    func testTheHandlerClaimsAnHttpsLink() {
        let client = makeClient()
        let recorder = NavigationPostRecorder()
        var handled: [URL] = []
        client.urlHandler = { url in
            handled.append(url)
            return true
        }

        client.handleNotificationResponse(makeRelevaTap(urlPush("https://shop.example.com/p/42")))

        XCTAssertEqual(handled.map(\.absoluteString), ["https://shop.example.com/p/42"])
        XCTAssertTrue(recorder.names.isEmpty, "a claimed URL is the app's, so the SDK does nothing more with it")
        XCTAssertNil(client.consumePendingNavigation())
    }

    func testADeclinedDeepLinkIsPostedAsBefore() {
        let client = makeClient()
        let recorder = NavigationPostRecorder()
        var asked = 0
        client.urlHandler = { _ in
            asked += 1
            return false
        }

        client.handleNotificationResponse(makeRelevaTap(urlPush("myapp://product/42")))

        XCTAssertEqual(asked, 1)
        XCTAssertEqual(recorder.names, ["RelevaNavigateToURL"])
        XCTAssertEqual(recorder.userInfos.first?["url"] as? URL, URL(string: "myapp://product/42"))
    }

    func testADeepLinkWithNoHandlerIsPostedAsBefore() {
        let client = makeClient()
        let recorder = NavigationPostRecorder()

        client.handleNotificationResponse(makeRelevaTap(urlPush("myapp://product/42")))

        XCTAssertEqual(recorder.names, ["RelevaNavigateToURL"])
    }

    // MARK: - onNavigation

    func testTheCallbackReceivesEveryDestinationAndThePostsStillFire() {
        let client = makeClient()
        let recorder = NavigationPostRecorder()
        var received: [RelevaNavigation] = []
        client.onNavigation = { received.append($0) }

        client.handleNotificationResponse(makeRelevaTap([
            "target": "screen",
            "navigate_to_screen": "cart",
            "navigate_to_parameters": "{\"productId\": \"42\"}"
        ]))
        client.handleNotificationResponse(makeRelevaTap(urlPush("myapp://product/42")))
        client.handleNotificationResponse(makeRelevaTap([
            "target": "inbox",
            "navigate_to_parameters": "{\"inboxMessageId\": 456}"
        ]))

        XCTAssertEqual(
            recorder.names,
            ["RelevaNavigateToScreen", "RelevaNavigateToURL", "RelevaNavigateToInbox"],
            "the posts are unchanged; the callback is in addition to them"
        )
        XCTAssertEqual(received.count, 3)

        guard case .screen(let name, let parameters) = received[0] else {
            return XCTFail("expected a screen, got \(received[0])")
        }
        XCTAssertEqual(name, "cart")
        XCTAssertEqual(parameters["productId"] as? String, "42")

        guard case .url(let url) = received[1] else {
            return XCTFail("expected a URL, got \(received[1])")
        }
        XCTAssertEqual(url, URL(string: "myapp://product/42"))

        guard case .inbox(let messageId) = received[2] else {
            return XCTFail("expected the inbox, got \(received[2])")
        }
        XCTAssertEqual(messageId, 456)
    }

    /// The cold-launch case: the tap is routed before the app has a handler for it.
    func testAssigningTheCallbackReplaysThePendingNavigationOnce() {
        let client = makeClient()
        client.handleNotificationResponse(makeRelevaTap([
            "target": "screen",
            "navigate_to_screen": "cart"
        ]))

        var received: [RelevaNavigation] = []
        client.onNavigation = { received.append($0) }
        XCTAssertEqual(received.count, 1, "the navigation the app missed is replayed")
        XCTAssertNil(client.consumePendingNavigation(), "and consumed by the replay")

        client.onNavigation = { received.append($0) }
        XCTAssertEqual(received.count, 1, "replayed once")
    }
}
