import UserNotifications
import XCTest
@testable import RelevaSDK

/// `enablePushEngagementTracking()` installs the SDK as the notification-centre delegate. The
/// host app's own delegate must keep receiving the callbacks the SDK does not own: taps, the
/// presentation of its own notifications, and the Settings deep link.
@MainActor
final class NotificationDelegateForwardingTests: XCTestCase {
    /// The test bundle has no host app, so `UNUserNotificationCenter.current()` cannot exist
    /// here. The forwarding code only passes the centre through to the host, and the hosts below
    /// never read it, so an arbitrary object stands in for it.
    private let center = unsafeBitCast(NSObject(), to: UNUserNotificationCenter.self)
    private var service: NotificationService!

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    /// Builds the service in the state `enablePushEngagementTracking()` leaves it: the SDK holds
    /// the delegate slot and remembers `host` as whatever was there before.
    private func install(host: UNUserNotificationCenterDelegate?) {
        service = NotificationService(config: RelevaConfig(enableTracking: false, enablePushNotifications: true))
        service.previousDelegate = host
    }

    // MARK: - Fixtures

    private final class HostDelegate: NSObject, UNUserNotificationCenterDelegate {
        var presented: [UNNotification] = []
        var received: [UNNotificationResponse] = []
        var settingsOpened = 0

        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            willPresent notification: UNNotification,
            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
        ) {
            presented.append(notification)
            completionHandler([.list])
        }

        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            didReceive response: UNNotificationResponse,
            withCompletionHandler completionHandler: @escaping () -> Void
        ) {
            received.append(response)
            completionHandler()
        }

        func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {
            settingsOpened += 1
        }
    }

    /// A host that only handles taps, so the optional methods it lacks must not be forwarded.
    private final class TapOnlyHost: NSObject, UNUserNotificationCenterDelegate {
        var received: [UNNotificationResponse] = []

        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            didReceive response: UNNotificationResponse,
            withCompletionHandler completionHandler: @escaping () -> Void
        ) {
            received.append(response)
            completionHandler()
        }
    }

    private func makeNotification(userInfo: [AnyHashable: Any], category: String = "") -> UNNotification {
        let content = UNMutableNotificationContent()
        content.userInfo = userInfo
        content.categoryIdentifier = category
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        let type: NSObject.Type = UNNotification.self
        // No public initializer; the framework's own decoder path sets these two keys.
        guard let notification = type.init() as? UNNotification else { fatalError("UNNotification fixture") }
        notification.setValue(request, forKey: "request")
        notification.setValue(Date(), forKey: "date")
        return notification
    }

    private func makeResponse(_ notification: UNNotification) -> UNNotificationResponse {
        let type: NSObject.Type = UNNotificationResponse.self
        guard let response = type.init() as? UNNotificationResponse else { fatalError("UNNotificationResponse fixture") }
        response.setValue(notification, forKey: "notification")
        response.setValue(UNNotificationDefaultActionIdentifier, forKey: "actionIdentifier")
        return response
    }

    private let hostPayload: [AnyHashable: Any] = ["aps": ["alert": "SPARK"], "carId": "42"]
    private let relevaPayload: [AnyHashable: Any] = ["aps": ["alert": "Hi"], "click_action": "RELEVA_OPEN_SCREEN"]

    // MARK: - Settings deep link

    func testOpenSettingsIsForwardedToTheHost() {
        let host = HostDelegate()
        install(host: host)

        service.userNotificationCenter(center, openSettingsFor: nil)

        XCTAssertEqual(host.settingsOpened, 1)
    }

    func testOpenSettingsWithNoHostDoesNothing() {
        install(host: nil)
        service.userNotificationCenter(center, openSettingsFor: nil) // must not crash
    }

    // MARK: - Foreground presentation

    func testHostNotificationPresentationIsDecidedByTheHost() {
        let host = HostDelegate()
        install(host: host)
        let notification = makeNotification(userInfo: hostPayload)

        let done = expectation(description: "completion")
        var options: UNNotificationPresentationOptions?
        service.userNotificationCenter(center, willPresent: notification) { options = $0; done.fulfill() }
        wait(for: [done], timeout: 2)

        XCTAssertEqual(host.presented.count, 1)
        XCTAssertTrue(host.presented.first === notification)
        XCTAssertEqual(options, [.list], "the host's own answer reaches the system")
    }

    func testRelevaNotificationPresentationIsNotForwarded() {
        let host = HostDelegate()
        install(host: host)
        let notification = makeNotification(userInfo: relevaPayload, category: "RELEVA_DEFAULT")

        let done = expectation(description: "completion")
        var options: UNNotificationPresentationOptions?
        service.userNotificationCenter(center, willPresent: notification) { options = $0; done.fulfill() }
        wait(for: [done], timeout: 2)

        XCTAssertTrue(host.presented.isEmpty)
        XCTAssertEqual(options, [.banner, .list, .sound, .badge])
    }

    func testHostNotificationWithNoForwardTargetIsSuppressedAsBefore() {
        install(host: TapOnlyHost())
        let notification = makeNotification(userInfo: hostPayload)

        let done = expectation(description: "completion")
        var options: UNNotificationPresentationOptions?
        service.userNotificationCenter(center, willPresent: notification) { options = $0; done.fulfill() }
        wait(for: [done], timeout: 2)

        XCTAssertEqual(options, [])
    }

    // MARK: - Taps

    func testEveryTapIsForwardedToTheHost() {
        let host = HostDelegate()
        install(host: host)
        let hostTap = makeResponse(makeNotification(userInfo: hostPayload))
        let relevaTap = makeResponse(makeNotification(userInfo: relevaPayload, category: "RELEVA_DEFAULT"))

        var completions = 0
        service.userNotificationCenter(center, didReceive: hostTap) { completions += 1 }
        service.userNotificationCenter(center, didReceive: relevaTap) { completions += 1 }

        XCTAssertEqual(host.received.count, 2)
        XCTAssertTrue(host.received[0] === hostTap)
        XCTAssertTrue(host.received[1] === relevaTap, "Releva taps reach the host too, after tracking")
        XCTAssertEqual(completions, 2, "the host's completion call is the system's")
    }

    func testTapWithNoHostStillCompletes() {
        install(host: nil)
        let tap = makeResponse(makeNotification(userInfo: hostPayload))

        var completions = 0
        service.userNotificationCenter(center, didReceive: tap) { completions += 1 }

        XCTAssertEqual(completions, 1)
    }

    func testTheSdkNeverForwardsToItself() {
        install(host: nil)
        service.previousDelegate = service // what a second `initialize()` would otherwise capture

        XCTAssertNil(service.hostDelegate(
            responding: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:))
        ))
    }
}
