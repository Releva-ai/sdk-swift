import XCTest
import Combine
@testable import RelevaSDK

/// Note on the "must not publish" assertions below: `StoryManagerService.initialize` runs
/// its whole trigger setup inline when called on the main thread (see `setupTriggers`), and
/// XCTest calls these test methods on the main thread. Any story it was going to publish
/// immediately has therefore already been published by the time `initialize` returns, so
/// these tests assert on what was received rather than waiting out an inverted expectation:
/// instant, and it cannot be weakened by a slow runner.
final class StoryManagerServiceTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func testInitializeWithImmediateTrigger() {
        let manager = StoryManagerService()
        let story = StoryResponse(
            token: "story-1",
            trigger: "immediately",
            slides: [StorySlideResponse(id: "s1", durationSeconds: 5)]
        )

        let expectation = expectation(description: "Story published")
        StoryDisplayController.shared.storyPublisher
            .sink { received in
                XCTAssertEqual(received.token, "story-1")
                expectation.fulfill()
            }
            .store(in: &cancellables)

        manager.initialize(newStories: [story])

        waitForExpectations(timeout: 2)
    }

    func testInitializeWithEmptySlides() {
        let manager = StoryManagerService()
        let story = StoryResponse(
            token: "story-1",
            trigger: "immediately",
            slides: []
        )

        var receivedTokens: [String] = []
        StoryDisplayController.shared.storyPublisher
            .sink { receivedTokens.append($0.token) }
            .store(in: &cancellables)

        manager.initialize(newStories: [story])

        XCTAssertTrue(receivedTokens.isEmpty, "a story with no slides must not be published")
    }

    func testDeduplication() {
        let manager = StoryManagerService()
        let story = StoryResponse(
            token: "story-dup",
            trigger: "immediately",
            slides: [StorySlideResponse(id: "s1", durationSeconds: 5)]
        )

        var receivedTokens: [String] = []
        StoryDisplayController.shared.storyPublisher
            .sink { receivedTokens.append($0.token) }
            .store(in: &cancellables)

        manager.initialize(newStories: [story, story])

        // Both copies have been through `triggerStory`'s `displayedStories` check by now,
        // so the duplicate either was suppressed or is already in this array.
        XCTAssertEqual(receivedTokens, ["story-dup"])
    }

    func testCartChangedTrigger() {
        let manager = StoryManagerService()
        let story = StoryResponse(
            token: "cart-story",
            trigger: "cartChanged",
            slides: [StorySlideResponse(id: "s1", durationSeconds: 5)]
        )

        let expectation = expectation(description: "Cart story published")
        StoryDisplayController.shared.storyPublisher
            .sink { received in
                XCTAssertEqual(received.token, "cart-story")
                expectation.fulfill()
            }
            .store(in: &cancellables)

        manager.initialize(newStories: [story])
        manager.onCartChanged()

        waitForExpectations(timeout: 2)
    }

    func testWishlistChangedTrigger() {
        let manager = StoryManagerService()
        let story = StoryResponse(
            token: "wishlist-story",
            trigger: "wishlistChanged",
            slides: [StorySlideResponse(id: "s1", durationSeconds: 5)]
        )

        let expectation = expectation(description: "Wishlist story published")
        StoryDisplayController.shared.storyPublisher
            .sink { received in
                XCTAssertEqual(received.token, "wishlist-story")
                expectation.fulfill()
            }
            .store(in: &cancellables)

        manager.initialize(newStories: [story])
        manager.onWishlistChanged()

        waitForExpectations(timeout: 2)
    }

    func testDispose() {
        let manager = StoryManagerService()
        let story = StoryResponse(
            token: "story-timer",
            trigger: "delaySeconds",
            delaySeconds: 60,
            slides: [StorySlideResponse(id: "s1", durationSeconds: 5)]
        )

        var receivedTokens: [String] = []
        StoryDisplayController.shared.storyPublisher
            .sink { receivedTokens.append($0.token) }
            .store(in: &cancellables)

        manager.initialize(newStories: [story])
        manager.dispose()

        // `initialize` and `dispose` both run inline here, so the timer is scheduled and
        // invalidated before this line. Nothing can wait for the trigger itself: it is 60 s
        // out, which the 0.5 s inverted wait this replaces could not have reached either.
        XCTAssertTrue(receivedTokens.isEmpty, "a disposed manager must not publish its delayed story")
    }
}
