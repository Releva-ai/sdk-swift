import XCTest
@testable import RelevaSDK

/// `BannerDisplayViewModel` is the one place both the SwiftUI modifier and `BannerPresenter`
/// report impressions, clicks and dismissals, so a regression here can affect an existing
/// SwiftUI integration even though it was changed for the UIKit path. These tests cover it
/// directly, with no window and no presenter — in particular `overlayOnly`, the one branch of
/// `shouldDisplay` this PR added, which until now was pinned by nothing but reading.
final class BannerDisplayViewModelTests: XCTestCase {

    @MainActor
    private final class TrackerSpy: BannerTracker {
        var impressions: [String] = []
        var actions: [String] = []

        func bannerImpression(_ banner: BannerResponse) {
            impressions.append(banner.token)
        }

        func bannerAction(_ banner: BannerResponse, action: String) {
            actions.append("\(banner.token):\(action)")
        }
    }

    @MainActor
    private func banner(
        _ token: String,
        displayType: String?,
        cssSelector: String? = nil,
        displayStrategy: String? = "afterbegin"
    ) -> BannerResponse {
        BannerResponse(
            token: token,
            displayType: displayType,
            cssSelector: cssSelector,
            displayStrategy: displayStrategy,
            design: ["body": ["rows": []]]
        )
    }

    // MARK: - overlayOnly (BannerPresenter's mode)

    @MainActor
    func testOverlayOnlyAcceptsPopupFlyoutAndBar() {
        let viewModel = BannerDisplayViewModel()
        let tracker = TrackerSpy()
        defer { viewModel.stop() }

        viewModel.start(tracker: tracker, targetSelector: "", overlayOnly: true, onLinkTap: nil)
        BannerDisplayController.shared.showBanner(banner("popup-ol", displayType: "popup"))
        BannerDisplayController.shared.showBanner(banner("flyout-ol", displayType: "flyout"))
        BannerDisplayController.shared.showBanner(banner("bar-ol", displayType: "bar"))
        drainMainQueue()

        XCTAssertEqual(viewModel.popupBanner?.token, "popup-ol")
        XCTAssertEqual(viewModel.flyoutBanner?.token, "flyout-ol")
        XCTAssertEqual(viewModel.barBanners.map(\.token), ["bar-ol"])
        XCTAssertEqual(Set(tracker.impressions), ["popup-ol", "flyout-ol", "bar-ol"])
    }

    @MainActor
    func testOverlayOnlyDropsStaticAndReplaceBannersBeforeTrackingAnImpression() {
        let viewModel = BannerDisplayViewModel()
        let tracker = TrackerSpy()
        defer { viewModel.stop() }

        viewModel.start(tracker: tracker, targetSelector: "#hero", overlayOnly: true, onLinkTap: nil)
        BannerDisplayController.shared.showBanner(
            banner("static-ol", displayType: "static", cssSelector: "#hero")
        )
        BannerDisplayController.shared.showBanner(
            banner("replace-ol", displayType: "static", cssSelector: "#hero", displayStrategy: "replace")
        )
        drainMainQueue()

        // A presenter has nowhere to lay either of these out inline, so `shouldDisplay` must
        // drop them before `trackImpression` runs — an impression for a banner nobody can see
        // would be a false report.
        XCTAssertTrue(viewModel.staticBannersBeforeContent.isEmpty)
        XCTAssertTrue(viewModel.replaceBanners.isEmpty)
        XCTAssertEqual(tracker.impressions, [])
    }

    // MARK: - Non-overlay (the SwiftUI modifier's mode, unchanged by this PR)

    @MainActor
    func testNonOverlayStillRoutesAMatchingStaticBannerToBeforeContent() {
        let viewModel = BannerDisplayViewModel()
        let tracker = TrackerSpy()
        defer { viewModel.stop() }

        viewModel.start(tracker: tracker, targetSelector: "#hero", overlayOnly: false, onLinkTap: nil)
        BannerDisplayController.shared.showBanner(
            banner("static-default", displayType: "static", cssSelector: "#hero")
        )
        drainMainQueue()

        XCTAssertEqual(viewModel.staticBannersBeforeContent.map(\.token), ["static-default"])
        XCTAssertEqual(tracker.impressions, ["static-default"])
    }

    @MainActor
    func testNonOverlayDropsAStaticBannerForADifferentSelector() {
        let viewModel = BannerDisplayViewModel()
        let tracker = TrackerSpy()
        defer { viewModel.stop() }

        viewModel.start(tracker: tracker, targetSelector: "#hero", overlayOnly: false, onLinkTap: nil)
        BannerDisplayController.shared.showBanner(
            banner("static-elsewhere", displayType: "static", cssSelector: "#other")
        )
        drainMainQueue()

        XCTAssertTrue(viewModel.staticBannersBeforeContent.isEmpty)
        XCTAssertEqual(tracker.impressions, [])
    }

    // MARK: - Tracking action strings

    @MainActor
    func testTrackClickReportsTheClickActionRatherThanTheCloseOne() {
        let viewModel = BannerDisplayViewModel()
        let tracker = TrackerSpy()
        defer { viewModel.stop() }

        viewModel.start(tracker: tracker, targetSelector: "", overlayOnly: true, onLinkTap: nil)
        let popup = banner("popup-click", displayType: "popup")
        BannerDisplayController.shared.showBanner(popup)
        drainMainQueue()

        // What `BannerChrome`'s `onLinkTap` closures call — the hosted-chrome path both the
        // presenter and the modifier share.
        viewModel.trackClick(popup)

        XCTAssertEqual(tracker.actions, ["popup-click:bannerClick"])
    }
}
