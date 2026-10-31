import SwiftUI
import UIKit
import XCTest
@testable import RelevaSDK

/// A presenter over a host in a visible window, counting through a spy.
private struct StoryFixture {
    let host: UIViewController
    let window: UIWindow
    let tracker: StoryTrackerSpy
    let presenter: StoryPresenter
}

/// `StoryPresenter` draws nothing of its own and tracks nothing of its own: it hosts the same
/// `StoryViewerView` the modifier shows and queues through the same `StoryDisplayViewModel`. So
/// these tests cover what the presenter adds — what it puts on screen for a story, that the
/// shared counting still fires, and that a stopped presenter takes nothing more — driven through
/// `StoryDisplayController.shared`, the singleton `StoryManagerService` publishes to in
/// production.
///
/// As in `BannerPresenterTests`, the assertions are on what the presenter did, never on UIKit
/// having *finished* a transition — see `PresentationTestSupport.makeVisibleWindow`.
final class StoryPresenterTests: XCTestCase {
    @MainActor
    func testAStoryIsPresentedFullScreenAndCounted() {
        let fixture = makeFixture()
        defer { takeDown(fixture) }

        fixture.presenter.start()
        StoryDisplayController.shared.showStory(story("story-1"))
        drainMainQueue()

        XCTAssertEqual(fixture.tracker.impressions, ["story-1"])
        waitUntil("the viewer is presented") { fixture.host.presentedViewController != nil }
        XCTAssertTrue(
            fixture.host.presentedViewController is UIHostingController<StoryViewerView>,
            "expected the hosted viewer, got \(String(describing: fixture.host.presentedViewController))"
        )
        XCTAssertEqual(fixture.host.presentedViewController?.modalPresentationStyle, .overFullScreen)
    }

    /// Stories play one at a time on both paths: the queued one is not shown, and not counted,
    /// until the viewer that is up has gone.
    @MainActor
    func testASecondStoryWaitsForTheOneOnScreen() {
        let fixture = makeFixture()
        defer { takeDown(fixture) }

        fixture.presenter.start()
        StoryDisplayController.shared.showStory(story("first"))
        StoryDisplayController.shared.showStory(story("second"))
        drainMainQueue()

        waitUntil("the viewer is presented") { fixture.host.presentedViewController != nil }
        let viewer = fixture.host.presentedViewController
        XCTAssertEqual(fixture.tracker.impressions, ["first"])
        XCTAssertTrue(fixture.host.presentedViewController === viewer)
        XCTAssertNil(viewer?.presentedViewController, "stacking the second story on the first would bury it")
    }

    @MainActor
    func testStopTakesTheViewerDownAndIgnoresLaterStories() {
        let fixture = makeFixture()
        defer { takeDown(fixture) }

        fixture.presenter.start()
        StoryDisplayController.shared.showStory(story("first"))
        drainMainQueue()
        waitUntil("the viewer is presented") { fixture.host.presentedViewController != nil }

        let viewer = fixture.presenter.viewerController
        fixture.presenter.stop()
        // `stop()` either drops `viewerController` (the viewer was already gone, or the dismissal
        // took effect at once) or keeps it until UIKit confirms the dismissal, so that a viewer
        // UIKit declined to dismiss is not orphaned beyond reach — see `StoryPresenter.stop()`.
        // Which branch runs depends on a transition this test host never finishes; what holds on
        // both is that nothing *else* took the property over.
        XCTAssertTrue(
            fixture.presenter.viewerController == nil || fixture.presenter.viewerController === viewer,
            "a stopped presenter must not leave a different viewer behind"
        )

        StoryDisplayController.shared.showStory(story("second"))
        drainMainQueue()

        XCTAssertEqual(fixture.tracker.impressions, ["first"], "a stopped presenter counts nothing")
        XCTAssertTrue(
            fixture.presenter.viewerController == nil || fixture.presenter.viewerController === viewer,
            "and shows nothing"
        )
    }

    /// A story closed just before the host goes off screen — a link tap, which closes the viewer
    /// and then navigates away — must not count the next queued story while nothing can show it.
    /// Both ways the queue moves on, the dismiss completion and the view model's fallback, are
    /// held back by `stop()`; the fallback is the one this test host can wait for.
    @MainActor
    func testAStoryClosedBeforeStopDoesNotCountTheNextOneWhileStopped() async {
        let fixture = makeFixture()
        defer { takeDown(fixture) }

        fixture.presenter.start()
        StoryDisplayController.shared.showStory(story("first"))
        StoryDisplayController.shared.showStory(story("second"))
        drainMainQueue()
        waitUntil("the viewer is presented") { fixture.host.presentedViewController != nil }

        fixture.presenter.viewModel.storyClosed()
        fixture.presenter.stop()
        try? await Task.sleep(nanoseconds: UInt64((StoryDisplayViewModel.dismissalFallback + 0.5) * 1_000_000_000))

        XCTAssertEqual(fixture.tracker.impressions, ["first"], "the queued story waits for the host to come back")
    }

    /// UIKit declines a present from a controller that is not in a window, and only logs. The
    /// view model has already handed the story over, so nothing but the presenter's own retry
    /// can put it up once the host is on screen.
    @MainActor
    func testAPresentUIKitDeclinedIsRetried() {
        let window = makeVisibleWindow(rootViewController: UIViewController())
        let host = UIViewController()
        let tracker = StoryTrackerSpy()
        let presenter = StoryPresenter(host: host, client: offlineClient(), tracker: tracker) { _ in }
        defer {
            presenter.stop()
            window.isHidden = true
        }

        presenter.start()
        StoryDisplayController.shared.showStory(story("first"))
        drainMainQueue()
        XCTAssertNil(presenter.viewerController, "a declined present is not treated as on screen")

        window.rootViewController = host
        waitUntil("the retry presents the viewer") { host.presentedViewController != nil }
        XCTAssertEqual(tracker.impressions, ["first"], "retrying does not count the story again")
    }

    // MARK: - Fixtures

    private func story(_ token: String) -> StoryResponse {
        StoryResponse(
            token: token,
            trigger: "immediately",
            slides: [StorySlideResponse(id: "\(token)-s1", durationSeconds: 5)]
        )
    }

    @MainActor
    private func makeFixture() -> StoryFixture {
        let host = UIViewController()
        let tracker = StoryTrackerSpy()
        return StoryFixture(
            host: host,
            window: makeVisibleWindow(rootViewController: host),
            tracker: tracker,
            presenter: StoryPresenter(host: host, client: offlineClient(), tracker: tracker) { _ in }
        )
    }

    /// Leaving a started presenter behind would have it count the next test's stories too:
    /// `StoryDisplayController` is a process-wide singleton.
    @MainActor
    private func takeDown(_ fixture: StoryFixture) {
        fixture.presenter.stop()
        fixture.window.isHidden = true
    }
}
