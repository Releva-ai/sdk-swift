import UserNotifications
import XCTest
@testable import RelevaSDK

/// `RelevaClient.handleNotificationResponse(_:)` is the SDK's tap entry point for an app that
/// keeps its own `UNUserNotificationCenterDelegate`, or that enables tracking after iOS has
/// already delivered the tap that launched it. It runs the same handling the SDK's own delegate
/// does — and a tap is handled once, however many of those ways in see it.
@MainActor
final class NotificationResponseHandlingTests: XCTestCase {
    /// The forwarding code only passes the centre through to the host, and nothing here reads
    /// it, so an arbitrary object stands in for it (as in `NotificationDelegateForwardingTests`).
    private let center = unsafeBitCast(NSObject(), to: UNUserNotificationCenter.self)
    private var savedShared: RelevaClient?

    override func setUp() {
        super.setUp()
        savedShared = RelevaClient.shared
        RelevaClient.shared = nil
    }

    override func tearDown() {
        clients.forEach { $0.shutdown() }
        clients = []
        RelevaClient.shared = savedShared
        super.tearDown()
    }

    private var clients: [RelevaClient] = []

    /// A client with nothing enabled on it yet and no server behind it. Shut down in `tearDown`
    /// so the engagement service `enablePushEngagementTracking()` starts stops its batch timer.
    private func makeClient() -> RelevaClient {
        let client = RelevaClient(
            realm: "test",
            accessToken: "test-token",
            config: RelevaConfig(enableTracking: false, enablePushNotifications: true, customEndpoint: "http://127.0.0.1:9")
        )
        clients.append(client)
        return client
    }

    /// Runs the real `enablePushEngagementTracking()`. The notification service is installed
    /// first, over a spy centre, because the method builds one only when it has none and the real
    /// one resolves `UNUserNotificationCenter.current()`, which needs a host app this bundle has
    /// none of.
    @discardableResult
    private func enableTracking(on client: RelevaClient) -> NotificationService {
        let service = NotificationService(config: client.config, center: CenterSpy())
        client.notificationService = service
        client.enablePushEngagementTracking()
        return service
    }

    private let screenPush: [AnyHashable: Any] = [
        "target": "screen",
        "navigate_to_screen": "cart",
        "navigate_to_parameters": "{\"productId\": \"42\"}"
    ]

    // MARK: - Tests

    func testATapIsRoutedAndReportedAsReleva() {
        let client = makeClient()
        let service = enableTracking(on: client)
        let recorder = NavigationPostRecorder()
        var taps = 0
        service.onNotificationTapped = { _ in taps += 1 }

        XCTAssertTrue(client.handleNotificationResponse(makeRelevaTap(screenPush)))

        XCTAssertEqual(taps, 1)
        XCTAssertEqual(recorder.names, ["RelevaNavigateToScreen"])
        XCTAssertEqual(recorder.userInfos.first?["screen"] as? String, "cart")
    }

    func testATapOnTheAppsOwnPushIsReportedAsNotReleva() {
        let client = makeClient()
        enableTracking(on: client)
        let tap = makeResponse(makeNotification(userInfo: ["aps": ["alert": "SPARK"], "carId": "42"]))

        XCTAssertFalse(client.handleNotificationResponse(tap), "the app routes its own push itself")
    }

    /// The cold-launch case: the tap is handed over before `enablePushEngagementTracking()` has
    /// built the services that record it, so it waits for them.
    func testATapHandedOverBeforeTrackingIsEnabledIsProcessedOnce() {
        let client = makeClient()
        let recorder = NavigationPostRecorder()
        let tap = makeRelevaTap(screenPush)

        XCTAssertTrue(client.handleNotificationResponse(tap))
        XCTAssertTrue(recorder.names.isEmpty, "nothing is routed while there is nothing to track it with")

        enableTracking(on: client)
        XCTAssertEqual(recorder.names, ["RelevaNavigateToScreen"])

        client.handleNotificationResponse(tap)
        XCTAssertEqual(recorder.names, ["RelevaNavigateToScreen"], "the buffered tap was already handled")
    }

    /// What an app that sets both before enabling tracking relies on: the service the method
    /// builds or reuses is handed them, so a universal link stays in the app and a handler
    /// installed early sees the buffered tap's destination.
    func testHandlersSetBeforeTrackingIsEnabledAreHonoured() {
        let client = makeClient()
        var claimed: [URL] = []
        var received: [RelevaNavigation] = []
        client.urlHandler = { url in
            claimed.append(url)
            return true
        }
        client.onNavigation = { received.append($0) }

        client.handleNotificationResponse(makeRelevaTap(["target": "url", "navigate_to_url": "https://shop.example.com/p/1"]))
        enableTracking(on: client)
        client.handleNotificationResponse(makeRelevaTap(screenPush))

        XCTAssertEqual(claimed.map(\.absoluteString), ["https://shop.example.com/p/1"])
        XCTAssertEqual(received.count, 1, "the claimed URL is not reported; the screen tap is")
    }

    /// An app that never calls `handleNotificationResponse` sees every tap through the SDK's
    /// delegate, including two on one request identifier — as on 5.2.1.
    func testTheDelegateAloneHandlesEveryTap() {
        let client = makeClient()
        let service = enableTracking(on: client)
        var taps = 0
        service.onNotificationTapped = { _ in taps += 1 }
        let tap = makeRelevaTap(screenPush)

        service.userNotificationCenter(center, didReceive: tap) {}
        service.userNotificationCenter(center, didReceive: tap) {}

        XCTAssertEqual(taps, 2)
    }

    /// The SDK forwards a Releva tap to the host's delegate, and a host that routes every tap
    /// through `handleNotificationResponse` then hands the same tap back.
    func testTheSdkDelegateAndTheAppHandleOneTapOnce() {
        let client = makeClient()
        let service = enableTracking(on: client)
        let recorder = NavigationPostRecorder()
        var taps = 0
        service.onNotificationTapped = { _ in taps += 1 }
        let tap = makeRelevaTap(screenPush)

        service.userNotificationCenter(center, didReceive: tap) {}
        client.handleNotificationResponse(tap)

        XCTAssertEqual(taps, 1)
        XCTAssertEqual(recorder.names, ["RelevaNavigateToScreen"])
    }

    /// The deliveries of a *repeating* local notification share one request identifier, so the
    /// window that keeps one tap from being handled twice is not forever.
    func testALaterTapOnTheSameNotificationIsHandledAgain() {
        let client = makeClient()
        let service = enableTracking(on: client)
        var taps = 0
        service.onNotificationTapped = { _ in taps += 1 }
        let tap = makeRelevaTap(screenPush)

        client.handleNotificationResponse(tap)
        service.handledTapWindow = 0
        client.handleNotificationResponse(tap)

        XCTAssertEqual(taps, 2)
    }

    func testTheSameTapHandedOverTwiceIsHandledOnce() {
        let client = makeClient()
        let service = enableTracking(on: client)
        let recorder = NavigationPostRecorder()
        var taps = 0
        service.onNotificationTapped = { _ in taps += 1 }
        let tap = makeRelevaTap(screenPush)

        client.handleNotificationResponse(tap)
        client.handleNotificationResponse(tap)

        XCTAssertEqual(taps, 1)
        XCTAssertEqual(recorder.names, ["RelevaNavigateToScreen"])
    }
}
