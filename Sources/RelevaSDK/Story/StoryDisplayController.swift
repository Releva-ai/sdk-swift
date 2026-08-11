import Foundation
import Combine

/// Singleton controller that manages story display events.
/// Stories are emitted here by StoryManagerService and consumed by StoryDisplayView.
public class StoryDisplayController: ObservableObject {
    /// Shared instance
    public static let shared = StoryDisplayController()

    /// Published story events
    private let storySubject = PassthroughSubject<StoryResponse, Never>()

    /// Publisher for story events
    public var storyPublisher: AnyPublisher<StoryResponse, Never> {
        storySubject.eraseToAnyPublisher()
    }

    private init() {}

    /// Emit a story to be displayed
    public func showStory(_ story: StoryResponse) {
        storySubject.send(story)
    }
}
