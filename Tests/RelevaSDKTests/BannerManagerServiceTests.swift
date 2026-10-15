import Combine
import UIKit
import XCTest
@testable import RelevaSDK

/// A popup or a flyout is shown once per session, as in sdk-react-native's BannerManagerService:
/// a later push response that delivers it again does not show it again, bars and static banners
/// are re-shown by every response, and the memory resets when a new session begins or the client
/// is shut down.
@MainActor
final class BannerManagerServiceTests: XCTestCase {
    private var shown: [String] = []
    private var subscription: AnyCancellable?

    override func setUp() {
        super.setUp()
        BannerManagerService.startNewSession()
        shown = []
        subscribe()
    }

    override func tearDown() {
        subscription?.cancel()
        subscription = nil
        BannerManagerService.startNewSession()
        super.tearDown()
    }

    /// Stands in for a display surface: records every banner emitted while subscribed.
    private func subscribe() {
        subscription = BannerDisplayController.shared.bannerPublisher
            .sink { [weak self] banner in self?.shown.append(banner.token) }
    }

    private func banner(_ token: String, _ displayType: String, trigger: String = "immediately") -> BannerResponse {
        BannerResponse(token: token, displayType: displayType, trigger: trigger)
    }

    // MARK: - One-shot display types

    func testAPopupIsNotShownAgainByALaterResponseInTheSameSession() {
        let manager = BannerManagerService()
        manager.initialize(newBanners: [banner("popup-1", "popup")])
        manager.initialize(newBanners: [banner("popup-1", "popup")])
        XCTAssertEqual(shown, ["popup-1"])
    }

    func testAFlyoutIsNotShownAgainByALaterResponseInTheSameSession() {
        let manager = BannerManagerService()
        manager.initialize(newBanners: [banner("fly-1", "flyout")])
        manager.initialize(newBanners: [banner("fly-1", "flyout")])
        XCTAssertEqual(shown, ["fly-1"])
    }

    /// The memory is the session's: a second manager, as a host might make per screen, and a
    /// disposed one do not bring the popup back.
    func testTheMemoryIsSharedByEveryManagerAndSurvivesDispose() {
        let first = BannerManagerService()
        first.initialize(newBanners: [banner("popup-1", "popup")])
        first.dispose()

        let second = BannerManagerService()
        second.initialize(newBanners: [banner("popup-1", "popup")])
        XCTAssertEqual(shown, ["popup-1"])
    }

    func testAnotherPopupIsStillShown() {
        let manager = BannerManagerService()
        manager.initialize(newBanners: [banner("popup-1", "popup")])
        manager.initialize(newBanners: [banner("popup-1", "popup"), banner("popup-2", "popup")])
        XCTAssertEqual(shown, ["popup-1", "popup-2"])
    }

    /// Cart and wishlist triggers are suppressed the same way once their popup has been shown.
    func testACartChangedPopupIsShownOncePerSession() {
        let manager = BannerManagerService()
        manager.initialize(newBanners: [banner("cart-popup", "popup", trigger: "cartChanged")])
        manager.onCartChanged()
        manager.onCartChanged()
        manager.initialize(newBanners: [banner("cart-popup", "popup", trigger: "cartChanged")])
        manager.onCartChanged()
        XCTAssertEqual(shown, ["cart-popup"])
    }

    func testAScrollPopupIsShownOncePerSession() {
        let manager = BannerManagerService()
        let popup = BannerResponse(token: "scroll-popup", displayType: "popup", scrollPercentage: 50, trigger: "scrollPercentage")
        manager.initialize(newBanners: [popup])
        manager.onScroll(percentage: 60)
        manager.initialize(newBanners: [popup])
        manager.onScroll(percentage: 80)
        XCTAssertEqual(shown, ["scroll-popup"])
    }

    // MARK: - Bars and static banners

    /// A bar or a static banner is page content: every response that delivers it shows it.
    func testBarsAndStaticBannersAreShownByEveryResponse() {
        let manager = BannerManagerService()
        let banners = [banner("bar-1", "bar"), banner("static-1", "static")]
        manager.initialize(newBanners: banners)
        manager.initialize(newBanners: banners)
        XCTAssertEqual(shown, ["bar-1", "static-1", "bar-1", "static-1"])
    }

    /// Within one response a banner is shown once, whatever its type.
    func testABarIsShownOncePerResponse() {
        let manager = BannerManagerService()
        manager.initialize(newBanners: [banner("cart-bar", "bar", trigger: "cartChanged")])
        manager.onCartChanged()
        manager.onCartChanged()
        XCTAssertEqual(shown, ["cart-bar"])
    }

    // MARK: - Delivery

    /// A popup emitted while no display surface is subscribed was never shown, so it keeps its
    /// one showing for when a surface is there.
    func testAPopupNobodyReceivedIsShownByTheNextResponse() {
        subscription?.cancel()
        subscription = nil
        XCTAssertFalse(BannerDisplayController.shared.hasSubscribers, "precondition: no display surface is subscribed")

        let manager = BannerManagerService()
        manager.initialize(newBanners: [banner("popup-1", "popup")])
        XCTAssertTrue(shown.isEmpty)

        subscribe()
        manager.initialize(newBanners: [banner("popup-1", "popup")])
        manager.initialize(newBanners: [banner("popup-1", "popup")])
        XCTAssertEqual(shown, ["popup-1"])
    }

    func testShowBannerReportsWhetherASurfaceIsSubscribed() {
        XCTAssertTrue(BannerDisplayController.shared.showBanner(banner("probe-1", "popup")))
        subscription?.cancel()
        subscription = nil
        XCTAssertFalse(BannerDisplayController.shared.showBanner(banner("probe-2", "popup")))
    }

    // MARK: - Reset

    func testANewSessionShowsThePopupAgain() {
        let manager = BannerManagerService()
        manager.initialize(newBanners: [banner("popup-1", "popup")])
        BannerManagerService.startNewSession()
        manager.initialize(newBanners: [banner("popup-1", "popup")])
        XCTAssertEqual(shown, ["popup-1", "popup-1"])
    }

    /// `SessionService` starts a new session after a background longer than its threshold, and
    /// that clears the memory.
    func testSessionServiceStartingANewSessionShowsThePopupAgain() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "BannerManagerServiceTests_\(UUID().uuidString)"))
        let storage = StorageService(userDefaults: defaults)
        let savedThreshold = SessionService.debounceThresholdMs
        SessionService.shared.dispose()
        SessionService.debounceThresholdMs = -1
        defer {
            SessionService.shared.dispose()
            SessionService.debounceThresholdMs = savedThreshold
        }
        SessionService.shared.initialize(storage: storage, npsManager: nil)

        let manager = BannerManagerService()
        manager.initialize(newBanners: [banner("popup-1", "popup")])
        manager.initialize(newBanners: [banner("popup-1", "popup")])
        XCTAssertEqual(shown, ["popup-1"], "the same session keeps it suppressed")

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        manager.initialize(newBanners: [banner("popup-1", "popup")])
        XCTAssertEqual(shown, ["popup-1", "popup-1"], "a new session shows it again")
    }

    /// A replacement client continues the device session, so shutting the old one down is what
    /// clears the memory.
    func testShuttingTheClientDownShowsThePopupAgain() {
        let manager = BannerManagerService()
        manager.initialize(newBanners: [banner("popup-1", "popup")])

        let savedShared = RelevaClient.shared
        defer { RelevaClient.shared = savedShared }
        let client = RelevaClient(
            realm: "test",
            accessToken: "test-token",
            config: RelevaConfig(enableTracking: false, enablePushNotifications: false)
        )
        client.shutdown()

        manager.initialize(newBanners: [banner("popup-1", "popup")])
        XCTAssertEqual(shown, ["popup-1", "popup-1"])
    }
}
