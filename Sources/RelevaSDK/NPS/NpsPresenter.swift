import Combine
import SwiftUI
import UIKit

/// Presents NPS surveys from a `UIViewController`, for apps that are not built in SwiftUI.
///
/// This is the UIKit counterpart of `View.npsDisplay(onSubmit:onSkip:)`. It shows the same
/// `NpsSurveyView` in a sheet-style `UIHostingController`, so the survey looks and behaves the
/// same on both paths.
///
/// Reporting the response is the app's job on both paths — pass a closure that calls
/// `RelevaClient.submitNpsResponse(token:score:comment:completion:)`:
///
/// ```swift
/// final class HomeViewController: UIViewController {
///     let client: RelevaClient
///
///     private lazy var nps = NpsPresenter(host: self, onSubmit: { [weak self] token, score, comment in
///         self?.client.submitNpsResponse(token: token, score: score, comment: comment)
///     })
///
///     override func viewWillAppear(_ animated: Bool) {
///         super.viewWillAppear(animated)
///         nps.start()
///     }
///
///     override func viewWillDisappear(_ animated: Bool) {
///         super.viewWillDisappear(animated)
///         nps.stop()
///     }
/// }
/// ```
@MainActor
public final class NpsPresenter {
    private weak var host: UIViewController?
    private let onSubmit: (String, Int, String?) -> Void
    private let onSkip: (() -> Void)?

    private var cancellable: AnyCancellable?
    /// The presented survey, or `nil` when none is up. Internal rather than private so a test
    /// can assert on what the presenter put up and then let go of — UIKit's own transitions do
    /// not complete in this package's test host, so the presenter's side of a dismissal is
    /// observable there and UIKit's is not.
    private(set) var surveyController: UIViewController?

    /// - Parameters:
    ///   - host: The view controller the survey is presented from. Held weakly.
    ///   - onSubmit: Called with the survey token, the score and the optional follow-up comment.
    ///   - onSkip: Called when the user taps Skip.
    public init(
        host: UIViewController,
        onSubmit: @escaping (String, Int, String?) -> Void,
        onSkip: (() -> Void)? = nil
    ) {
        self.host = host
        self.onSubmit = onSubmit
        self.onSkip = onSkip
    }

    // MARK: - Lifecycle

    /// Begin listening for surveys. Calling this while already started does nothing.
    public func start() {
        guard cancellable == nil else { return }

        cancellable = NpsDisplayController.shared.npsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] config in
                self?.present(config)
            }
    }

    /// Stop listening and take down a survey that is on screen.
    public func stop() {
        cancellable?.cancel()
        cancellable = nil
        close(animated: false)
    }

    // MARK: - Presentation

    private func present(_ config: NpsConfig) {
        // `presentingViewController` is nil once a sheet has gone, including after the user
        // swiped it down, so this covers "a survey is already up", "the last one is gone, show
        // this one", and "the last `present` was declined by UIKit and never took" without
        // keeping any state of its own that could disagree with what is on screen. A declined
        // presentation therefore reaches the screen when the next survey arrives rather than
        // immediately; see the note in `BannerPresenter.syncOverlay`.
        guard surveyController?.presentingViewController == nil, let host = host else { return }

        let controller = UIHostingController(
            rootView: NpsSurveyView(
                config: IdentifiableNpsConfig(config: config),
                onSubmit: onSubmit,
                onSkip: onSkip
            ) { [weak self] in self?.close(animated: true) }
        )
        controller.modalPresentationStyle = .pageSheet
        controller.sheetPresentationController?.detents = [.medium(), .large()]
        surveyController = controller
        host.topMostPresentedViewController.present(controller, animated: true)
    }

    private func close(animated: Bool) {
        guard let controller = surveyController else { return }

        // Nil when the presentation never took or the sheet is already gone — including a swipe
        // dismissal, which never routes through this method at all — so nothing to dismiss and
        // nothing to clean up either.
        guard let presenting = controller.presentingViewController else {
            surveyController = nil
            return
        }

        // Only let go of the reference once UIKit confirms the dismissal actually happened, the
        // same shape as `BannerPresenter.syncOverlay`: a sheet still `isBeingPresented` (skipped
        // or submitted during its own presentation) declines `dismiss` and only logs, so clearing
        // `surveyController` up front would leave nothing able to reach the orphaned sheet again.
        // Unlike `BannerPresenter`, nothing here retries a declined dismiss: `present`'s guard
        // just returns while `surveyController` still points at the orphaned sheet, so it — and
        // every survey after it — stays unshown for the rest of the app session.
        // `BannerPresenter` doesn't have this gap because `reconcile` runs on every banner event
        // and its `isNeeded: false` branch re-issues the dismiss; nothing plays that role here.
        // Recovery is user-driven only: a `.pageSheet` is swipe-dismissable, which is what keeps
        // this from being worse than the banner case. See the CHANGELOG's "Known limitations".
        presenting.dismiss(animated: animated) { [weak self] in
            // Identity-checked rather than an unconditional clear: `present` can replace
            // `surveyController` with a new sheet before this completion lands (a fast
            // skip-then-next-survey), and the property could otherwise be dropping the live
            // sheet's reference instead of the one that was actually dismissed.
            guard let self = self, self.surveyController === controller else { return }
            self.surveyController = nil
        }
    }
}
