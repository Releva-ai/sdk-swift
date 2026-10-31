import UserNotifications
import XCTest

/// The navigations the SDK posts through `NotificationCenter`, in the order they were posted.
///
/// Not main-actor isolated and not an inline closure over the test's own state: an observer block
/// is `@Sendable`, so what it appends to cannot be either.
final class NavigationPostRecorder {
    private(set) var names: [String] = []
    private(set) var userInfos: [[AnyHashable: Any]] = []
    private var observers: [NSObjectProtocol] = []

    private static let navigationNames = ["RelevaNavigateToScreen", "RelevaNavigateToURL", "RelevaNavigateToInbox"]

    init() {
        observers = Self.navigationNames.map { name in
            NotificationCenter.default.addObserver(
                forName: Notification.Name(name),
                object: nil,
                queue: nil
            ) { [weak self] notification in
                self?.names.append(name)
                self?.userInfos.append(notification.userInfo ?? [:])
            }
        }
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}

/// Taps, built the only way they can be: `UNNotification` and `UNNotificationResponse` have no
/// public initializers, so the two keys the framework's own decoder sets are set by hand.
///
/// Shared by `NotificationDelegateForwardingTests` and `NotificationResponseHandlingTests` —
/// the two entry points the SDK has for a tap — and by `PushNavigationCallbackTests`.
extension XCTestCase {
    func makeNotification(userInfo: [AnyHashable: Any], category: String = "") -> UNNotification {
        let content = UNMutableNotificationContent()
        content.userInfo = userInfo
        content.categoryIdentifier = category
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        let type: NSObject.Type = UNNotification.self
        guard let notification = type.init() as? UNNotification else { fatalError("UNNotification fixture") }
        notification.setValue(request, forKey: "request")
        notification.setValue(Date(), forKey: "date")
        return notification
    }

    func makeResponse(_ notification: UNNotification) -> UNNotificationResponse {
        let type: NSObject.Type = UNNotificationResponse.self
        guard let response = type.init() as? UNNotificationResponse else { fatalError("UNNotificationResponse fixture") }
        response.setValue(notification, forKey: "notification")
        response.setValue(UNNotificationDefaultActionIdentifier, forKey: "actionIdentifier")
        return response
    }

    /// A tap on a Releva push, with whatever `data` the push carried at the root level, which is
    /// where Firebase puts it on iOS.
    func makeRelevaTap(_ data: [AnyHashable: Any]) -> UNNotificationResponse {
        var userInfo: [AnyHashable: Any] = ["aps": ["alert": "Hi"], "click_action": "RELEVA_OPEN_SCREEN"]
        for (key, value) in data {
            userInfo[key] = value
        }
        return makeResponse(makeNotification(userInfo: userInfo))
    }
}
