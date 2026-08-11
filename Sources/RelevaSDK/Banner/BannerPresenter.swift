import Combine
import SwiftUI
import UIKit

/// Displays banners over a `UIViewController`, for apps that are not built in SwiftUI.
///
/// This is the UIKit counterpart of `View.bannerDisplay(client:targetSelector:onLinkTap:)`.
/// It renders the same SwiftUI views inside `UIHostingController`s and reports impressions,
/// clicks and dismissals through the same `BannerDisplayViewModel`, so tracking cannot drift
/// between the two paths.
///
/// Retain the presenter for as long as the host is on screen, and bracket it with the host's
/// appearance callbacks:
///
/// ```swift
/// final class HomeViewController: UIViewController {
///     let client: RelevaClient
///
///     private lazy var banners = BannerPresenter(host: self, client: client) { [weak self] url in
///         self?.handleDeepLink(url)
///     }
///
///     override func viewWillAppear(_ animated: Bool) {
///         super.viewWillAppear(animated)
///         banners.start()
///     }
///
///     override func viewWillDisappear(_ animated: Bool) {
///         super.viewWillDisappear(animated)
///         banners.stop()
///     }
/// }
/// ```
///
/// Only popup, flyout and bar banners are shown. Static and replace banners are laid out inside
/// the host's own content, which a presenter cannot do, so they are ignored here — including for
/// impression tracking — and remain the SwiftUI modifier's job.
@MainActor
public final class BannerPresenter {

    private weak var host: UIViewController?
    private let tracker: BannerTracker
    private let onLinkTap: (String) -> Void
    /// The same view model the SwiftUI modifier drives, holding the banner state this
    /// presenter mirrors into UIKit. Internal rather than private so a test can dismiss a
    /// banner the way a tap on its close button would.
    let viewModel = BannerDisplayViewModel()

    private var cancellable: AnyCancellable?
    private var overlayController: UIHostingController<BannerOverlayView>?
    private var isDismissingOverlay = false
    private var barSlots: [BarSlot] = []

    /// - Parameters:
    ///   - host: The view controller the banners are shown over. Held weakly.
    ///   - client: The client that reports impressions, clicks and dismissals.
    ///   - onLinkTap: Called when a link inside a banner design is tapped. Required — apps must
    ///     handle link navigation.
    public convenience init(
        host: UIViewController,
        client: RelevaClient,
        onLinkTap: @escaping (String) -> Void
    ) {
        self.init(host: host, tracker: client, onLinkTap: onLinkTap)
    }

    init(host: UIViewController, tracker: BannerTracker, onLinkTap: @escaping (String) -> Void) {
        self.host = host
        self.tracker = tracker
        self.onLinkTap = onLinkTap
    }

    // MARK: - Lifecycle

    /// Begin listening for banners. Calling this while already started does nothing.
    public func start() {
        guard cancellable == nil, let host = host else { return }

        installBarSlots(in: host)
        viewModel.start(tracker: tracker, targetSelector: "", overlayOnly: true, onLinkTap: onLinkTap)

        // `receive(on:)` so a reconcile sees the view model's committed state: `@Published`
        // fires from `willSet`, before the property it is derived from has been assigned.
        cancellable = viewModel.$popupBanner
            .combineLatest(viewModel.$flyoutBanner, viewModel.$barBanners)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] popup, flyout, _ in
                self?.reconcile(hasOverlay: popup != nil || flyout != nil)
            }
    }

    /// Stop listening and take down anything on screen. Dismissals are not tracked, matching
    /// the SwiftUI modifier's `onDisappear`: the banner was not closed, the screen went away.
    ///
    /// The view model's banner state is untouched, so a later `start()` re-presents whatever
    /// was on screen — without a second impression, since `trackImpression` only runs when a
    /// banner first arrives. That mirrors the modifier's own `@StateObject` surviving
    /// `onDisappear`, but it means a host bouncing between tabs sees the same popup again each
    /// time it comes back.
    ///
    /// This does not run on `deinit`. A presenter released while started (the host deallocated
    /// without a matching `viewWillDisappear`, or an app that simply forgets to call `stop()`)
    /// leaves any presented overlay on screen with nothing left to dismiss it — bracket `start()`
    /// / `stop()` with the host's appearance callbacks as shown above to avoid that.
    public func stop() {
        cancellable?.cancel()
        cancellable = nil
        viewModel.stop()

        isDismissingOverlay = false
        if let controller = overlayController {
            overlayController = nil
            controller.presentingViewController?.dismiss(animated: false)
        }

        for slot in barSlots {
            slot.controller.willMove(toParent: nil)
            slot.controller.view.removeFromSuperview()
            slot.controller.removeFromParent()
        }
        barSlots = []
    }

    // MARK: - Reconciliation

    private func reconcile(hasOverlay: Bool) {
        syncOverlay(isNeeded: hasOverlay)
        measureBars()
    }

    private func syncOverlay(isNeeded: Bool) {
        if isNeeded {
            if let existing = overlayController, existing.presentingViewController == nil {
                // The last attempt never took: `topMostPresentedViewController` can hand back a
                // controller whose own dismissal was still in flight, in which case `present`
                // logged "already presenting" and did nothing — or something else (an app modal
                // above the overlay, say) already dismissed it. Either way there is nothing to
                // reuse; drop it so the block below tries again instead of no-oping forever on
                // the `overlayController == nil` guard.
                overlayController = nil
            }
            guard overlayController == nil, !isDismissingOverlay, let host = host else { return }

            let controller = UIHostingController(
                rootView: BannerOverlayView(viewModel: viewModel, onLinkTap: onLinkTap)
            )
            controller.view.backgroundColor = .clear
            controller.modalPresentationStyle = .overFullScreen
            controller.modalTransitionStyle = .crossDissolve
            overlayController = controller
            // Present from whatever is frontmost so a banner is not lost behind a modal the
            // host already had up, and so the banner itself can be covered by a later one. This
            // also means dismissing the overlay later takes down anything the app itself
            // presented above it in the meantime — the usual trade-off of dismissing via
            // `presentingViewController` rather than tracking the exact controller to close.
            host.topMostPresentedViewController.present(controller, animated: true)
        } else {
            guard let controller = overlayController else { return }

            // If the presentation above never took, or something else already took the overlay
            // down, there is nothing to dismiss — and the completion below would never run,
            // latching `isDismissingOverlay` on and silently blocking every later popup/flyout
            // until a `stop()` / `start()` cycle.
            guard let presenting = controller.presentingViewController else {
                overlayController = nil
                return
            }

            overlayController = nil
            isDismissingOverlay = true
            presenting.dismiss(animated: true) { [weak self] in
                // `cancellable` is the started flag: a completion that lands after `stop()`
                // must not put a banner back up.
                guard let self = self, self.cancellable != nil else { return }
                self.isDismissingOverlay = false
                // A banner that arrived mid-dismissal was skipped above, so re-check.
                let hasOverlay = self.viewModel.popupBanner != nil || self.viewModel.flyoutBanner != nil
                self.syncOverlay(isNeeded: hasOverlay)
            }
        }
    }

    // MARK: - Bar Banners

    /// A bar banner cannot be a modal — that would block the whole screen for a strip of
    /// chrome — so each screen edge gets a child view controller that is empty, and therefore
    /// zero-height and untouchable, until a bar for that edge arrives.
    private struct BarSlot {
        let controller: UIHostingController<BannerBarStackView>
        /// Only set below iOS 16, where `UIHostingController.sizingOptions` does not exist.
        let heightConstraint: NSLayoutConstraint?
    }

    private func installBarSlots(in host: UIViewController) {
        let guide = host.view.safeAreaLayoutGuide

        for isBottom in [false, true] {
            let controller = UIHostingController(
                rootView: BannerBarStackView(viewModel: viewModel, isBottom: isBottom, onLinkTap: onLinkTap)
            )
            controller.view.backgroundColor = .clear
            controller.view.translatesAutoresizingMaskIntoConstraints = false

            host.addChild(controller)
            host.view.addSubview(controller.view)

            var heightConstraint: NSLayoutConstraint?
            if #available(iOS 16.0, *) {
                controller.sizingOptions = .intrinsicContentSize
            } else {
                heightConstraint = controller.view.heightAnchor.constraint(equalToConstant: 0)
            }

            var constraints = [
                controller.view.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
                controller.view.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
                isBottom
                    ? controller.view.bottomAnchor.constraint(equalTo: guide.bottomAnchor)
                    : controller.view.topAnchor.constraint(equalTo: guide.topAnchor)
            ]
            if let heightConstraint = heightConstraint {
                constraints.append(heightConstraint)
            }
            NSLayoutConstraint.activate(constraints)

            controller.didMove(toParent: host)
            barSlots.append(BarSlot(controller: controller, heightConstraint: heightConstraint))
        }
    }

    /// Below iOS 16 the bar's height has to be measured, because `sizingOptions` is
    /// unavailable and nothing else invalidates the hosting view's size when its content
    /// changes. A no-op from iOS 16 up.
    ///
    /// Forces layout first and bails out on a zero width rather than measuring against it: this
    /// can run from `start()`'s first reconcile, one main-queue hop after `viewWillAppear`,
    /// which may be before the host's first layout pass — and a `stop()` / `start()` round trip
    /// can leave `barBanners` already populated when that happens. A skipped measurement here is
    /// caught by the next reconcile once layout has happened.
    ///
    /// Known gap, not fixable without a simulator to observe: `sizeThatFits(in:)` is called in
    /// the same run-loop turn the `@Published` banner change was observed, so whether it sees
    /// the new content or the previous turn's has not been verified here.
    private func measureBars() {
        guard let host = host else { return }
        host.view.layoutIfNeeded()
        let width = host.view.safeAreaLayoutGuide.layoutFrame.width
        guard width > 0 else { return }

        for slot in barSlots {
            guard let heightConstraint = slot.heightConstraint else { continue }
            let fitted = slot.controller.sizeThatFits(
                in: CGSize(width: width, height: .greatestFiniteMagnitude)
            )
            heightConstraint.constant = fitted.height
        }
    }
}

// MARK: - Hosted Views

/// The popup and flyout layer of `BannerDisplayModifier`'s `ZStack`, without the host's content.
///
/// Both slots live in one view — and therefore one presented controller — so two banners
/// arriving together stack exactly as they do in SwiftUI, with no modal bookkeeping.
struct BannerOverlayView: View {
    @ObservedObject var viewModel: BannerDisplayViewModel
    let onLinkTap: (String) -> Void

    var body: some View {
        ZStack {
            if let popup = viewModel.popupBanner {
                BannerChrome.popup(popup, viewModel: viewModel, onLinkTap: onLinkTap)
            }

            if let flyout = viewModel.flyoutBanner {
                BannerChrome.flyout(flyout, viewModel: viewModel, onLinkTap: onLinkTap)
            }
        }
    }
}

/// Every bar banner pinned to one screen edge, stacked in arrival order.
struct BannerBarStackView: View {
    @ObservedObject var viewModel: BannerDisplayViewModel
    let isBottom: Bool
    let onLinkTap: (String) -> Void

    private var banners: [BannerResponse] {
        viewModel.barBanners.filter { ($0.displayPosition == "bottom") == isBottom }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(banners, id: \.token) { banner in
                BannerChrome.bar(
                    banner,
                    viewModel: viewModel,
                    isBottom: isBottom,
                    safeAreaInset: 0,
                    onLinkTap: onLinkTap
                )
            }
        }
    }
}
