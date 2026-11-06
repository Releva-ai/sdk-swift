import UserNotifications
import XCTest
@testable import RelevaSDK

/// Who asks for notification permission. By default the SDK still asks on
/// `enablePushEngagementTracking()`, as it always has; with
/// `RelevaConfig.requestsNotificationAuthorization` off it never does, and the app asks through
/// `RelevaClient.requestPushAuthorization(options:)` instead.
@MainActor
final class NotificationAuthorizationTests: XCTestCase {
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
