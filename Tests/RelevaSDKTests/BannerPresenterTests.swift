import SwiftUI
import UIKit
import XCTest
@testable import RelevaSDK

/// A presenter over a host in a visible window, reporting to a spy.
private struct BannerFixture {
    let host: UIViewController
    let window: UIWindow
    let tracker: BannerTrackerSpy
    let presenter: BannerPresenter
}

/// `BannerPresenter` draws nothing of its own and tracks nothing of its own: it hosts the same
/// SwiftUI chrome the modifier does, and every impression, click and dismissal goes through the
/// `BannerDisplayViewModel` both paths share. So these tests cover what the presenter adds —
/// which banners it accepts, what it puts on screen for each of them, and that the shared
/// tracking still fires — driven through `BannerDisplayController.shared`, the singleton
/// `BannerManagerService` publishes to in production.
///
/// They assert on what the presenter did and what it reported, never on UIKit having *finished* a
/// presentation or a dismissal: transitions do not complete in this test host, and
/// `PresentationTestSupport.makeVisibleWindow` records exactly what that does and does not cost.
final class BannerPresenterTests: XCTestCase {
    // MARK: - Presenting

    @MainActor
    func testPopupIsPresentedOverTheHostAndCounted() {
        let fixture = makeFixture()
        defer { takeDown(fixture) }

        fixture.presenter.start()
        BannerDisplayController.shared.showBanner(banner("popup-1", displayType: "popup"))
        drainMainQueue()

        XCTAssertEqual(fixture.tracker.impressions, ["popup-1"])
        waitUntil("the overlay is presented") { fixture.host.presentedViewController != nil }
        XCTAssertTrue(
            fixture.host.presentedViewController is UIHostingController<BannerOverlayView>,
            "expected the hosted overlay, got \(String(describing: fixture.host.presentedViewController))"
        )
        XCTAssertEqual(fixture.host.presentedViewController?.modalPresentationStyle, .overFullScreen)
    }

    /// The presenter presents from `host.topMostPresentedViewController` so that a banner
    /// arriving while the app already has a modal up lands over it instead of failing with
    /// "already presenting". That choice of target is the presenter's own logic, so it is tested
    /// directly: presenting the overlay onto the modal end to end would need the modal's
    /// transition to complete first, which this test host cannot do.
    @MainActor
    func testTheOverlayTargetIsTheFrontmostModalRatherThanTheHost() {
        let host = UIViewController()
        let window = makeVisibleWindow(rootViewController: host)
        // Not dismissed: a dismissal would not complete here either. The modal goes away with
        // the host when the window does.
        defer { window.isHidden = true }

        let existingModal = UIViewController()
        host.present(existingModal, animated: false)
        waitUntil("the existing modal is presented") { host.presentedViewController != nil }

        XCTAssertTrue(
            host.topMostPresentedViewController === existingModal,
            "a banner must be presented over the modal the app already has up, not from the host underneath it"
        )
    }

    @MainActor
    func testPopupAndFlyoutArrivingTogetherShareOneOverlay() {
        let fixture = makeFixture()
        defer { takeDown(fixture) }

        fixture.presenter.start()
        BannerDisplayController.shared.showBanner(banner("popup-1", displayType: "popup"))
        BannerDisplayController.shared.showBanner(banner("flyout-1", displayType: "flyout"))
        drainMainQueue()

        XCTAssertEqual(fixture.tracker.impressions, ["popup-1", "flyout-1"])
        XCTAssertNil(fixture.presenter.viewModel.popupBanner, "the flyout replaced the popup")
        XCTAssertEqual(fixture.presenter.viewModel.flyoutBanner?.token, "flyout-1")
        XCTAssertEqual(fixture.tracker.actions, [], "the replaced popup was not closed")
        waitUntil("the overlay is presented") { fixture.host.presentedViewController != nil }
        // Both banners are slots in one hosted view, so the second must not stack a second
        // modal on top of the first.
        XCTAssertNil(fixture.host.presentedViewController?.presentedViewController)
    }

    @MainActor
    func testSwappingPopupForFlyoutNeverEmptiesTheOverlay() {
        let fixture = makeFixture()
        defer { takeDown(fixture) }

        fixture.presenter.start()
        BannerDisplayController.shared.showBanner(banner("popup-1", displayType: "popup"))
        drainMainQueue()
        waitUntil("the overlay is presented") { fixture.host.presentedViewController != nil }
        let overlay = fixture.host.presentedViewController

        // The presenter dismisses its overlay on any state with neither slot set, so the swap
        // must never pass through one.
        var emptied = false
        let watch = fixture.presenter.viewModel.$popupBanner
            .combineLatest(fixture.presenter.viewModel.$flyoutBanner)
            .sink { popup, flyout in if popup == nil && flyout == nil { emptied = true } }
        BannerDisplayController.shared.showBanner(banner("flyout-1", displayType: "flyout"))
        BannerDisplayController.shared.showBanner(banner("popup-2", displayType: "popup"))
        drainMainQueue()
        watch.cancel()

        XCTAssertFalse(emptied, "a swap between a popup and a flyout passed through an empty overlay")
        XCTAssertEqual(fixture.presenter.viewModel.popupBanner?.token, "popup-2")
        XCTAssertNil(fixture.presenter.viewModel.flyoutBanner)
        XCTAssertTrue(fixture.host.presentedViewController === overlay, "the overlay stayed up through both swaps")
    }

    @MainActor
    func testBarIsHostedInTheHostsOwnViewRatherThanPresented() {
        let fixture = makeFixture()
        defer { takeDown(fixture) }

        fixture.presenter.start()
        BannerDisplayController.shared.showBanner(banner("bar-1", displayType: "bar"))
        drainMainQueue()

        XCTAssertEqual(fixture.tracker.impressions, ["bar-1"])
        // A modal would black the whole screen out for a strip of chrome, so bars go in one child
        // controller laid over the host's view instead.
        XCTAssertNil(fixture.host.presentedViewController)
        XCTAssertEqual(fixture.host.children.count, 1)
    }

    @MainActor
    func testStaticBannerIsNeitherShownNorCounted() {
        let fixture = makeFixture()
        defer { takeDown(fixture) }

        fixture.presenter.start()
        BannerDisplayController.shared.showBanner(banner("static-1", displayType: "static"))
        drainMainQueue()

        // A static banner belongs inline in the host's own content, where a presenter cannot
        // put it. An impression for a banner nobody can see would be a false report, so it is
        // dropped before tracking rather than after.
        XCTAssertEqual(fixture.tracker.impressions, [])
        XCTAssertNil(fixture.host.presentedViewController)
    }

    // MARK: - Taking banners down

    @MainActor
    func testDismissingThePopupTakesTheOverlayDownAndReportsTheClose() {
        let fixture = makeFixture()
        defer { takeDown(fixture) }

        let popup = banner("popup-1", displayType: "popup")
        fixture.presenter.start()
        BannerDisplayController.shared.showBanner(popup)
        drainMainQueue()
        waitUntil("the overlay is presented") { fixture.host.presentedViewController != nil }

        // What the close button in the hosted chrome calls.
        fixture.presenter.viewModel.dismissPopup(popup)
        drainMainQueue()

        XCTAssertEqual(fixture.tracker.actions, ["popup-1:bannerClose"])
        // `overlayController` is cleared from the dismiss completion, not up front — see
        // `syncOverlay` — precisely so a dismissal UIKit declines does not orphan the overlay.
        // That completion needs a transition to actually finish, which this test host's windows
        // (no `UIWindowScene`) never do, so asserting on `overlayController` here would only pin
        // the harness's inability to finish a transition, not presenter behaviour — see
        // `PresentationTestSupport.makeVisibleWindow`. `dismissPopup` clearing `popupBanner`
        // synchronously, independent of any UIKit transition, is the fact that actually holds.
        XCTAssertNil(fixture.presenter.viewModel.popupBanner, "the dismissed banner must leave the view model")
    }

    @MainActor
    func testDismissingTheFlyoutReportsTheCloseWithoutTheWrongActionString() {
        let fixture = makeFixture()
        defer { takeDown(fixture) }

        let flyout = banner("flyout-1", displayType: "flyout")
        fixture.presenter.start()
        BannerDisplayController.shared.showBanner(flyout)
        drainMainQueue()
        waitUntil("the overlay is presented") { fixture.host.presentedViewController != nil }

        fixture.presenter.viewModel.dismissFlyout(flyout)
        drainMainQueue()

        XCTAssertEqual(fixture.tracker.actions, ["flyout-1:bannerClose"])
        // Same harness limitation as the popup case above: the dismiss completion that clears
        // `overlayController` needs a transition to finish, which never happens here, so the
        // transition-independent fact — `dismissFlyout` clearing `flyoutBanner` synchronously —
        // is what is asserted instead.
        XCTAssertNil(fixture.presenter.viewModel.flyoutBanner, "the dismissed banner must leave the view model")
    }

    @MainActor
    func testDismissingABarReportsTheCloseAndTakesItOutOfTheStack() {
        let fixture = makeFixture()
        defer { takeDown(fixture) }

        let bar = banner("bar-1", displayType: "bar")
        fixture.presenter.start()
        BannerDisplayController.shared.showBanner(bar)
        drainMainQueue()

        fixture.presenter.viewModel.dismissBar(bar)
        drainMainQueue()

        XCTAssertEqual(fixture.tracker.actions, ["bar-1:bannerClose"])
        XCTAssertTrue(
            fixture.presenter.viewModel.barBanners.isEmpty,
            "a dismissed bar must come out of the stack, not just report its close"
        )
    }

    @MainActor
    func testStopTakesEverythingDownAndIgnoresLaterBanners() {
        let fixture = makeFixture()
        defer { takeDown(fixture) }

        fixture.presenter.start()
        BannerDisplayController.shared.showBanner(banner("popup-1", displayType: "popup"))
        drainMainQueue()
        waitUntil("the overlay is presented") { fixture.host.presentedViewController != nil }

        let stale = fixture.presenter.overlayController
        fixture.presenter.stop()
        // `stop()` either lets go of `overlayController` (the dismissal took effect immediately)
        // or keeps it (UIKit declined, so the reference is all that can still reach the overlay);
        // both are branches the source deliberately has, and which one runs depends on the
        // transition, which this test host never finishes. Either is fine here. What must not
        // happen is a third value: an overlay a late reconcile put up. The impression assertion
        // at the end of this test is the stronger statement about the subscription being gone;
        // this one is about nothing new reaching the screen.
        let overlay = fixture.presenter.overlayController
        XCTAssertTrue(
            overlay == nil || overlay === stale,
            "a stopped presenter must not put anything back on screen"
        )
        XCTAssertTrue(fixture.host.children.isEmpty, "the bar layer must come off with the presenter")

        BannerDisplayController.shared.showBanner(banner("popup-2", displayType: "popup"))
        drainMainQueue()

        XCTAssertEqual(
            fixture.tracker.impressions,
            ["popup-1"],
            "a stopped presenter must not count banners"
        )
    }

    /// `stop()`'s doc comment and the CHANGELOG both promise that the view model's banner state
    /// survives a `stop()` / `start()` round trip, so a banner still held from before the stop
    /// does not get counted twice. `viewModel.stop()` only cancels the subscription, leaving
    /// `displayedBanners` populated, and `handleBanner`'s `guard !displayedBanners.contains` is
    /// what absorbs the banner when it comes round again.
    ///
    /// The re-delivery below is what makes that mechanism observable at all:
    /// `BannerDisplayController.bannerPublisher` is a `PassthroughSubject` with no replay, so
    /// `start()` on its own receives nothing and no code between it and the assertion can reach
    /// `trackImpression` — the count would hold with `displayedBanners` cleared, with the guard
    /// deleted, or with `start()` doing nothing at all. A fresh `BannerResponse` carrying a
    /// token that is already in the set is exactly the production case: the set is keyed on
    /// token, not on instance.
    ///
    /// The *presentation* half of the round trip is deliberately not asserted: `stop()` only
    /// clears `overlayController` once `presentingViewController` reads back `nil`, which needs
    /// the declined dismiss's completion to have run, and this test host's transitions never
    /// complete — see `PresentationTestSupport.makeVisibleWindow`.
    @MainActor
    func testStopThenStartDoesNotCountASecondImpressionForTheRetainedBanner() {
        let fixture = makeFixture()
        defer { takeDown(fixture) }

        fixture.presenter.start()
        BannerDisplayController.shared.showBanner(banner("popup-1", displayType: "popup"))
        drainMainQueue()
        waitUntil("the overlay is presented") { fixture.host.presentedViewController != nil }

        fixture.presenter.stop()
        fixture.presenter.start()
        BannerDisplayController.shared.showBanner(banner("popup-1", displayType: "popup"))
        drainMainQueue()

        XCTAssertEqual(fixture.tracker.impressions, ["popup-1"], "the retained banner is not counted twice")
    }

    // MARK: - Layout

    /// The presenter's overlay places a flyout the way the overlay window does: an unsized card is
    /// 80% of the window wide and full-bleed from the top of the screen to its bottom, which needs
    /// the safe-area insets the overlay view reads for itself.
    @MainActor
    func testTheOverlaysFlyoutIsPlacedInTheWholeWindow() {
        final class Frames { var value: [CGRect] = [] }
        let frames = Frames()
        let viewModel = BannerDisplayViewModel()
        viewModel.flyoutBanner = BannerResponse(
            token: "fly-1",
            displayType: "flyout",
            displayPosition: "right",
            design: BannerDisplayViewModelTests.minimalDesign
        )
        let controller = UIHostingController(
            rootView: BannerOverlayView(viewModel: viewModel) { _ in }
                .onPreferenceChange(BannerFramesKey.self) { frames.value = $0 }
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        drainMainQueue(turns: 6)
        window.layoutIfNeeded()
        defer { window.isHidden = true }

        XCTAssertGreaterThan(controller.view.safeAreaInsets.top, 0, "the window has a status bar to run under")
        guard let card = frames.value.first else { return XCTFail("the flyout reported no frame") }
        XCTAssertEqual(card.minX, 402 * 0.2, accuracy: 0.5)
        XCTAssertEqual(card.maxX, 402, accuracy: 0.5)
        XCTAssertEqual(card.minY, 0, accuracy: 0.5)
        XCTAssertEqual(card.maxY, 874, accuracy: 0.5)
    }

    /// The presenter lays bars out exactly as the overlay window does: top bars from the host's
    /// safe-area top with no inset in the card, a centred bar centred between there and the bottom
    /// edge, and bottom bars up from the bottom edge with the bottom inset inside the last card.
    @MainActor
    func testBarsAreLaidOutAsTheOverlayWindowLaysThemOut() throws {
        let extraInsets = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        let bars = [
            bar("top-1", position: "top"),
            bar("top-2", position: "top", keys: ["cardPositionHorizontal": "center", "cardWidth": "240px"]),
            bar("centre", position: "top", keys: ["cardPositionVertical": "center", "cardWidth": "200px"]),
            bar("bottom-1", position: "bottom", keys: ["cardHeight": "10%"]),
            bar("bottom-2", position: "bottom", keys: ["cardBackgroundColor": "#ff00ff"])
        ]
        let expected = overlayBarFrames(bars, extraInsets: extraInsets)

        let fixture = makeFixture()
        defer { takeDown(fixture) }
        fixture.host.additionalSafeAreaInsets = extraInsets
        fixture.presenter.start()
        fixture.presenter.viewModel.barBanners = bars
        drainMainQueue(turns: 6)
        fixture.window.layoutIfNeeded()
        drainMainQueue(turns: 6)

        let layer = try XCTUnwrap(fixture.presenter.barLayer)
        let frames = layer.view.interactiveFrames
        XCTAssertEqual(frames.count, 10, "a card and a close control per bar, got \(frames)")
        XCTAssertEqual(sorted(frames).count, sorted(expected).count)
        for (got, want) in zip(sorted(frames), sorted(expected)) {
            assertFrame(got, want, "the presenter's bar frame matches the overlay window's")
        }

        let safeTop = fixture.host.view.safeAreaInsets.top
        let bounds = fixture.host.view.bounds
        let cards = frames.filter { $0.width >= 200 }
        XCTAssertEqual(cards.map(\.minY).min() ?? -1, safeTop, accuracy: 0.5, "the first top bar starts at the safe-area top")
        XCTAssertEqual(cards.map(\.maxY).max() ?? -1, bounds.maxY, accuracy: 0.5, "the last bottom bar runs to the bottom edge")
    }

    /// Touches beside a bar reach the host; touches on its card are the bar's. The host's view is
    /// offset in its window, since the bars report their frames in window coordinates.
    @MainActor
    func testTheBarLayerPassesTouchesBesideABarThroughToTheHost() throws {
        let container = UIViewController()
        let window = makeVisibleWindow(rootViewController: container)
        defer { window.isHidden = true }
        let host = UIViewController()
        container.addChild(host)
        container.view.addSubview(host.view)
        host.view.frame = container.view.bounds.inset(by: UIEdgeInsets(top: 100, left: 30, bottom: 0, right: 0))
        host.didMove(toParent: container)
        let presenter = BannerPresenter(host: host, tracker: BannerTrackerSpy()) { _ in }
        presenter.start()
        defer { presenter.stop() }
        presenter.viewModel.barBanners = [
            bar("narrow", position: "top", keys: ["cardPositionHorizontal": "center", "cardWidth": "200px"])
        ]
        drainMainQueue(turns: 6)
        window.layoutIfNeeded()
        drainMainQueue(turns: 6)

        let layer = try XCTUnwrap(presenter.barLayer).view
        let card = try XCTUnwrap(layer.interactiveFrames.max { $0.width < $1.width })
        XCTAssertEqual(card.minY, 100, accuracy: 0.5, "the bar sits at the host view's top")
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { layer.convert(CGPoint(x: x, y: y), from: nil) }
        XCTAssertNotNil(layer.hitTest(point(card.midX, card.midY), with: nil), "the card takes a touch")
        XCTAssertNil(layer.hitTest(point(card.minX - 20, card.midY), with: nil), "beside the card the touch passes through")
        XCTAssertNil(layer.hitTest(point(card.midX, card.maxY + 100), with: nil), "below the bar the touch passes through")
    }

    // MARK: - Fixtures

    private func bar(_ token: String, position: String, keys: [String: JSONValue] = [:]) -> BannerResponse {
        BannerResponse(
            token: token,
            displayType: "bar",
            displayPosition: position,
            cssStyles: keys,
            design: BannerDisplayViewModelTests.minimalDesign
        )
    }

    private func sorted(_ frames: [CGRect]) -> [CGRect] {
        frames.sorted { ($0.minY, $0.minX, $0.width) < ($1.minY, $1.minX, $1.width) }
    }

    /// The frames the overlay window reports for `bars`, laid out in a window like the fixture's.
    @MainActor
    private func overlayBarFrames(_ bars: [BannerResponse], extraInsets: UIEdgeInsets) -> [CGRect] {
        let viewModel = BannerDisplayViewModel()
        viewModel.barBanners = bars
        let host = BannerOverlayHost.shared
        host.attach(viewModel) { _ in }
        let controller = BannerOverlayHostingController(rootView: BannerOverlayRoot(host: host))
        controller.host = host
        controller.view.backgroundColor = .clear
        controller.additionalSafeAreaInsets = extraInsets
        let window = makeVisibleWindow(rootViewController: controller)
        window.layoutIfNeeded()
        drainMainQueue(turns: 6)
        window.layoutIfNeeded()
        defer {
            host.detach(viewModel)
            window.isHidden = true
        }
        return host.interactiveFrames
    }

    /// A banner with the least a presenter will accept: `shouldDisplay` drops one with no
    /// design, on both paths.
    private func banner(_ token: String, displayType: String) -> BannerResponse {
        BannerResponse(
            token: token,
            displayType: displayType,
            design: BannerDisplayViewModelTests.minimalDesign
        )
    }

    @MainActor
    private func makeFixture() -> BannerFixture {
        let host = UIViewController()
        let tracker = BannerTrackerSpy()
        return BannerFixture(
            host: host,
            window: makeVisibleWindow(rootViewController: host),
            tracker: tracker,
            presenter: BannerPresenter(host: host, tracker: tracker) { _ in }
        )
    }

    /// Leaving a started presenter behind would have it count the next test's banners too:
    /// `BannerDisplayController` is a process-wide singleton.
    @MainActor
    private func takeDown(_ fixture: BannerFixture) {
        fixture.presenter.stop()
        fixture.window.isHidden = true
    }
}
