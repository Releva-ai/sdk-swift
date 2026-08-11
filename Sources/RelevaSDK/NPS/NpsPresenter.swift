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
    private var surveyController: UIViewController?
    /// Bounds the retry in `present` below so a host that can never present (rather than one
    /// mid-transition) does not spin forever redoing the same failing presentation.
    private var presentRetriesRemaining = 2

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

        presentRetriesRemaining = 2
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
        // swiped it down, so this covers both "a survey is already up" and "the last one is
        // gone, show this one" without tracking dismissal separately.
        guard surveyController?.presentingViewController == nil, let host = host else { return }

        let controller = UIHostingController(
            rootView: NpsSurveyView(
                config: IdentifiableNpsConfig(config: config),
                onSubmit: onSubmit,
                onSkip: onSkip,
                onClose: { [weak self] in self?.close(animated: true) }
            )
        )
        controller.modalPresentationStyle = .pageSheet
        controller.sheetPresentationController?.detents = [.medium(), .large()]
        surveyController = controller
        host.topMostPresentedViewController.present(controller, animated: true)

        if controller.presentingViewController == nil {
            // The presentation did not take — UIKit only logs, e.g. when
            // `topMostPresentedViewController` handed back a controller whose own dismissal was
            // still in flight. Nothing re-drives `present` until the next survey arrives, so
            // without a retry this one would be lost rather than shown. `present` sets
            // `presentingViewController` synchronously when it takes, so this is observable
            // right here.
            surveyController = nil
            if presentRetriesRemaining > 0 {
                presentRetriesRemaining -= 1
                DispatchQueue.main.async { [weak self] in
                    // `cancellable` is the started flag: a retry landing after `stop()` must not
                    // put a survey back up.
                    guard let self = self, self.cancellable != nil else { return }
                    self.present(config)
                }
            }
            // A host that can never present gives up here instead of retrying indefinitely.
        } else {
            // A later failure gets its own fresh budget rather than draining across unrelated
            // surveys.
            presentRetriesRemaining = 2
        }
    }

    private func close(animated: Bool) {
        guard let controller = surveyController else { return }

        surveyController = nil
        controller.presentingViewController?.dismiss(animated: animated)
    }
}
