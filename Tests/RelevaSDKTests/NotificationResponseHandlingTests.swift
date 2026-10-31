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
        RelevaClient.shared = savedShared
        super.tearDown()
    }

    /// A client with nothing enabled on it yet and no server behind it.
    private func makeClient() -> RelevaClient {
        RelevaClient(
            realm: "test",
            accessToken: "test-token",
            config: RelevaConfig(enableTracking: false, enablePushNotifications: true, customEndpoint: "http://127.0.0.1:9")
        )
    }

    /// Installs the notification service `enablePushEngagementTracking()` would. That method
    /// itself cannot run here: it resolves `UNUserNotificationCenter.current()`, which needs a
    /// host app this bundle has none of.
    @discardableResult
    private func enableTracking(on client: RelevaClient) -> NotificationService {
        let service = NotificationService(config: client.config)
        client.notificationService = service
        return service
    }

    private let screenPush: [AnyHashable: Any] = [
        "target": "screen",
        "navigate_to_screen": "cart",
        "navigate_to_parameters": "{\"productId\": \"42\"}"
    ]

    // MARK: - Tests

    func testATapIsTrackedAndRoutedAndReportedAsReleva() {
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
        client.processBufferedNotificationResponses()
        XCTAssertEqual(recorder.names, ["RelevaNavigateToScreen"])

        client.handleNotificationResponse(tap)
        XCTAssertEqual(recorder.names, ["RelevaNavigateToScreen"], "the buffered tap was already handled")
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
