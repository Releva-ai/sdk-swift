import XCTest
@testable import RelevaSDK

/// `BannerDisplayViewModel` is the one place both the SwiftUI modifier and `BannerPresenter`
/// report impressions, clicks and dismissals, so a regression here can affect an existing
/// SwiftUI integration even though it was changed for the UIKit path. These tests cover it
/// directly, with no window and no presenter — in particular `overlayOnly`, the one branch of
/// `shouldDisplay` this PR added, which until now was pinned by nothing but reading.
final class BannerDisplayViewModelTests: XCTestCase {
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
            design: Self.minimalDesign
        )
    }

    /// One row, one column, one text block: the smallest design the view model will display.
    static let minimalDesign: [String: JSONValue] = [
        "body": ["rows": [["columns": [["contents": [["type": "text", "values": ["text": "x"]]]]]]]]
    ]

    // MARK: - empty designs and popup queueing

    @MainActor
    func testDesignWithoutContentIsNotShownOrCounted() {
        let viewModel = BannerDisplayViewModel()
        let tracker = BannerTrackerSpy()
        defer { viewModel.stop() }
        viewModel.start(tracker: tracker, targetSelector: "", onLinkTap: nil)
        BannerDisplayController.shared.showBanner(BannerResponse(token: "empty", displayType: "popup", design: ["body": ["rows": []]]))
        drainMainQueue()
        XCTAssertNil(viewModel.popupBanner)
        XCTAssertTrue(tracker.impressions.isEmpty)
    }

    @MainActor
    func testSecondPopupWaitsForTheFirstAndIsCountedWhenShown() {
        let viewModel = BannerDisplayViewModel()
        let tracker = BannerTrackerSpy()
        defer { viewModel.stop() }
        viewModel.start(tracker: tracker, targetSelector: "", onLinkTap: nil)
        let first = banner("p1", displayType: "popup")
        let second = banner("p2", displayType: "popup")
        BannerDisplayController.shared.showBanner(first)
        BannerDisplayController.shared.showBanner(second)
        drainMainQueue()

        XCTAssertEqual(viewModel.popupBanner?.token, "p1", "the first stays up")
        XCTAssertEqual(tracker.impressions, ["p1"], "the waiting one is not counted yet")

        viewModel.dismissPopup(first)
        XCTAssertEqual(viewModel.popupBanner?.token, "p2", "the second follows")
        XCTAssertEqual(tracker.impressions, ["p1", "p2"])
        XCTAssertEqual(tracker.actions, ["p1:bannerClose"])
    }

    /// `stop()` clears `queuedPopups`/`queuedFlyouts` (a tab switch cancels the pending queue)
    /// but, before this fix, left the dropped banner's token in `displayedBanners` with nothing
    /// left to ever remove it — so `BannerManagerService.initialize` re-arming and re-triggering
    /// the same banner on the next screen view was silently dropped by the guard in
    /// `handleBanner`, and it could never re-enter the queue at all, even after the popup ahead
    /// of it was eventually dismissed. `stop()` deliberately leaves `popupBanner` itself alone
    /// (a currently-showing popup is not "never shown"), so the re-triggered banner is expected
    /// to land back in the queue, not to display immediately. This pins the synchronous half of
    /// the fix (the queue-drop path); the cancelled-prefetch half needs a controllable async
    /// image load to pin the same way and is covered by inspection.
    @MainActor
    func testStopReleasesAQueuedPopupSoARetriggerCanQueueItAgain() {
        let viewModel = BannerDisplayViewModel()
        let tracker = BannerTrackerSpy()
        viewModel.start(tracker: tracker, targetSelector: "", onLinkTap: nil)
        let first = banner("p1", displayType: "popup")
        let second = banner("p2", displayType: "popup")
        BannerDisplayController.shared.showBanner(first)
        BannerDisplayController.shared.showBanner(second)
        drainMainQueue()
        XCTAssertEqual(viewModel.popupBanner?.token, "p1")
        XCTAssertEqual(tracker.impressions, ["p1"], "p2 is still queued, not shown")

        // Tab switch: the queue is torn down while p1 is still showing and p2 is still waiting.
        viewModel.stop()

        // The next screen view re-arms and re-triggers the same banner.
        viewModel.start(tracker: tracker, targetSelector: "", onLinkTap: nil)
        defer { viewModel.stop() }
        BannerDisplayController.shared.showBanner(second)
        drainMainQueue()

        // p1 is untouched by stop(), so p2 re-queues behind it rather than showing immediately —
        // the point is that it is queued at all, where before the fix it was dropped for good.
        XCTAssertEqual(viewModel.popupBanner?.token, "p1", "p1 was never dismissed")
        XCTAssertEqual(tracker.impressions, ["p1"], "p2 has re-queued, not shown yet")

        viewModel.dismissPopup(first)

        XCTAssertEqual(viewModel.popupBanner?.token, "p2", "p2 must have re-entered the queue to be shown here")
        XCTAssertEqual(tracker.impressions, ["p1", "p2"])
    }

    // MARK: - overlayOnly (BannerPresenter's mode)

    @MainActor
    func testOverlayOnlyAcceptsPopupFlyoutAndBar() {
        let viewModel = BannerDisplayViewModel()
        let tracker = BannerTrackerSpy()
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
        let tracker = BannerTrackerSpy()
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
        let tracker = BannerTrackerSpy()
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
        let tracker = BannerTrackerSpy()
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
        let tracker = BannerTrackerSpy()
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
