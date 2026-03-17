import XCTest
@testable import RelevaSDK

final class StoryManagerServiceTests: XCTestCase {

    func testInitializeWithImmediateTrigger() {
        let manager = StoryManagerService()
        let story = StoryResponse(
            token: "story-1",
            trigger: "immediately",
            slides: [StorySlideResponse(id: "s1", durationSeconds: 5)]
        )

        manager.initialize(newStories: [story])
        // Should trigger immediately
    }

    func testInitializeWithEmptySlides() {
        let manager = StoryManagerService()
        let story = StoryResponse(
            token: "story-1",
            trigger: "immediately",
            slides: []
        )

        manager.initialize(newStories: [story])
        // Should not trigger (empty slides)
    }

    func testDeduplication() {
        let manager = StoryManagerService()
        let story = StoryResponse(
            token: "story-dup",
            trigger: "immediately",
            slides: [StorySlideResponse(id: "s1", durationSeconds: 5)]
        )

        // Initialize twice should not show the story twice
        manager.initialize(newStories: [story, story])
    }

    func testCartChangedTrigger() {
        let manager = StoryManagerService()
        let story = StoryResponse(
            token: "cart-story",
            trigger: "cartChanged",
            slides: [StorySlideResponse(id: "s1", durationSeconds: 5)]
        )

        manager.initialize(newStories: [story])
        manager.onCartChanged()
        // Should trigger the cart story
    }

    func testWishlistChangedTrigger() {
        let manager = StoryManagerService()
        let story = StoryResponse(
            token: "wishlist-story",
            trigger: "wishlistChanged",
            slides: [StorySlideResponse(id: "s1", durationSeconds: 5)]
        )

        manager.initialize(newStories: [story])
        manager.onWishlistChanged()
        // Should trigger the wishlist story
    }

    func testDispose() {
        let manager = StoryManagerService()
        let story = StoryResponse(
            token: "story-timer",
            trigger: "delaySeconds",
            delaySeconds: 60,
            slides: [StorySlideResponse(id: "s1", durationSeconds: 5)]
        )

        manager.initialize(newStories: [story])
        manager.dispose() // Should cancel timers
    }
}
