import Combine
import SwiftUI
import UIKit

/// Displays stories over a `UIViewController`, for apps that are not built in SwiftUI.
///
/// This is the UIKit counterpart of `View.storyDisplay(client:onLinkTap:)`. It shows the same
/// `StoryViewerView` full screen and queues stories through the same `StoryDisplayViewModel`, so
/// impressions, slide views, slide clicks, completion and close are reported identically on both
/// paths, and a story that arrives while another is playing waits for it in the same way.
///
/// Retain the presenter for as long as the host is on screen, and bracket it with the host's
/// appearance callbacks:
///
/// ```swift
/// final class FeedViewController: UIViewController {
///     let client: RelevaClient
///
///     private lazy var stories = StoryPresenter(host: self, client: client) { [weak self] url in
///         self?.handleDeepLink(url)
///     }
///
///     override func viewWillAppear(_ animated: Bool) {
///         super.viewWillAppear(animated)
///         stories.start()
///     }
///
///     override func viewWillDisappear(_ animated: Bool) {
///         super.viewWillDisappear(animated)
///         stories.stop()
///     }
/// }
/// ```
@MainActor
public final class StoryPresenter {
    private weak var host: UIViewController?
    private let client: RelevaClient
    private let tracker: StoryTracker
    private let onLinkTap: (String) -> Void
    /// The same view model the SwiftUI modifier drives, holding the queue this presenter plays.
    /// Internal rather than private so a test can read what is waiting.
    let viewModel = StoryDisplayViewModel()

    private var cancellable: AnyCancellable?
    /// The presented viewer, or `nil` when nothing is up. Internal rather than private so a test
    /// can assert on what the presenter put up and then let go of — UIKit's own transitions do
    /// not complete in this package's test host, so the presenter's side of a dismissal is
    /// observable there and UIKit's is not.
    private(set) var viewerController: UIHostingController<StoryViewerView>?

    /// - Parameters:
    ///   - host: The view controller the stories are shown over. Held weakly.
    ///   - client: The client that reports impressions, slide events and closes.
    ///   - onLinkTap: Called when a link in a slide, or the slide's action button, is tapped.
    ///     Required — apps must handle link navigation.
    public convenience init(
        host: UIViewController,
        client: RelevaClient,
        onLinkTap: @escaping (String) -> Void
    ) {
        self.init(host: host, client: client, tracker: client, onLinkTap: onLinkTap)
    }

    /// `tracker` is `client` in production. A test substitutes a spy for it so that counting a
    /// story does no network I/O, which is the seam `BannerPresenter` has for banners.
    init(
        host: UIViewController,
        client: RelevaClient,
        tracker: StoryTracker,
        onLinkTap: @escaping (String) -> Void
    ) {
        self.host = host
        self.client = client
        self.tracker = tracker
        self.onLinkTap = onLinkTap
    }

    // MARK: - Lifecycle

    /// Begin listening for stories. Calling this while already started does nothing.
    public func start() {
        guard cancellable == nil, host != nil else { return }

        viewModel.start(tracker: tracker)

        // `receive(on:)` so the presentation happens after the view model has committed the
        // story: `@Published` fires from `willSet`.
        cancellable = viewModel.$activeStory
            .receive(on: DispatchQueue.main)
            .sink { [weak self] story in
                self?.sync(story)
            }
    }

    /// Stop listening and take down a story that is on screen. The close is not tracked, matching
    /// the SwiftUI modifier: the story was not closed, the screen went away. The story stays the
    /// active one, so the next `start()` shows it again from its first slide.
    ///
    /// This does not run on `deinit`, for the reason `BannerPresenter.stop()` documents: bracket
    /// `start()` / `stop()` with the host's appearance callbacks, or a viewer UIKit declined to
    /// dismiss stays on screen with nothing left to reach it.
    public func stop() {
        cancellable?.cancel()
        cancellable = nil
        viewModel.stop()

        if let controller = viewerController {
            // Only let go of the reference once UIKit has actually taken the viewer down, as
            // `BannerPresenter.stop()` does and for the same reason: a controller still
            // `isBeingPresented` declines `dismiss` and only logs, and the next `start()` of this
            // presenter is then the one thing that can still reach it.
            controller.presentingViewController?.dismiss(animated: false)
            if controller.presentingViewController == nil {
                viewerController = nil
            }
        }
    }

    // MARK: - Presentation

    /// How long to wait before presenting again after UIKit declined a `present`.
    static let presentRetryDelay: TimeInterval = 0.3

    /// Puts the story on screen, or takes the last one down, so that what is presented matches
    /// the view model. A `present` UIKit declined — it only logs, it does not throw — is read
    /// back from `presentingViewController` and retried after `presentRetryDelay`: the view model
    /// already handed the story over and holds it as the active one, so no later story would
    /// ever reach this method to retry it.
    private func sync(_ story: IdentifiableStory?) {
        guard let story = story else {
            dismissViewer()
            return
        }

        if let existing = viewerController, existing.presentingViewController == nil {
            // Either the last `present` never took, or something else dismissed the viewer.
            viewerController = nil
        }
        guard viewerController == nil, let host = host else { return }

        let controller = UIHostingController(
            rootView: StoryViewerView(
                story: story.story,
                client: client,
                onLinkTap: onLinkTap
            ) { [weak self] in
                // The viewer never takes itself off screen; the view model's queue waits for the
                // dismissal below before it hands over the next story.
                self?.viewModel.storyClosed()
            }
        )
        controller.modalPresentationStyle = .overFullScreen
        viewerController = controller
        // Present from whatever is frontmost, as `BannerPresenter` does, so a story is not lost
        // behind a modal the host already had up.
        host.topMostPresentedViewController.present(controller, animated: true)

        if controller.presentingViewController == nil {
            viewerController = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.presentRetryDelay) { [weak self] in
                guard let self = self, self.cancellable != nil, self.viewerController == nil,
                      self.viewModel.activeStory?.id == story.id else { return }
                self.sync(story)
            }
        }
    }

    private func dismissViewer() {
        // No viewer at all: what `stop()` leaves when the story it took down was closed while its
        // dismissal was still animating, so that no completion told the view model the cover is
        // free. `start()` lands here, and the queue must not stay stuck behind it.
        guard let controller = viewerController else {
            viewModel.coverDidDisappear()
            return
        }

        // Nil when the presentation never took or something else already took the viewer down.
        guard let presenting = controller.presentingViewController else {
            viewerController = nil
            viewModel.coverDidDisappear()
            return
        }

        presenting.dismiss(animated: true) { [weak self] in
            guard let self = self, self.viewerController === controller else { return }
            self.viewerController = nil
            // A completion that lands after `stop()` must not count the next story while the
            // host is off screen, as `BannerPresenter`'s matching completion does not.
            guard self.cancellable != nil else { return }
            // What `onDisappear` tells the view model on the SwiftUI path: the screen is free,
            // play the next story. A dismissal UIKit declines never lands here, which is what
            // `StoryDisplayViewModel.dismissalFallback` covers.
            self.viewModel.coverDidDisappear()
        }
    }
}
