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

/// Rows of plain cells, in sections whose headers pin in a plain table when `headers` is set.
private final class TableRows: NSObject, UITableViewDataSource {
    var sections: Int
    let rowsPerSection: Int
    let headers: Bool

    init(sections: Int, rowsPerSection: Int, headers: Bool) {
        self.sections = sections
        self.rowsPerSection = rowsPerSection
        self.headers = headers
    }

    func numberOfSections(in tableView: UITableView) -> Int { sections }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rowsPerSection }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = "row \(indexPath.row)"
        return cell
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        headers ? "Section \(section)" : nil
    }
}

/// Plain cells, enough to scroll.
private final class CollectionItems: NSObject, UICollectionViewDataSource {
    private static let reuseIdentifier = "item"

    init(registeringOn collectionView: UICollectionView) {
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: Self.reuseIdentifier)
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { 200 }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: Self.reuseIdentifier, for: indexPath)
        cell.backgroundColor = .systemGray
        return cell
    }
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
        XCTAssertEqual(fixture.host.presentedViewController?.modalTransitionStyle, .crossDissolve, "a popup fades in and out")
    }

    /// As sdk-react-native's `Modal animationType="slide"`: the overlay holding a flyout slides up
    /// from the bottom and back down.
    @MainActor
    func testAFlyoutsOverlaySlidesUpAndDown() {
        let fixture = makeFixture()
        defer { takeDown(fixture) }

        fixture.presenter.start()
        BannerDisplayController.shared.showBanner(banner("flyout-1", displayType: "flyout"))
        drainMainQueue()

        waitUntil("the overlay is presented") { fixture.host.presentedViewController != nil }
        XCTAssertEqual(fixture.host.presentedViewController?.modalPresentationStyle, .overFullScreen)
        XCTAssertEqual(fixture.host.presentedViewController?.modalTransitionStyle, .coverVertical)
    }

    /// As sdk-react-native's Modal, which sets its transition style only when it presents: a swap
    /// keeps the overlay up, and it leaves as it came in.
    @MainActor
    func testAnOverlayOpenedWithAPopupKeepsItsFadeThroughASwap() {
        let fixture = makeFixture()
        defer { takeDown(fixture) }

        fixture.presenter.start()
        BannerDisplayController.shared.showBanner(banner("popup-1", displayType: "popup"))
        drainMainQueue()
        waitUntil("the overlay is presented") { fixture.host.presentedViewController != nil }
        let overlay = fixture.host.presentedViewController

        BannerDisplayController.shared.showBanner(banner("flyout-1", displayType: "flyout"))
        drainMainQueue()
        XCTAssertTrue(fixture.host.presentedViewController === overlay)
        XCTAssertEqual(overlay?.modalTransitionStyle, .crossDissolve, "the overlay still leaves fading")
    }

    @MainActor
    func testAnOverlayOpenedWithAFlyoutKeepsItsSlideThroughASwap() {
        let fixture = makeFixture()
        defer { takeDown(fixture) }

        fixture.presenter.start()
        BannerDisplayController.shared.showBanner(banner("flyout-1", displayType: "flyout"))
        drainMainQueue()
        waitUntil("the overlay is presented") { fixture.host.presentedViewController != nil }
        let overlay = fixture.host.presentedViewController

        BannerDisplayController.shared.showBanner(banner("popup-1", displayType: "popup"))
        drainMainQueue()
        XCTAssertTrue(fixture.host.presentedViewController === overlay)
        XCTAssertEqual(overlay?.modalTransitionStyle, .coverVertical, "the overlay still leaves sliding down")
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

    /// Over a `UITableViewController` in a navigation controller the host's view is the table, whose
    /// own edges are its content's. The bars sit on its visible frame: the top bar at the safe-area
    /// top below the navigation bar, the bottom bar at the bottom edge, and neither moves when the
    /// table scrolls.
    @MainActor
    func testBarsOverATableViewHostStayOnScreenWhenItScrolls() throws {
        let host = UITableViewController(style: .plain)
        let rows = TableRows(sections: 1, rowsPerSection: 200, headers: false)
        host.tableView.dataSource = rows
        let window = makeVisibleWindow(rootViewController: UINavigationController(rootViewController: host))
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        let presenter = BannerPresenter(host: host, tracker: BannerTrackerSpy()) { _ in }
        presenter.start()
        defer { presenter.stop() }
        presenter.viewModel.barBanners = [bar("top", position: "top"), bar("bottom", position: "bottom")]
        func settle() {
            drainMainQueue(turns: 6)
            window.layoutIfNeeded()
            drainMainQueue(turns: 6)
            window.layoutIfNeeded()
        }
        settle()

        let table = try XCTUnwrap(host.tableView)
        let layer = try XCTUnwrap(presenter.barLayer).view
        let visible = table.convert(table.bounds, to: nil)
        func cards() -> [CGRect] {
            layer.interactiveFrames.filter { $0.width > 100 }.sorted { $0.minY < $1.minY }
        }
        XCTAssertGreaterThan(table.safeAreaInsets.top, 0, "the navigation bar is over the table")
        let before = cards()
        XCTAssertEqual(before.count, 2, "a card per bar, got \(layer.interactiveFrames)")
        XCTAssertEqual(before.first?.minY ?? -1, visible.minY + table.safeAreaInsets.top, accuracy: 0.5, "the top bar starts below the navigation bar")
        XCTAssertEqual(before.last?.maxY ?? -1, visible.maxY, accuracy: 0.5, "the bottom bar runs to the bottom edge")
        XCTAssertEqual(before.first?.width ?? -1, visible.width, accuracy: 0.5, "the bars span the table's width")

        table.contentOffset = CGPoint(x: 0, y: 600)
        settle()
        XCTAssertEqual(table.contentOffset.y, 600, "the table scrolled")
        XCTAssertEqual(layer.convert(layer.bounds, to: nil), visible, "the layer stays on the visible frame")
        XCTAssertEqual(cards(), before, "the bars do not scroll with the rows")
        let layerIndex = try XCTUnwrap(table.subviews.firstIndex(of: layer))
        let lastRow = try XCTUnwrap(table.subviews.lastIndex { $0 is UITableViewCell })
        XCTAssertGreaterThan(layerIndex, lastRow, "the bars stay above the rows")

        // A safe area that changes with the frame unchanged, as when a large title collapses.
        host.additionalSafeAreaInsets.top = 40
        settle()
        XCTAssertEqual(cards().first?.minY ?? -1, (before.first?.minY ?? 0) + 40, accuracy: 0.5, "the top bar follows the safe-area top")
        XCTAssertEqual(cards().last?.maxY ?? -1, visible.maxY, accuracy: 0.5, "the bottom bar stays at the bottom edge")
    }

    /// A table passes its subviews the safe-area edges it does not take into its content inset:
    /// none of the top with `.automatic`, all of it with `.never`, and the sides with either. The
    /// bars over it count the safe area once, so they are laid out exactly as over a plain view
    /// controller in the same place, before and after the table scrolls.
    @MainActor
    func testBarsOverATableViewHostCountTheSafeAreaOnce() throws {
        let bars = [bar("top", position: "top"), bar("bottom", position: "bottom")]
        let portrait = UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 0)
        let landscape = UIEdgeInsets(top: 0, left: 59, bottom: 21, right: 59)
        for extraInsets in [portrait, landscape] {
            let expected = sorted(plainHostBarFrames(bars, extraInsets: extraInsets))
            XCTAssertEqual(expected.count, 4, "a card and a close control per bar over the plain host, got \(expected)")
            for behaviour in [UIScrollView.ContentInsetAdjustmentBehavior.automatic, .never] {
                let context = "\(extraInsets), contentInsetAdjustmentBehavior \(behaviour.rawValue)"
                let host = UITableViewController(style: .plain)
                let rows = TableRows(sections: 1, rowsPerSection: 200, headers: false)
                host.tableView.dataSource = rows
                host.tableView.contentInsetAdjustmentBehavior = behaviour
                let window = showInNavigationController(host, extraInsets: extraInsets)
                defer { window.isHidden = true }
                let presenter = BannerPresenter(host: host, tracker: BannerTrackerSpy()) { _ in }
                presenter.start()
                defer { presenter.stop() }
                presenter.viewModel.barBanners = bars
                settleLayout(window)

                let table = try XCTUnwrap(host.tableView)
                let layer = try XCTUnwrap(presenter.barLayer).view
                let visible = table.convert(table.bounds, to: nil)
                XCTAssertGreaterThan(table.safeAreaInsets.top, 0, "the navigation bar is over the table")
                for scrolled in [false, true] {
                    if scrolled {
                        table.contentOffset.y += 600
                        settleLayout(window)
                    }
                    let frames = sorted(layer.interactiveFrames)
                    XCTAssertEqual(frames.count, expected.count, "\(context), scrolled \(scrolled): got \(frames)")
                    for (got, want) in zip(frames, expected) {
                        assertFrame(got, want, "\(context), scrolled \(scrolled): the bar frame matches a plain host's")
                    }
                    let cards = frames.filter { $0.width > 100 }
                    XCTAssertEqual(cards.map(\.minY).min() ?? -1, visible.minY + table.safeAreaInsets.top, accuracy: 0.5, "\(context), scrolled \(scrolled): the top bar starts at the safe-area top")
                    XCTAssertEqual(cards.map(\.maxY).max() ?? -1, visible.maxY, accuracy: 0.5, "\(context), scrolled \(scrolled): the bottom bar runs to the window bottom")
                }
            }
        }
    }

    /// A plain table adds its section headers above the bar layer as it scrolls, and pins one at
    /// the top under the top bar. The layer stays above every header, so the bars are drawn over
    /// them and take the touches on their cards; a touch on a row below still reaches the table.
    @MainActor
    func testBarsOverATableViewHostStayAboveItsPinnedSectionHeaders() throws {
        let host = UITableViewController(style: .plain)
        let rows = TableRows(sections: 60, rowsPerSection: 4, headers: true)
        host.tableView.dataSource = rows
        let window = showInNavigationController(host, extraInsets: .zero)
        defer { window.isHidden = true }
        let presenter = BannerPresenter(host: host, tracker: BannerTrackerSpy()) { _ in }
        presenter.start()
        defer { presenter.stop() }
        presenter.viewModel.barBanners = [bar("top", position: "top"), bar("bottom", position: "bottom")]
        settleLayout(window)

        let table = try XCTUnwrap(host.tableView)
        let layer = try XCTUnwrap(presenter.barLayer).view
        for step in 1...3 {
            table.contentOffset.y += 600
            settleLayout(window)

            let headers = table.subviews.filter { $0 is UITableViewHeaderFooterView }
            let topCard = try XCTUnwrap(layer.interactiveFrames.filter { $0.width > 100 }.min { $0.minY < $1.minY })
            XCTAssertTrue(
                headers.contains { $0.convert($0.bounds, to: nil).intersects(topCard) },
                "step \(step): a pinned header is under the top bar"
            )
            let layerIndex = try XCTUnwrap(table.subviews.firstIndex(of: layer))
            let lastHeader = try XCTUnwrap(table.subviews.lastIndex { $0 is UITableViewHeaderFooterView })
            XCTAssertGreaterThan(layerIndex, lastHeader, "step \(step): the bars are drawn above the headers")

            let onBar = window.hitTest(CGPoint(x: topCard.midX, y: topCard.midY), with: nil)
            XCTAssertTrue(onBar?.isDescendant(of: layer) ?? false, "step \(step): the top bar takes a touch on its card, got \(String(describing: onBar))")
            let onRow = window.hitTest(CGPoint(x: topCard.midX, y: window.bounds.midY), with: nil)
            XCTAssertFalse(onRow?.isDescendant(of: layer) ?? true, "step \(step): a touch on a row passes through")
            XCTAssertTrue(onRow?.isDescendant(of: table) ?? false, "step \(step): the row takes it, got \(String(describing: onRow))")
        }
    }

    /// A table moves its own content offset when sections are inserted or deleted above the rows on
    /// screen, and when it reloads, scrolls to a row, or its insets or size change. The layer follows
    /// at once and the bars stay on the table's visible frame, above its section headers, with the
    /// top bar taking the touches on its card.
    @MainActor
    func testBarsOverATableViewHostFollowTheOffsetsTheTableMovesItself() throws {
        struct Move {
            let name: String
            /// Whether the table ends up away from the offset `prepare` scrolled it to.
            let movesOffset: Bool
            var prepare: (UITableView) -> Void = { $0.contentOffset.y = 636 }
            let run: (UITableViewController, TableRows) -> Void
        }
        let moves = [
            Move(name: "a section inserted above, without animation", movesOffset: true) { host, rows in
                rows.sections += 1
                host.tableView.insertSections([0], with: .none)
            },
            Move(name: "a section deleted above, without animation", movesOffset: true) { host, rows in
                rows.sections -= 1
                host.tableView.deleteSections([0], with: .none)
            },
            Move(name: "a section inserted above, animated", movesOffset: true) { host, rows in
                rows.sections += 1
                host.tableView.insertSections([0], with: .automatic)
            },
            Move(name: "a section deleted above, animated", movesOffset: true) { host, rows in
                rows.sections -= 1
                host.tableView.deleteSections([0], with: .fade)
            },
            Move(name: "a section inserted above in begin/endUpdates", movesOffset: true) { host, rows in
                host.tableView.beginUpdates()
                rows.sections += 1
                host.tableView.insertSections([0], with: .automatic)
                host.tableView.endUpdates()
            },
            Move(name: "a reload with the same rows", movesOffset: false) { host, _ in
                host.tableView.reloadData()
            },
            Move(name: "a reload with too few rows to stay scrolled", movesOffset: true) { host, rows in
                rows.sections = 3
                host.tableView.reloadData()
            },
            Move(name: "a scroll to a row, without animation", movesOffset: true) { host, _ in
                host.tableView.scrollToRow(at: IndexPath(row: 0, section: 20), at: .top, animated: false)
            },
            Move(name: "a larger top content inset", movesOffset: false) { host, _ in
                host.tableView.contentInset.top += 100
            },
            Move(
                name: "a smaller bottom content inset at the end of the rows",
                movesOffset: true,
                prepare: { table in
                    table.contentInset.bottom = 300
                    table.contentOffset.y = table.contentSize.height + table.adjustedContentInset.bottom - table.bounds.height
                },
                run: { host, _ in host.tableView.contentInset.bottom = 0 }
            ),
            Move(name: "the navigation bar hidden", movesOffset: true) { host, _ in
                host.navigationController?.setNavigationBarHidden(true, animated: false)
            },
            Move(name: "the window turned to landscape", movesOffset: false) { host, _ in
                guard let window = host.view.window else { return XCTFail("the table is in a window") }
                window.frame = CGRect(x: 0, y: 0, width: window.bounds.height, height: window.bounds.width)
            }
        ]
        for move in moves {
            let host = UITableViewController(style: .plain)
            let rows = TableRows(sections: 30, rowsPerSection: 5, headers: true)
            host.tableView.dataSource = rows
            let window = showInNavigationController(host, extraInsets: .zero)
            defer { window.isHidden = true }
            let presenter = BannerPresenter(host: host, tracker: BannerTrackerSpy()) { _ in }
            presenter.start()
            defer { presenter.stop() }
            presenter.viewModel.barBanners = [bar("top", position: "top"), bar("bottom", position: "bottom")]
            settleLayout(window)
            let table = try XCTUnwrap(host.tableView)
            let layer = try XCTUnwrap(presenter.barLayer).view
            move.prepare(table)
            settleLayout(window)
            let offset = table.contentOffset.y

            move.run(host, rows)
            XCTAssertEqual(layer.frame, table.bounds, "\(move.name): the layer follows the table's bounds at once")
            settleLayout(window)
            if move.movesOffset {
                XCTAssertNotEqual(table.contentOffset.y, offset, "\(move.name): the table moved its offset")
            }
            assertBarsOnTheVisibleFrame(of: table, layer: layer, in: window, move.name)
        }
    }

    /// Once the table and the bars are still, the bar layer is not laid out again and does not move
    /// the table either, including after the table moved its own offset.
    @MainActor
    func testTheBarLayerOverATableViewHostIsNotLaidOutAgainWhileNothingChanges() throws {
        let host = UITableViewController(style: .plain)
        let rows = TableRows(sections: 30, rowsPerSection: 5, headers: true)
        host.tableView.dataSource = rows
        let window = showInNavigationController(host, extraInsets: .zero)
        defer { window.isHidden = true }
        let presenter = BannerPresenter(host: host, tracker: BannerTrackerSpy()) { _ in }
        presenter.start()
        defer { presenter.stop() }
        presenter.viewModel.barBanners = [bar("top", position: "top"), bar("bottom", position: "bottom")]
        settleLayout(window)
        let table = try XCTUnwrap(host.tableView)
        let layer = try XCTUnwrap(presenter.barLayer).view
        table.contentOffset.y = 636
        rows.sections += 1
        table.insertSections([0], with: .none)
        settleLayout(window)
        assertBarsOnTheVisibleFrame(of: table, layer: layer, in: window, "after the insert")

        final class Counts { var layerPasses = 0; var tableChanges = 0 }
        let counts = Counts()
        let measure = layer.onSafeAreaChange
        layer.onSafeAreaChange = { insets in
            counts.layerPasses += 1
            measure?(insets)
        }
        layer.setNeedsLayout()
        window.layoutIfNeeded()
        XCTAssertEqual(counts.layerPasses, 1, "a layout pass of the layer is counted")
        counts.layerPasses = 0
        let observations = [
            table.observe(\.bounds) { _, _ in counts.tableChanges += 1 },
            table.observe(\.contentOffset) { _, _ in counts.tableChanges += 1 },
            table.observe(\.contentSize) { _, _ in counts.tableChanges += 1 }
        ]
        let end = Date().addingTimeInterval(1)
        while Date() < end {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            window.layoutIfNeeded()
        }
        observations.forEach { $0.invalidate() }
        XCTAssertEqual(counts.layerPasses, 0, "no layout passes of the layer while idle")
        XCTAssertEqual(counts.tableChanges, 0, "the table's bounds, offset and content size are not set again while idle")
    }

    /// A collection view controller in a navigation controller: the bars sit as over a plain view
    /// controller in the same place, and stay there when the collection view scrolls.
    @MainActor
    func testBarsOverACollectionViewHostStayOnScreenWhenItScrolls() throws {
        let bars = [bar("top", position: "top"), bar("bottom", position: "bottom")]
        let extraInsets = UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 0)
        let expected = sorted(plainHostBarFrames(bars, extraInsets: extraInsets))
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 100, height: 100)
        let host = UICollectionViewController(collectionViewLayout: layout)
        let items = CollectionItems(registeringOn: host.collectionView)
        host.collectionView.dataSource = items
        let window = showInNavigationController(host, extraInsets: extraInsets)
        defer { window.isHidden = true }
        let presenter = BannerPresenter(host: host, tracker: BannerTrackerSpy()) { _ in }
        presenter.start()
        defer { presenter.stop() }
        presenter.viewModel.barBanners = bars
        settleLayout(window)

        let collectionView = try XCTUnwrap(host.collectionView)
        let layer = try XCTUnwrap(presenter.barLayer).view
        let before = sorted(layer.interactiveFrames)
        XCTAssertEqual(before.count, expected.count, "got \(before)")
        for (got, want) in zip(before, expected) {
            assertFrame(got, want, "the bar frame matches a plain host's")
        }

        collectionView.contentOffset.y += 600
        settleLayout(window)
        XCTAssertGreaterThan(collectionView.contentOffset.y, 400, "the collection view scrolled")
        XCTAssertEqual(sorted(layer.interactiveFrames), before, "the bars do not scroll with the items")
        let topCard = try XCTUnwrap(before.first { $0.width > 100 })
        let onBar = window.hitTest(CGPoint(x: topCard.midX, y: topCard.midY), with: nil)
        XCTAssertTrue(onBar?.isDescendant(of: layer) ?? false, "the top bar takes a touch on its card, got \(String(describing: onBar))")
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

    /// A closed flyout stays drawn, taking no touches, while the overlay slides away with it; a
    /// popup that replaces it takes its place at once.
    @MainActor
    func testTheOverlayKeepsDrawingAClosedFlyoutUntilItIsGone() throws {
        final class Frames { var value: [CGRect] = [] }
        let frames = Frames()
        let viewModel = BannerDisplayViewModel()
        let flyout = BannerResponse(token: "fly-1", displayType: "flyout", displayPosition: "right", design: BannerDisplayViewModelTests.minimalDesign)
        viewModel.flyoutBanner = flyout
        let controller = UIHostingController(
            rootView: BannerOverlayView(viewModel: viewModel) { _ in }
                .onPreferenceChange(BannerFramesKey.self) { frames.value = $0 }
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        func settle() {
            window.layoutIfNeeded()
            drainMainQueue(turns: 6)
            window.layoutIfNeeded()
        }
        settle()
        let card = try XCTUnwrap(frames.value.first, "the flyout reported no frame")

        viewModel.dismissFlyout(flyout)
        settle()
        XCTAssertEqual(frames.value.first ?? .zero, card, "the closed flyout is still drawn")

        viewModel.popupBanner = BannerResponse(token: "popup-1", displayType: "popup", design: BannerDisplayViewModelTests.minimalDesign)
        settle()
        XCTAssertEqual(frames.value.count, 1, "only the popup's card, got \(frames.value)")
        XCTAssertNotEqual(frames.value.first ?? .zero, card, "the popup replaced the flyout")
    }

    /// A closed popup stays drawn, taking no touches, while the overlay fades away with it; a
    /// flyout that replaces it takes its place at once.
    @MainActor
    func testTheOverlayKeepsDrawingAClosedPopupUntilItIsGone() throws {
        final class Frames { var value: [CGRect] = [] }
        let frames = Frames()
        let viewModel = BannerDisplayViewModel()
        let popup = BannerResponse(token: "popup-1", displayType: "popup", design: BannerDisplayViewModelTests.minimalDesign)
        viewModel.popupBanner = popup
        let controller = UIHostingController(
            rootView: BannerOverlayView(viewModel: viewModel) { _ in }
                .onPreferenceChange(BannerFramesKey.self) { frames.value = $0 }
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        func settle() {
            window.layoutIfNeeded()
            drainMainQueue(turns: 6)
            window.layoutIfNeeded()
        }
        settle()
        let card = try XCTUnwrap(frames.value.first, "the popup reported no frame")

        viewModel.dismissPopup(popup)
        settle()
        XCTAssertEqual(frames.value, [card], "the closed popup is still drawn")

        viewModel.flyoutBanner = BannerResponse(token: "fly-1", displayType: "flyout", displayPosition: "right", design: BannerDisplayViewModelTests.minimalDesign)
        settle()
        XCTAssertEqual(frames.value.count, 1, "only the flyout's card, got \(frames.value)")
        XCTAssertNotEqual(frames.value.first ?? .zero, card, "the flyout replaced the popup")
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

    /// `host` as the root of a navigation controller in a visible window, with `extraInsets` added
    /// to the navigation controller's safe area.
    @MainActor
    private func showInNavigationController(_ host: UIViewController, extraInsets: UIEdgeInsets) -> UIWindow {
        let navigation = UINavigationController(rootViewController: host)
        navigation.additionalSafeAreaInsets = extraInsets
        let window = makeVisibleWindow(rootViewController: navigation)
        window.layoutIfNeeded()
        return window
    }

    @MainActor
    private func settleLayout(_ window: UIWindow) {
        drainMainQueue(turns: 6)
        window.layoutIfNeeded()
        drainMainQueue(turns: 6)
        window.layoutIfNeeded()
    }

    /// The layer covers the table's visible frame, the top bar starts at the safe-area top and the
    /// bottom bar runs to the bottom edge, the layer is drawn above every row and header, and only
    /// the bars take touches.
    @MainActor
    private func assertBarsOnTheVisibleFrame(
        of table: UITableView,
        layer: BannerBarPassThroughView,
        in window: UIWindow,
        _ context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let visible = table.convert(table.bounds, to: nil)
        XCTAssertEqual(layer.convert(layer.bounds, to: nil), visible, "\(context): the layer covers the visible frame", file: file, line: line)
        let cards = layer.interactiveFrames.filter { $0.width > 100 }.sorted { $0.minY < $1.minY }
        guard cards.count == 2, let top = cards.first, let bottom = cards.last else {
            return XCTFail("\(context): a card per bar, got \(layer.interactiveFrames)", file: file, line: line)
        }
        XCTAssertEqual(top.minY, visible.minY + table.safeAreaInsets.top, accuracy: 0.5, "\(context): the top bar starts at the safe-area top", file: file, line: line)
        XCTAssertEqual(bottom.maxY, visible.maxY, accuracy: 0.5, "\(context): the bottom bar runs to the bottom edge", file: file, line: line)
        XCTAssertTrue(table.subviews.last === layer, "\(context): the bars are drawn above the rows and headers", file: file, line: line)
        let onBar = window.hitTest(CGPoint(x: top.midX, y: top.midY), with: nil)
        XCTAssertTrue(onBar?.isDescendant(of: layer) ?? false, "\(context): the top bar takes a touch on its card, got \(String(describing: onBar))", file: file, line: line)
        let onRow = window.hitTest(CGPoint(x: top.midX, y: visible.midY), with: nil)
        XCTAssertFalse(onRow?.isDescendant(of: layer) ?? true, "\(context): a touch between the bars passes through", file: file, line: line)
        XCTAssertTrue(onRow?.isDescendant(of: table) ?? false, "\(context): the table takes it, got \(String(describing: onRow))", file: file, line: line)
    }

    /// The frames a presenter's bars claim over a plain view controller shown as
    /// `showInNavigationController` shows it.
    @MainActor
    private func plainHostBarFrames(_ bars: [BannerResponse], extraInsets: UIEdgeInsets) -> [CGRect] {
        let host = UIViewController()
        let window = showInNavigationController(host, extraInsets: extraInsets)
        let presenter = BannerPresenter(host: host, tracker: BannerTrackerSpy()) { _ in }
        presenter.start()
        presenter.viewModel.barBanners = bars
        settleLayout(window)
        defer {
            presenter.stop()
            window.isHidden = true
        }
        return presenter.barLayer?.view.interactiveFrames ?? []
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
