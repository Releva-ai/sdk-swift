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
    /// The presented overlay, or `nil` when nothing is up. Internal rather than private so a
    /// test can assert on what the presenter put up and then let go of — UIKit's own transitions
    /// do not complete in this package's test host, so the presenter's side of a dismissal is
    /// observable there and UIKit's is not.
    private(set) var overlayController: UIHostingController<BannerOverlayView>?
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
    /// / `stop()` with the host's appearance callbacks as shown above to avoid that. A `stop()`
    /// whose dismissal UIKit declines lands in the same place when the presenter is never started
    /// again, which a nav pop during the overlay's brief `.crossDissolve` reaches: a pop is not a
    /// dismissal, so it is not refused the way that dismiss was, and the overlay is presented from
    /// a context above the popped host — typically the `UINavigationController` — so it stays on
    /// screen while the host and this presenter go.
    public func stop() {
        cancellable?.cancel()
        cancellable = nil
        viewModel.stop()

        if let controller = overlayController {
            // Only let go of the reference once UIKit has actually taken the overlay down: a
            // controller still `isBeingPresented` (reachable if `stop()` runs mid-transition, on
            // a fast tab switch) declines `dismiss` and only logs, so clearing `overlayController`
            // unconditionally here would orphan it on screen with nothing left to reach it. What
            // recovers from a declined dismissal is the next `start()` *of this presenter*: the
            // reference is still the live one, so its first reconcile keeps the overlay and the
            // presenter can take it down again when the banner is closed. Nothing runs in
            // between — the subscription is cancelled above, so `reconcile` cannot fire — which
            // means a presenter that is never started again leaves the overlay up, the same
            // outcome as the missing `deinit` in this method's doc comment.
            controller.presentingViewController?.dismiss(animated: false)
            if controller.presentingViewController == nil {
                overlayController = nil
            }
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

    /// Puts the overlay up or takes it down so that what is on screen matches the view model.
    ///
    /// Deliberately keeps no state of its own beyond `overlayController`: every decision below
    /// is read back from UIKit, so there is no flag that can disagree with what is actually
    /// presented. In particular a `present` UIKit declines — it only logs, it does not throw —
    /// leaves an `overlayController` whose `presentingViewController` is `nil`, which the next
    /// reconcile drops and retries rather than treating as already on screen. Reaching the
    /// screen sooner than that would mean waiting out whichever animated transition got in the
    /// way, and this package has no way to exercise that path in a test (see
    /// `PresentationTestSupport.makeVisibleWindow`), so it is a documented limitation rather
    /// than unverified code.
    private func syncOverlay(isNeeded: Bool) {
        if isNeeded {
            if let existing = overlayController, existing.presentingViewController == nil {
                // Either the last `present` never took, or something else (an app modal above
                // the overlay, say) already dismissed it. Nothing to reuse; drop it so the
                // block below tries again instead of no-oping forever on the guard.
                overlayController = nil
            }
            guard overlayController == nil, let host = host else { return }

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

            // Nil when the presentation never took or something else already took the overlay
            // down — nothing to dismiss then, and nothing to clean up either.
            guard let presenting = controller.presentingViewController else {
                overlayController = nil
                return
            }

            // Only let go of the reference from the dismiss completion — the one place that
            // knows the dismissal actually happened. A controller still `isBeingPresented` (the
            // user taps close as it fades in, or the host's `viewWillDisappear` fires on a fast
            // tab switch, both inside the brief `.crossDissolve`) declines `dismiss` and only
            // logs; clearing `overlayController` up front, as before, would then leave nothing
            // able to reach the orphaned overlay ever again. If the dismissal is declined here,
            // this completion never runs, `overlayController` stays set, and the next reconcile
            // either finds it still presented (re-issuing the dismiss when not needed) or finds
            // `presentingViewController == nil` by then and drops it via the guard above.
            presenting.dismiss(animated: true) { [weak self] in
                // `cancellable` is the started flag: a completion that lands after `stop()`
                // must not put a banner back up.
                guard let self = self, self.cancellable != nil else { return }
                self.overlayController = nil // it really is gone
                // A banner that arrived while the dismissal was in flight gets its overlay here:
                // `present` on a controller mid-dismissal is the one thing UIKit reliably
                // refuses, so that reconcile has to happen after the transition, not during it.
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
    /// changes. A no-op from iOS 16 up, where every slot's `heightConstraint` is `nil` — checked
    /// before forcing layout below, so the modern path is not made to pay for a measurement it
    /// has no use for on every reconcile (every popup show, dismissal and bar add/remove).
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
        guard barSlots.contains(where: { $0.heightConstraint != nil }), let host = host else { return }
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
