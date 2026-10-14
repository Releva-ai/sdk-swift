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
    /// The bar layer over the host's view, or `nil` when the presenter is stopped. Internal so a
    /// test can read where the bars were laid out.
    private(set) var barLayer: BarLayer?

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

        installBarLayer(in: host)
        viewModel.start(tracker: tracker, targetSelector: "", overlayOnly: true, onLinkTap: onLinkTap)

        // `receive(on:)` so a reconcile sees the view model's committed state: `@Published`
        // fires from `willSet`, before the property it is derived from has been assigned.
        cancellable = viewModel.$popupBanner
            .combineLatest(viewModel.$flyoutBanner, viewModel.$barBanners)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] popup, flyout, _ in
                self?.syncOverlay(isNeeded: popup != nil || flyout != nil)
                self?.matchTransition(toFlyout: flyout != nil, popup: popup != nil)
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
            // between — the subscription is cancelled above, so `syncOverlay` cannot fire — which
            // means a presenter that is never started again leaves the overlay up, the same
            // outcome as the missing `deinit` in this method's doc comment.
            controller.presentingViewController?.dismiss(animated: false)
            if controller.presentingViewController == nil {
                overlayController = nil
            }
        }

        if let barLayer = barLayer {
            barLayer.controller.willMove(toParent: nil)
            barLayer.view.removeFromSuperview()
            barLayer.controller.removeFromParent()
        }
        barLayer = nil
    }

    // MARK: - Reconciliation

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
            controller.modalTransitionStyle = viewModel.flyoutBanner != nil ? .coverVertical : .crossDissolve
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
                // `cancellable` is the started flag: a completion that lands after `stop()` must
                // not put a banner back up. Identity-checked as well, the same guard
                // `NpsPresenter.close` carries: this branch re-issues the dismiss on every
                // reconcile, so two completions can be outstanding for one controller, and the
                // first clears the reference and presents a replacement below in the same breath.
                guard let self = self, self.cancellable != nil, self.overlayController === controller else { return }
                self.overlayController = nil // it really is gone
                // A banner that arrived while the dismissal was in flight gets its overlay here:
                // `present` on a controller mid-dismissal is the one thing UIKit reliably
                // refuses, so that reconcile has to happen after the transition, not during it.
                let hasOverlay = self.viewModel.popupBanner != nil || self.viewModel.flyoutBanner != nil
                self.syncOverlay(isNeeded: hasOverlay)
            }
        }
    }

    /// The overlay comes and goes as sdk-react-native's Modal does: sliding up and down with a
    /// flyout, fading with a popup. A swap between the two keeps the overlay up and sets how it
    /// will leave.
    private func matchTransition(toFlyout flyout: Bool, popup: Bool) {
        guard flyout || popup, let controller = overlayController else { return }
        controller.modalTransitionStyle = flyout ? .coverVertical : .crossDissolve
    }

    // MARK: - Bar Banners

    /// A bar banner cannot be a modal — that would block the whole screen for a strip of
    /// chrome — so the bars are drawn in a layer over the host's view: a child view controller
    /// laying them out exactly as the overlay window does (`BannerBarLayer`), against the host
    /// view's edges and its safe area. Over a scroll view (a table or collection view controller's
    /// view) the layer covers its visible frame, so the bars do not scroll. The layer passes every
    /// touch through except on a bar's card or close control.
    struct BarLayer {
        let view: BannerBarPassThroughView
        let controller: BannerBarLayerHostingController
    }

    private func installBarLayer(in host: UIViewController) {
        let geometry = BannerBarLayerGeometry()
        let layerView = BannerBarPassThroughView()
        layerView.translatesAutoresizingMaskIntoConstraints = false
        layerView.backgroundColor = .clear

        let rootView = BannerPresenterBarView(viewModel: viewModel, geometry: geometry, onLinkTap: onLinkTap) { [weak layerView] frames in
            layerView?.interactiveFrames = frames
        }
        let controller = BannerBarLayerHostingController(rootView: rootView)
        controller.geometry = geometry
        controller.view.backgroundColor = .clear
        controller.view.isOpaque = false
        controller.view.translatesAutoresizingMaskIntoConstraints = false

        host.view.addSubview(layerView)
        host.addChild(controller)
        layerView.addSubview(controller.view)
        // A scroll view's edges are its content's; its frame guide is what stays on screen.
        let frameGuide = (host.view as? UIScrollView)?.frameLayoutGuide
        NSLayoutConstraint.activate([
            layerView.leadingAnchor.constraint(equalTo: frameGuide?.leadingAnchor ?? host.view.leadingAnchor),
            layerView.trailingAnchor.constraint(equalTo: frameGuide?.trailingAnchor ?? host.view.trailingAnchor),
            layerView.topAnchor.constraint(equalTo: frameGuide?.topAnchor ?? host.view.topAnchor),
            layerView.bottomAnchor.constraint(equalTo: frameGuide?.bottomAnchor ?? host.view.bottomAnchor),
            controller.view.leadingAnchor.constraint(equalTo: layerView.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: layerView.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: layerView.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: layerView.bottomAnchor)
        ])
        if let scrollView = host.view as? UIScrollView {
            // A scroll view gives its subviews no safe area: a hidden view pinned to its safe-area
            // guide measures it for the layer.
            let safeAreaGuide = UIView()
            safeAreaGuide.isHidden = true
            safeAreaGuide.translatesAutoresizingMaskIntoConstraints = false
            layerView.insertSubview(safeAreaGuide, at: 0)
            let guide = scrollView.safeAreaLayoutGuide
            NSLayoutConstraint.activate([
                safeAreaGuide.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
                safeAreaGuide.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
                safeAreaGuide.topAnchor.constraint(equalTo: guide.topAnchor),
                safeAreaGuide.bottomAnchor.constraint(equalTo: guide.bottomAnchor)
            ])
            layerView.safeAreaGuide = safeAreaGuide
            layerView.onSafeAreaChange = { [weak controller] insets in
                if controller?.additionalSafeAreaInsets != insets { controller?.additionalSafeAreaInsets = insets }
            }
        }
        controller.didMove(toParent: host)
        barLayer = BarLayer(view: layerView, controller: controller)
    }
}

// MARK: - Hosted Views

/// The popup and flyout layer of `BannerDisplayModifier`'s `ZStack`, without the host's content.
///
/// Both slots live in one view, and therefore one presented controller, so a popup and a flyout
/// replacing each other need no modal bookkeeping.
struct BannerOverlayView: View {
    @ObservedObject var viewModel: BannerDisplayViewModel
    let onLinkTap: (String) -> Void
    /// The last flyout shown, drawn while the overlay slides away with it after it closes.
    @State private var leavingFlyout: BannerResponse?

    var body: some View {
        // A popup taking a flyout's place replaces it at once.
        let flyout = viewModel.flyoutBanner ?? (viewModel.popupBanner == nil ? leavingFlyout : nil)
        ZStack {
            if let popup = viewModel.popupBanner {
                BannerChrome.popup(popup, viewModel: viewModel, onLinkTap: onLinkTap)
            }

            if let flyout = flyout {
                // The flyout positions itself in the whole window, so it is handed the insets this
                // reader sees and then spans the safe area too.
                GeometryReader { geometry in
                    BannerChrome.flyout(flyout, viewModel: viewModel, safeArea: geometry.safeAreaInsets, onLinkTap: onLinkTap)
                        .ignoresSafeArea()
                }
                // A flyout sliding out takes no touches.
                .allowsHitTesting(viewModel.flyoutBanner != nil)
            }
        }
        .onAppear { leavingFlyout = viewModel.flyoutBanner }
        .onChange(of: viewModel.flyoutBanner?.token) { _ in
            if let shown = viewModel.flyoutBanner { leavingFlyout = shown }
        }
        .onChange(of: viewModel.popupBanner?.token) { _ in
            if viewModel.popupBanner != nil { leavingFlyout = nil }
        }
    }
}

/// The safe-area insets of the host's view, as the bar layer covering it sees them.
@MainActor
final class BannerBarLayerGeometry: ObservableObject {
    @Published var safeArea = EdgeInsets()
}

/// Publishes its view's safe-area insets, which are the host view's, to the bar layer.
final class BannerBarLayerHostingController: UIHostingController<BannerPresenterBarView> {
    var geometry: BannerBarLayerGeometry?

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        publishSafeArea()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        publishSafeArea()
    }

    private func publishSafeArea() {
        let insets = EdgeInsets(view.safeAreaInsets)
        if geometry?.safeArea != insets { geometry?.safeArea = insets }
    }
}

/// A view that only claims touches inside `interactiveFrames`, which are in window coordinates.
final class BannerBarPassThroughView: UIView {
    var interactiveFrames: [CGRect] = []
    /// Over a scroll view: a hidden subview covering the scroll view's safe area.
    var safeAreaGuide: UIView?
    /// Called on each layout with the insets `safeAreaGuide` measures.
    var onSafeAreaChange: ((UIEdgeInsets) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let guide = safeAreaGuide?.frame else { return }
        onSafeAreaChange?(UIEdgeInsets(
            top: max(guide.minY, 0),
            left: max(guide.minX, 0),
            bottom: max(bounds.maxY - guide.maxY, 0),
            right: max(bounds.maxX - guide.maxX, 0)
        ))
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let inWindow = convert(point, to: nil)
        guard interactiveFrames.contains(where: { $0.contains(inWindow) }) else { return nil }
        return super.hitTest(point, with: event)
    }
}

/// The presenter's bar layer: the overlay window's `BannerBarLayer`, given the host view's safe
/// area, reporting the frames that claim touches.
struct BannerPresenterBarView: View {
    let viewModel: BannerDisplayViewModel
    @ObservedObject var geometry: BannerBarLayerGeometry
    let onLinkTap: (String) -> Void
    let onFramesChange: ([CGRect]) -> Void

    var body: some View {
        let safeArea = geometry.safeArea
        BannerBarLayer(viewModel: viewModel, safeArea: { safeArea }, onLinkTap: onLinkTap)
            .onPreferenceChange(BannerFramesKey.self) { onFramesChange($0) }
    }
}
