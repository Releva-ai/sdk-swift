import Foundation

/// Manages story trigger logic and lifecycle.
/// Handles trigger types: immediately, delaySeconds, scrollPercentage, cartChanged, wishlistChanged.
public class StoryManagerService {

    private var stories: [StoryResponse] = []
    private var displayedStories = Set<String>()
    private var delayTimers: [Timer] = []
    private var scrollTimer: Timer?
    private var scrollPercentageProvider: (() -> Int)?

    /// Initialize with stories from a push response.
    /// Clears previous state and sets up triggers for each story.
    public func initialize(
        newStories: [StoryResponse],
        scrollPercentageProvider: (() -> Int)? = nil
    ) {
        dispose()

        stories = newStories
        displayedStories.removeAll()
        self.scrollPercentageProvider = scrollPercentageProvider

        setupTriggers()
    }

    private func setupTriggers() {
        for story in stories {
            guard !story.slides.isEmpty else { continue }

            switch story.trigger {
            case "immediately":
                triggerStory(story)

            case "delaySeconds":
                if let delay = story.delaySeconds, delay > 0 {
                    let timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(delay), repeats: false) { [weak self] _ in
                        self?.triggerStory(story)
                    }
                    delayTimers.append(timer)
                }

            case "scrollPercentage":
                if story.scrollPercentage != nil, scrollPercentageProvider != nil {
                    setupScrollTrigger(story)
                }

            case "cartChanged", "wishlistChanged", "leaveIntent":
                break

            default:
                break
            }
        }
    }

    private func setupScrollTrigger(_ story: StoryResponse) {
        guard scrollTimer == nil else { return }
        scrollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self,
                  let provider = self.scrollPercentageProvider,
                  let threshold = story.scrollPercentage else { return }
            let current = provider()
            if current >= threshold && !self.displayedStories.contains(story.token) {
                self.triggerStory(story)
                self.scrollTimer?.invalidate()
                self.scrollTimer = nil
            }
        }
    }

    /// Call when the cart changes to trigger cart-based stories
    public func onCartChanged() {
        stories.filter { $0.trigger == "cartChanged" }.forEach { triggerStory($0) }
    }

    /// Call when the wishlist changes to trigger wishlist-based stories
    public func onWishlistChanged() {
        stories.filter { $0.trigger == "wishlistChanged" }.forEach { triggerStory($0) }
    }

    private func triggerStory(_ story: StoryResponse) {
        guard !displayedStories.contains(story.token) else { return }
        displayedStories.insert(story.token)
        StoryDisplayController.shared.showStory(story)
    }

    /// Clean up timers
    public func dispose() {
        delayTimers.forEach { $0.invalidate() }
        delayTimers.removeAll()
        scrollTimer?.invalidate()
        scrollTimer = nil
    }

    deinit {
        dispose()
    }
}
