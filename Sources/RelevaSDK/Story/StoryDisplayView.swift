import SwiftUI
import Combine

/// A SwiftUI view modifier that wraps content and displays stories when triggered.
///
/// Stories are queued and shown sequentially (one at a time) in a full-screen cover.
///
/// Usage:
/// ```swift
/// HomeView()
///     .storyDisplay(client: relevaClient) { url in
///         handleDeepLink(url)
///     }
/// ```
public struct StoryDisplayModifier: ViewModifier {
    let client: RelevaClient
    let onLinkTap: (String) -> Void

    @StateObject private var viewModel = StoryDisplayViewModel()

    public func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $viewModel.activeStory) { story in
                StoryViewerView(
                    story: story.story,
                    client: client,
                    onLinkTap: onLinkTap
                ) {
                    viewModel.storyClosed()
                }
                // Fires once the cover has left the screen; the next queued story is presented
                // from here, never while this one is still animating out.
                .onDisappear { viewModel.coverDidDisappear() }
            }
            .onAppear {
                viewModel.start(tracker: client)
            }
    }
}

// MARK: - View Extension

extension View {
    /// Add story display capability to this view.
    /// - Parameters:
    ///   - client: The RelevaClient instance
    ///   - onLinkTap: Callback when a story link is tapped. Required — apps must handle link navigation.
    public func storyDisplay(
        client: RelevaClient,
        onLinkTap: @escaping (String) -> Void
    ) -> some View {
        self.modifier(StoryDisplayModifier(
            client: client,
            onLinkTap: onLinkTap
        ))
    }
}

// MARK: - Tracking Seam

/// The part of `RelevaClient` that story display uses; a test substitutes a spy so that no
/// real network I/O happens (see `BannerTracker`).
@MainActor
protocol StoryTracker: AnyObject {
    func storyImpression(_ story: StoryResponse)
}

extension RelevaClient: StoryTracker {}

// MARK: - ViewModel

@MainActor
class StoryDisplayViewModel: ObservableObject {
    @Published var activeStory: IdentifiableStory?

    private var storyQueue: [StoryResponse] = []
    private var cancellable: AnyCancellable?
    private var tracker: StoryTracker?

    /// `true` from the moment a story is handed to the cover until the cover reports that it has
    /// disappeared. `activeStory` is `nil` while the dismissal animates, and a story presented in
    /// that window is counted but never shown.
    private(set) var coverOnScreen = false

    /// If the cover never reports its disappearance, the queue resumes after this long.
    static let dismissalFallback: TimeInterval = 1.5
    private var fallbackTask: Task<Void, Never>?

    func start(tracker: StoryTracker) {
        self.tracker = tracker

        cancellable = StoryDisplayController.shared.storyPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] story in
                self?.enqueue(story)
            }
    }

    /// The viewer asked to be taken off screen (close, or end behaviour "dismiss").
    func storyClosed() {
        activeStory = nil
        fallbackTask?.cancel()
        fallbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.dismissalFallback * 1_000_000_000))
            guard !Task.isCancelled, let self = self, self.activeStory == nil else { return }
            self.coverDidDisappear()
        }
    }

    /// The cover's content left the screen. A story presented before this point is dropped by
    /// SwiftUI: counted, never seen.
    func coverDidDisappear() {
        // `onDisappear` can also fire while the story is still up (e.g. a re-parented view);
        // only a closed story frees the cover.
        guard activeStory == nil else { return }
        fallbackTask?.cancel()
        fallbackTask = nil
        coverOnScreen = false
        processQueue()
    }

    private func enqueue(_ story: StoryResponse) {
        guard !story.slides.isEmpty else { return }
        // Several screen views in quick succession return the same story; keep one copy so a close
        // does not fire a storyImpression with nothing new on screen.
        guard activeStory?.story.token != story.token,
              !storyQueue.contains(where: { $0.token == story.token }) else { return }
        storyQueue.append(story)
        processQueue()
    }

    private func processQueue() {
        guard activeStory == nil, !coverOnScreen, !storyQueue.isEmpty else { return }
        let story = storyQueue.removeFirst()

        coverOnScreen = true
        // Track impression
        tracker?.storyImpression(story)

        activeStory = IdentifiableStory(story: story)
    }
}

/// Wrapper to make StoryResponse identifiable for .fullScreenCover(item:)
struct IdentifiableStory: Identifiable {
    let id = UUID()
    let story: StoryResponse
}
