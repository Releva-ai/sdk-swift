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

    // MARK: - empty designs and the popup slot

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

    /// As in sdk-react-native's single `popupBanner` slot: a newer popup replaces the one on
    /// screen, both are counted, and the replaced one is not closed, so no close is tracked.
    @MainActor
    func testANewerPopupReplacesTheOneOnScreenWithoutTrackingAClose() {
        let viewModel = BannerDisplayViewModel()
        let tracker = BannerTrackerSpy()
        defer { viewModel.stop() }
        viewModel.start(tracker: tracker, targetSelector: "", onLinkTap: nil)
        BannerDisplayController.shared.showBanner(banner("p1", displayType: "popup"))
        BannerDisplayController.shared.showBanner(banner("p2", displayType: "popup"))
        drainMainQueue()

        XCTAssertEqual(viewModel.popupBanner?.token, "p2", "the newest is on screen")
        XCTAssertEqual(tracker.impressions, ["p1", "p2"])
        XCTAssertEqual(tracker.actions, [], "the replaced popup was not closed")

        viewModel.dismissPopup(banner("p2", displayType: "popup"))
        XCTAssertNil(viewModel.popupBanner, "the replaced popup does not come back")
        XCTAssertEqual(tracker.actions, ["p2:bannerClose"])
    }

    /// A popup and a flyout share that one slot, so each replaces the other.
    @MainActor
    func testAPopupAndAFlyoutReplaceEachOther() {
        let viewModel = BannerDisplayViewModel()
        let tracker = BannerTrackerSpy()
        defer { viewModel.stop() }
        viewModel.start(tracker: tracker, targetSelector: "", onLinkTap: nil)
        BannerDisplayController.shared.showBanner(banner("popup-1", displayType: "popup"))
        BannerDisplayController.shared.showBanner(banner("flyout-1", displayType: "flyout"))
        drainMainQueue()
        XCTAssertNil(viewModel.popupBanner)
        XCTAssertEqual(viewModel.flyoutBanner?.token, "flyout-1")

        BannerDisplayController.shared.showBanner(banner("popup-2", displayType: "popup"))
        drainMainQueue()
        XCTAssertEqual(viewModel.popupBanner?.token, "popup-2")
        XCTAssertNil(viewModel.flyoutBanner)
        XCTAssertEqual(tracker.impressions, ["popup-1", "flyout-1", "popup-2"])
        XCTAssertEqual(tracker.actions, [])
    }

    /// A replaced popup is released, so a later trigger of the same banner shows it again.
    @MainActor
    func testAReplacedPopupCanBeShownAgain() {
        let viewModel = BannerDisplayViewModel()
        let tracker = BannerTrackerSpy()
        defer { viewModel.stop() }
        viewModel.start(tracker: tracker, targetSelector: "", onLinkTap: nil)
        BannerDisplayController.shared.showBanner(banner("p1", displayType: "popup"))
        BannerDisplayController.shared.showBanner(banner("p2", displayType: "popup"))
        BannerDisplayController.shared.showBanner(banner("p1", displayType: "popup"))
        drainMainQueue()

        XCTAssertEqual(viewModel.popupBanner?.token, "p1")
        XCTAssertEqual(tracker.impressions, ["p1", "p2", "p1"])
    }

    /// Arrival order decides, not the order image prefetches finish in: a popup that waited for
    /// its images does not replace a newer one already on screen. It is still counted.
    @MainActor
    func testAnOlderPopupWhosePrefetchFinishesLastDoesNotReplaceANewerOne() {
        let viewModel = BannerDisplayViewModel()
        let tracker = BannerTrackerSpy()
        defer { viewModel.stop() }
        viewModel.start(tracker: tracker, targetSelector: "", onLinkTap: nil)
        let withImage: [String: JSONValue] = [
            "body": ["rows": [["columns": [["contents": [
                ["type": "image", "values": ["src": ["url": "https://example.invalid/banner.jpg"]]]
            ]]]]]]
        ]
        BannerDisplayController.shared.showBanner(BannerResponse(token: "older", displayType: "popup", design: withImage))
        BannerDisplayController.shared.showBanner(banner("newer", displayType: "popup"))
        drainMainQueue()
        XCTAssertEqual(viewModel.popupBanner?.token, "newer")

        waitUntil("the older popup's prefetch finished", timeout: BannerDisplayViewModel.imagePrefetchTimeout + 3) {
            tracker.impressions.count == 2
        }
        XCTAssertEqual(viewModel.popupBanner?.token, "newer", "the newer popup stays up")
        XCTAssertEqual(tracker.impressions, ["newer", "older"])
        XCTAssertEqual(tracker.actions, [])
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

        XCTAssertNil(viewModel.popupBanner, "the flyout replaced the popup in their shared slot")
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
