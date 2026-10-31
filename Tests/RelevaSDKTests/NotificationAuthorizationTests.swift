import UserNotifications
import XCTest
@testable import RelevaSDK

/// Who asks for notification permission. By default the SDK still asks on
/// `enablePushEngagementTracking()`, as it always has; with
/// `RelevaConfig.requestsNotificationAuthorization` off it never does, and the app asks through
/// `RelevaClient.requestPushAuthorization(options:)` instead.
@MainActor
final class NotificationAuthorizationTests: XCTestCase {
    /// Stands in for `UNUserNotificationCenter.current()`, which needs a host app this bundle has
    /// none of.
    private final class CenterSpy: UserNotificationCentering {
        weak var delegate: UNUserNotificationCenterDelegate?
        var granted = false
        var settingsRequests = 0
        var authorizationRequests: [UNAuthorizationOptions] = []
        private(set) var categories: Set<UNNotificationCategory> = []

        /// Never answered: `UNNotificationSettings` has no initializer a test can reach. What the
        /// service does with the answer is the authorization request recorded below, so the count
        /// is what says whether the SDK went looking for permission at all.
        func getNotificationSettings(completionHandler: @escaping (UNNotificationSettings) -> Void) {
            settingsRequests += 1
        }

        func getNotificationCategories(completionHandler: @escaping (Set<UNNotificationCategory>) -> Void) {
            completionHandler(categories)
        }

        func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
            self.categories = categories
        }

        func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: ((Error?) -> Void)?) {
            completionHandler?(nil)
        }

        func requestAuthorization(options: UNAuthorizationOptions, completionHandler: @escaping (Bool, Error?) -> Void) {
            authorizationRequests.append(options)
            completionHandler(granted, nil)
        }
    }

    func testInitializeGoesLookingForPermissionByDefault() {
        let center = CenterSpy()
        let service = NotificationService(config: RelevaConfig(), center: center)

        service.initialize()

        XCTAssertEqual(center.settingsRequests, 1, "unchanged: the SDK asks when the status is still undetermined")
        XCTAssertTrue(center.delegate === service)
    }

    func testInitializeAsksForNothingWhenTheAppAsksItself() {
        let center = CenterSpy()
        let service = NotificationService(
            config: RelevaConfig(requestsNotificationAuthorization: false),
            center: center
        )

        service.initialize()

        XCTAssertEqual(center.settingsRequests, 0)
        XCTAssertTrue(center.authorizationRequests.isEmpty)
        XCTAssertTrue(center.delegate === service, "everything else about enabling tracking is unchanged")
        XCTAssertFalse(center.categories.isEmpty, "including the SDK's categories")
    }

    func testTheSdksOwnRequestIsWhatItHasAlwaysAskedFor() async {
        let center = CenterSpy()
        let service = NotificationService(config: RelevaConfig(), center: center)

        let granted = await service.requestAuthorization()

        XCTAssertFalse(granted, "the centre denied it")
        XCTAssertEqual(center.authorizationRequests, [[.alert, .badge, .sound]])
    }

    func testTheClientAsksWithTheOptionsItIsGiven() async {
        let center = CenterSpy()
        let client = offlineClient()
        client.notificationService = NotificationService(config: client.config, center: center)

        let granted = await client.requestPushAuthorization(options: [.alert, .providesAppNotificationSettings])

        XCTAssertFalse(granted)
        XCTAssertEqual(
            center.authorizationRequests,
            [[.alert, .providesAppNotificationSettings]],
            "the options the SDK's own request cannot express are the point of this entry point"
        )
    }
}
