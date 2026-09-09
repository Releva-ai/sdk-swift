import XCTest
@testable import RelevaSDK

/// `StoryDisplayViewModel` feeds `fullScreenCover(item:)`. A queued story waits for the cover to
/// report that it has disappeared, and is counted exactly when it is handed to the cover.
@MainActor
final class StoryDisplayViewModelTests: XCTestCase {
    private final class StoryTrackerSpy: StoryTracker {
        var impressions: [String] = []
        func storyImpression(_ story: StoryResponse) { impressions.append(story.token) }
    }

    private func story(_ token: String) -> StoryResponse {
        StoryResponse(
            token: token,
            trigger: "immediately",
            slides: [StorySlideResponse(id: "\(token)-s1", durationSeconds: 5)]
        )
    }

    private func makeViewModel() -> (StoryDisplayViewModel, StoryTrackerSpy) {
        let spy = StoryTrackerSpy()
        let viewModel = StoryDisplayViewModel()
        viewModel.start(tracker: spy)
        return (viewModel, spy)
    }

    func testSecondStoryWaitsUntilTheFirstCoverHasDisappeared() {
        let (viewModel, spy) = makeViewModel()
        StoryDisplayController.shared.showStory(story("first"))
        StoryDisplayController.shared.showStory(story("second"))
        drainMainQueue()

        XCTAssertEqual(viewModel.activeStory?.story.token, "first")
        XCTAssertEqual(spy.impressions, ["first"], "the queued story is not counted while another is up")

        viewModel.storyClosed()
        XCTAssertNil(viewModel.activeStory)
        XCTAssertEqual(
            spy.impressions,
            ["first"],
            "closing hands nothing to the cover while it is still animating out"
        )
        XCTAssertTrue(viewModel.coverOnScreen)

        viewModel.coverDidDisappear()
        XCTAssertEqual(viewModel.activeStory?.story.token, "second")
        XCTAssertEqual(spy.impressions, ["first", "second"], "counted when it is actually presented")
    }

    func testStoryArrivingDuringDismissalWaitsToo() {
        let (viewModel, spy) = makeViewModel()
        StoryDisplayController.shared.showStory(story("first"))
        drainMainQueue()
        viewModel.storyClosed()

        StoryDisplayController.shared.showStory(story("late"))
        drainMainQueue()
        XCTAssertNil(viewModel.activeStory, "the cover is still on its way out")
        XCTAssertEqual(spy.impressions, ["first"])

        viewModel.coverDidDisappear()
        XCTAssertEqual(viewModel.activeStory?.story.token, "late")
        XCTAssertEqual(spy.impressions, ["first", "late"])
    }

    func testDisappearWhileAStoryIsStillUpIsIgnored() {
        let (viewModel, spy) = makeViewModel()
        StoryDisplayController.shared.showStory(story("first"))
        StoryDisplayController.shared.showStory(story("second"))
        drainMainQueue()

        // A spurious onDisappear (view re-parented) while "first" is still showing.
        viewModel.coverDidDisappear()
        XCTAssertEqual(viewModel.activeStory?.story.token, "first")
        XCTAssertEqual(spy.impressions, ["first"])
    }

    func testQueueResumesIfTheCoverNeverReportsDisappearing() {
        let (viewModel, spy) = makeViewModel()
        StoryDisplayController.shared.showStory(story("first"))
        StoryDisplayController.shared.showStory(story("second"))
        drainMainQueue()
        viewModel.storyClosed()

        let presented = expectation(description: "second story presented by the fallback")
        DispatchQueue.main.asyncAfter(deadline: .now() + StoryDisplayViewModel.dismissalFallback + 0.5) {
            presented.fulfill()
        }
        wait(for: [presented], timeout: StoryDisplayViewModel.dismissalFallback + 2)
        XCTAssertEqual(viewModel.activeStory?.story.token, "second")
        XCTAssertEqual(spy.impressions, ["first", "second"])
    }
}
