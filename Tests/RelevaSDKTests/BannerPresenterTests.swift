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

    @MainActor
    func testPopupIsPresentedOverAnExistingModalRatherThanFailing() {
        let fixture = makeFixture()
        // The app already has something up before a banner arrives — the case
        // `topMostPresentedViewController` exists for. Dismiss it before the presenter, so it
        // doesn't leak into whatever runs the window next, the way `takeDown` alone would leave
        // it — `takeDown` only stops the presenter and hides the window.
        let existingModal = UIViewController()
        defer {
            existingModal.dismiss(animated: false)
            takeDown(fixture)
        }
        fixture.host.present(existingModal, animated: false)
        waitUntil("the existing modal is presented") { fixture.host.presentedViewController != nil }

        fixture.presenter.start()
        BannerDisplayController.shared.showBanner(banner("popup-1", displayType: "popup"))
        drainMainQueue()

        XCTAssertEqual(fixture.tracker.impressions, ["popup-1"])
        waitUntil("the overlay is presented over the existing modal") {
            existingModal.presentedViewController != nil
        }
        XCTAssertTrue(
            existingModal.presentedViewController is UIHostingController<BannerOverlayView>,
            "the overlay must land on top of the existing modal, not fail silently"
        )
        // And not stacked directly on the host, underneath the existing modal.
        XCTAssertTrue(fixture.host.presentedViewController === existingModal)
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
        waitUntil("the overlay is presented") { fixture.host.presentedViewController != nil }
        // Both banners are slots in one hosted view, so the second must not stack a second
        // modal on top of the first.
        XCTAssertNil(fixture.host.presentedViewController?.presentedViewController)
    }

    @MainActor
    func testBarIsHostedInTheHostsOwnViewRatherThanPresented() {
        let fixture = makeFixture()
        defer { takeDown(fixture) }

        fixture.presenter.start()
        BannerDisplayController.shared.showBanner(banner("bar-1", displayType: "bar"))
        drainMainQueue()

        XCTAssertEqual(fixture.tracker.impressions, ["bar-1"])
        // A modal would black the whole screen out for a strip of chrome, so bars go in a child
        // controller per screen edge instead.
        XCTAssertNil(fixture.host.presentedViewController)
        XCTAssertEqual(fixture.host.children.count, 2)
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
        waitUntil("the overlay is dismissed") { fixture.host.presentedViewController == nil }
    }

    @MainActor
    func testANewPopupAfterDismissalIsPresentedAgain() {
        let fixture = makeFixture()
        defer { takeDown(fixture) }

        let first = banner("popup-1", displayType: "popup")
        fixture.presenter.start()
        BannerDisplayController.shared.showBanner(first)
        drainMainQueue()
        waitUntil("the overlay is presented") { fixture.host.presentedViewController != nil }

        fixture.presenter.viewModel.dismissPopup(first)
        drainMainQueue()
        waitUntil("the overlay is dismissed") { fixture.host.presentedViewController == nil }

        // A normal dismiss-then-repopulate round trip: the overlay was presented normally, so
        // `presentingViewController` finds it and the dismiss completion clears the flag before
        // this arrives either way. `testAPopupAfterTheOverlayWasDismissedExternallyIsStillPresented`
        // below is the one that pins the latch itself, which needs the overlay gone before the
        // presenter tries to dismiss it.
        BannerDisplayController.shared.showBanner(banner("popup-2", displayType: "popup"))
        drainMainQueue()

        XCTAssertEqual(fixture.tracker.impressions, ["popup-1", "popup-2"])
        waitUntil("the overlay is presented again") { fixture.host.presentedViewController != nil }
    }

    @MainActor
    func testAPopupAfterTheOverlayWasDismissedExternallyIsStillPresented() {
        let fixture = makeFixture()
        defer { takeDown(fixture) }

        let first = banner("popup-1", displayType: "popup")
        fixture.presenter.start()
        BannerDisplayController.shared.showBanner(first)
        drainMainQueue()
        waitUntil("the overlay is presented") { fixture.host.presentedViewController != nil }

        // Behind the presenter's back — something else dismissed the chain the overlay was in,
        // so `syncOverlay` finds a controller with no `presentingViewController` when it goes to
        // dismiss it.
        fixture.host.dismiss(animated: false)
        waitUntil("the overlay is gone") { fixture.host.presentedViewController == nil }

        // Pre-fix this set `isDismissingOverlay = true` and skipped the completion that clears
        // it, wedging the presenter for the rest of its life.
        fixture.presenter.viewModel.dismissPopup(first)
        drainMainQueue()

        BannerDisplayController.shared.showBanner(banner("popup-2", displayType: "popup"))
        drainMainQueue()

        XCTAssertEqual(fixture.tracker.impressions, ["popup-1", "popup-2"])
        waitUntil("the next popup still reaches the screen") {
            fixture.host.presentedViewController != nil
        }
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
        waitUntil("the overlay is dismissed") { fixture.host.presentedViewController == nil }
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

        fixture.presenter.stop()
        waitUntil("the overlay is dismissed") { fixture.host.presentedViewController == nil }
        XCTAssertTrue(fixture.host.children.isEmpty, "the bar slots must come off with the presenter")

        BannerDisplayController.shared.showBanner(banner("popup-2", displayType: "popup"))
        drainMainQueue()

        XCTAssertEqual(
            fixture.tracker.impressions,
            ["popup-1"],
            "a stopped presenter must not count banners"
        )
        XCTAssertNil(fixture.host.presentedViewController)
    }

    // MARK: - Fixtures

    /// A banner with the least a presenter will accept: `shouldDisplay` drops one with no
    /// design, on both paths.
    private func banner(_ token: String, displayType: String) -> BannerResponse {
        BannerResponse(
            token: token,
            displayType: displayType,
            design: ["body": ["rows": []]]
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
