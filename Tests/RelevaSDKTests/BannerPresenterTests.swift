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
        XCTAssertNil(
            fixture.presenter.overlayController,
            "the presenter must let go of the overlay it asked UIKit to take down"
        )
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
        XCTAssertNil(
            fixture.presenter.overlayController,
            "the presenter must let go of the overlay it asked UIKit to take down"
        )
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
        XCTAssertNil(
            fixture.presenter.overlayController,
            "stop() must let go of the overlay it asked UIKit to take down"
        )
        XCTAssertTrue(fixture.host.children.isEmpty, "the bar slots must come off with the presenter")

        BannerDisplayController.shared.showBanner(banner("popup-2", displayType: "popup"))
        drainMainQueue()

        XCTAssertEqual(
            fixture.tracker.impressions,
            ["popup-1"],
            "a stopped presenter must not count banners"
        )
        XCTAssertNil(
            fixture.presenter.overlayController,
            "a stopped presenter must not put anything back on screen"
        )
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
