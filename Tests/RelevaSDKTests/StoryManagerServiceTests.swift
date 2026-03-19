import XCTest
import Combine
@testable import RelevaSDK

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

        let expectation = expectation(description: "Story should not fire")
        expectation.isInverted = true
        StoryDisplayController.shared.storyPublisher
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        manager.initialize(newStories: [story])

        waitForExpectations(timeout: 0.5)
    }

    func testDeduplication() {
        let manager = StoryManagerService()
        let story = StoryResponse(
            token: "story-dup",
            trigger: "immediately",
            slides: [StorySlideResponse(id: "s1", durationSeconds: 5)]
        )

        var receivedCount = 0
        let expectation = expectation(description: "Story published once")
        StoryDisplayController.shared.storyPublisher
            .sink { received in
                receivedCount += 1
                XCTAssertEqual(received.token, "story-dup")
                expectation.fulfill()
            }
            .store(in: &cancellables)

        manager.initialize(newStories: [story, story])

        waitForExpectations(timeout: 2)
        // Give time for potential duplicate
        let noMore = expectation(description: "No more stories")
        noMore.isInverted = true
        waitForExpectations(timeout: 0.3)
        XCTAssertEqual(receivedCount, 1)
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

        let expectation = expectation(description: "Story should not fire after dispose")
        expectation.isInverted = true
        StoryDisplayController.shared.storyPublisher
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        manager.initialize(newStories: [story])
        manager.dispose()

        waitForExpectations(timeout: 0.5)
    }
}
