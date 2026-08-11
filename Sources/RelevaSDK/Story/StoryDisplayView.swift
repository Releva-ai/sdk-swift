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
                )                    {
                        viewModel.activeStory = nil
                    }
            }
            .onAppear {
                viewModel.start(client: client)
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

// MARK: - ViewModel

@MainActor
class StoryDisplayViewModel: ObservableObject {
    @Published var activeStory: IdentifiableStory?

    private var storyQueue: [StoryResponse] = []
    private var cancellable: AnyCancellable?
    private var client: RelevaClient?
    private var storyCancellable: AnyCancellable?

    func start(client: RelevaClient) {
        self.client = client

        cancellable = StoryDisplayController.shared.storyPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] story in
                self?.enqueue(story)
            }

        // Watch for activeStory becoming nil (story dismissed) to process queue
        storyCancellable = $activeStory
            .dropFirst()
            .filter { $0 == nil }
            .sink { [weak self] _ in
                self?.processQueue()
            }
    }

    private func enqueue(_ story: StoryResponse) {
        guard !story.slides.isEmpty else { return }
        storyQueue.append(story)
        if activeStory == nil {
            processQueue()
        }
    }

    private func processQueue() {
        guard activeStory == nil, !storyQueue.isEmpty else { return }
        let story = storyQueue.removeFirst()

        // Track impression
        client?.storyImpression(story)

        activeStory = IdentifiableStory(story: story)
    }
}

/// Wrapper to make StoryResponse identifiable for .fullScreenCover(item:)
struct IdentifiableStory: Identifiable {
    let id = UUID()
    let story: StoryResponse
}
