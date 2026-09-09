import UIKit
import XCTest
@testable import RelevaSDK

/// `init` pins the first `RelevaClient` as `RelevaClient.shared`, and a replaced instance that is
/// still alive keeps calling `refreshPushToken()` from its foreground observer under its previous
/// profile. `shutdown()` makes an instance inert.
@MainActor
final class RelevaClientShutdownTests: XCTestCase {
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

    private func makeClient() -> RelevaClient {
        RelevaClient(
            realm: "test",
            accessToken: "test-token",
            config: RelevaConfig(enableTracking: false, enablePushNotifications: true)
        )
    }

    /// Posts `didBecomeActive` and lets the observer's main-queue hop and its `Task` run.
    private func activateApp() {
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        drainMainQueue(turns: 4)
    }

    func testForegroundNoLongerAsksForAPushTokenAfterShutdown() {
        let client = makeClient()
        var providerCalls = 0
        client.pushTokenProvider = { completion in
            providerCalls += 1
            completion(nil) // an empty token stops the refresh before any network I/O
        }

        activateApp()
        XCTAssertEqual(providerCalls, 1, "control: a live client refreshes its token on foreground")

        client.shutdown()
        XCTAssertTrue(client.isShutDown)

        activateApp()
        client.refreshPushToken()
        drainMainQueue()
        XCTAssertEqual(providerCalls, 1, "a shut-down client must not touch the push token again")
    }

    func testShutdownReleasesTheSharedInstanceSlot() {
        let first = makeClient()
        XCTAssertTrue(RelevaClient.shared === first, "the first client becomes the shared instance")

        first.shutdown()
        XCTAssertNil(RelevaClient.shared, "a shut-down client must not stay pinned as shared")

        let second = makeClient()
        XCTAssertTrue(RelevaClient.shared === second, "the replacement takes the slot")
        second.shutdown()
    }
}
