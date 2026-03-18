import Foundation

/// Manages story trigger logic and lifecycle.
/// Handles trigger types: immediately, delaySeconds, scrollPercentage, cartChanged, wishlistChanged.
public class StoryManagerService {

    private var stories: [StoryResponse] = []
    private var displayedStories = Set<String>()
    private var delayTimers: [Timer] = []
    private var scrollTimer: Timer?
    private var scrollTriggeredStories: [StoryResponse] = []
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
                    let scheduleBlock = { [weak self] in
                        let timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(delay), repeats: false) { [weak self] _ in
                            self?.triggerStory(story)
                        }
                        self?.delayTimers.append(timer)
                    }
                    if Thread.isMainThread {
                        scheduleBlock()
                    } else {
                        DispatchQueue.main.async(execute: scheduleBlock)
                    }
                }

            case "scrollPercentage":
                if story.scrollPercentage != nil, scrollPercentageProvider != nil {
                    scrollTriggeredStories.append(story)
                }

            case "cartChanged", "wishlistChanged", "leaveIntent":
                break

            default:
                break
            }
        }

        if !scrollTriggeredStories.isEmpty {
            setupScrollTimer()
        }
    }

    private func setupScrollTimer() {
        let scheduleBlock: () -> Void = { [weak self] in
            self?.scrollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self = self,
                      let provider = self.scrollPercentageProvider else { return }
                let current = provider()
                var allTriggered = true
                for story in self.scrollTriggeredStories {
                    guard let threshold = story.scrollPercentage else { continue }
                    if current >= threshold && !self.displayedStories.contains(story.token) {
                        self.triggerStory(story)
                    }
                    if !self.displayedStories.contains(story.token) {
                        allTriggered = false
                    }
                }
                if allTriggered {
                    self.scrollTimer?.invalidate()
                    self.scrollTimer = nil
                }
            }
        }
        if Thread.isMainThread {
            scheduleBlock()
        } else {
            DispatchQueue.main.async(execute: scheduleBlock)
        }
    }

    /// Call when the cart changes to trigger cart-based stories
    public func onCartChanged() {
        let work = { [weak self] in
            guard let self = self else { return }
            self.stories.filter { $0.trigger == "cartChanged" }.forEach { self.triggerStory($0) }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    /// Call when the wishlist changes to trigger wishlist-based stories
    public func onWishlistChanged() {
        let work = { [weak self] in
            guard let self = self else { return }
            self.stories.filter { $0.trigger == "wishlistChanged" }.forEach { self.triggerStory($0) }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    /// Must be called on main thread.
    private func triggerStory(_ story: StoryResponse) {
        guard !displayedStories.contains(story.token) else { return }
        displayedStories.insert(story.token)
        StoryDisplayController.shared.showStory(story)
    }

    /// Clean up timers
    public func dispose() {
        let timers = delayTimers
        let scroll = scrollTimer
        delayTimers.removeAll()
        scrollTimer = nil
        scrollTriggeredStories.removeAll()

        let invalidateBlock = {
            timers.forEach { $0.invalidate() }
            scroll?.invalidate()
        }
        if Thread.isMainThread {
            invalidateBlock()
        } else {
            DispatchQueue.main.async(execute: invalidateBlock)
        }
    }

    deinit {
        delayTimers.forEach { $0.invalidate() }
        scrollTimer?.invalidate()
    }
}
