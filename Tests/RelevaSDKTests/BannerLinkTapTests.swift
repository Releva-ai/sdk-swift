import XCTest
@testable import RelevaSDK

/// A link tapped inside a banner's design reports a `bannerClick` and routes the link. A popup or a
/// flyout closes first, with no `bannerClose`; a bar stays up. `BannerChrome.linkTap` is the handler
/// all three hand to `DesignRenderer`, given the `close` each passes.
final class BannerLinkTapTests: XCTestCase {
    private static let url = "https://example.com/sale"

    @MainActor
    func testALinkInAPopupClosesItAndReportsOnlyTheClick() {
        let popup = banner("popup-link", displayType: "popup")
        let tap = tapLink(in: popup, close: { $0.dismissPopup(popup, track: false) }, configure: { $0.popupBanner = popup })

        XCTAssertEqual(tap.routed, [Self.url])
        XCTAssertEqual(tap.tracker.actions, ["popup-link:bannerClick"])
        XCTAssertNil(tap.viewModel.popupBanner, "the popup closes")
        XCTAssertEqual(tap.closedBeforeClick, true, "the popup closes before the click is reported")
    }

    @MainActor
    func testALinkInAFlyoutClosesItAndReportsOnlyTheClick() {
        let flyout = banner("flyout-link", displayType: "flyout")
        let tap = tapLink(in: flyout, close: { $0.dismissFlyout(flyout, track: false) }, configure: { $0.flyoutBanner = flyout })

        XCTAssertEqual(tap.routed, [Self.url])
        XCTAssertEqual(tap.tracker.actions, ["flyout-link:bannerClick"])
        XCTAssertNil(tap.viewModel.flyoutBanner, "the flyout closes")
        XCTAssertEqual(tap.closedBeforeClick, true, "the flyout closes before the click is reported")
    }

    @MainActor
    func testALinkInABarKeepsTheBarUp() {
        let bar = banner("bar-link", displayType: "bar")
        let tap = tapLink(in: bar, close: nil) { $0.barBanners = [bar] }

        XCTAssertEqual(tap.routed, [Self.url])
        XCTAssertEqual(tap.tracker.actions, ["bar-link:bannerClick"])
        XCTAssertEqual(tap.viewModel.barBanners.map(\.token), ["bar-link"], "the bar stays up")
    }

    // MARK: - Harness

    private struct Tap {
        let viewModel: BannerDisplayViewModel
        let tracker: BannerTrackerSpy
        let routed: [String]
        /// Whether no click had been reported when `close` ran; `nil` when there was no `close`.
        let closedBeforeClick: Bool?
    }

    @MainActor
    private func tapLink(
        in banner: BannerResponse,
        close: ((BannerDisplayViewModel) -> Void)?,
        configure: (BannerDisplayViewModel) -> Void
    ) -> Tap {
        final class Log { var urls: [String] = []; var closedBeforeClick: Bool? }
        let log = Log()
        let tracker = BannerTrackerSpy()
        let viewModel = BannerDisplayViewModel()
        viewModel.start(tracker: tracker, targetSelector: "", overlayOnly: true, onLinkTap: nil)
        defer { viewModel.stop() }
        configure(viewModel)

        let closeBanner: (() -> Void)? = close.map { close in
            {
                log.closedBeforeClick = tracker.actions.isEmpty
                close(viewModel)
            }
        }
        BannerChrome.linkTap(banner, viewModel: viewModel, close: closeBanner) { log.urls.append($0) }(Self.url)
        return Tap(viewModel: viewModel, tracker: tracker, routed: log.urls, closedBeforeClick: log.closedBeforeClick)
    }

    private func banner(_ token: String, displayType: String) -> BannerResponse {
        BannerResponse(token: token, displayType: displayType, design: BannerDisplayViewModelTests.minimalDesign)
    }
}
