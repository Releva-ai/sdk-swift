import SwiftUI
import UIKit
import Combine

/// Hosts the overlay banners (popup, flyout, bar) of the SwiftUI `bannerDisplay` modifier in a
/// window of their own, above the app's navigation and tab bars.
///
/// Drawn inside the modified view they would sit under `NavigationStack`'s bar. The web SDK
/// positions these banners `fixed` over the whole page; this is the UIKit equivalent. Static
/// banners stay inline in the host view.
///
/// The window passes touches through wherever no banner is drawn. A popup or a flyout covers the
/// screen with its dimmed overlay and takes every touch.
@MainActor
final class BannerOverlayHost: ObservableObject {
    static let shared = BannerOverlayHost()

    @Published private(set) var viewModel: BannerDisplayViewModel?
    private(set) var onLinkTap: (String) -> Void = { _ in }

    /// The overlay window's safe-area insets, published from UIKit's layout pass; a
    /// `GeometryReader` that ignores the safe area can report zero.
    @Published fileprivate(set) var safeAreaInsets: UIEdgeInsets = .zero

    /// Screen-space frames of the bar cards, their close controls and the flyout card currently
    /// drawn; touches outside them fall through to the app. Updated by `BannerOverlayRoot` from a
    /// preference.
    var interactiveFrames: [CGRect] = []
    /// `true` while a popup or a flyout is shown: its overlay owns the whole screen.
    var coversScreen = false

    private var window: BannerOverlayWindow?
    private var cancellable: AnyCancellable?
    private var sceneObserver: AnyCancellable?

    private init() {
        // On a cold launch the first screen can appear before any scene reports itself
        // connected, so the window is also (re)created when a scene activates.
        sceneObserver = NotificationCenter.default.publisher(for: UIScene.didActivateNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.ensureWindow()
                self.mirrorAppearance()
                self.updateVisibility()
            }
    }

    /// The modifier calls this on appear. The last attached view model is the one drawn.
    func attach(_ viewModel: BannerDisplayViewModel, onLinkTap: @escaping (String) -> Void) {
        if self.viewModel !== viewModel {
            relevaLog("RelevaSDK: BannerOverlay - attached view model \(ObjectIdentifier(viewModel).hashValue)")
        }
        self.viewModel = viewModel
        self.onLinkTap = onLinkTap
        cancellable = viewModel.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateVisibility() }
        ensureWindow()
        mirrorAppearance()
        updateVisibility()
    }

    /// The modifier calls this on disappear. Only the active view model is detached, so a
    /// screen leaving behind another that attached later does not blank the overlay.
    func detach(_ viewModel: BannerDisplayViewModel) {
        guard self.viewModel === viewModel else { return }
        relevaLog("RelevaSDK: BannerOverlay - detached view model \(ObjectIdentifier(viewModel).hashValue)")
        self.viewModel = nil
        cancellable = nil
        interactiveFrames = []
        coversScreen = false
        updateVisibility()
    }

    /// A started view model got a banner to show. If it is not the attached one (SwiftUI can fire a
    /// screen's onDisappear during launch while tabs and navigation settle), attach it again; a
    /// screen that is really gone has called stop() and receives nothing.
    func contentChanged(in viewModel: BannerDisplayViewModel, onLinkTap: ((String) -> Void)?) {
        if self.viewModel !== viewModel {
            relevaLog("RelevaSDK: BannerOverlay - banner arrived on a detached view model, re-attaching")
            attach(viewModel, onLinkTap: onLinkTap ?? { _ in })
        } else {
            updateVisibility()
        }
    }

    private func ensureWindow() {
        if let window = window, window.windowScene != nil { return }

        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else {
            relevaLog("RelevaSDK: BannerOverlay - no window scene connected yet, overlay window deferred")
            return
        }

        let window = BannerOverlayWindow(windowScene: scene)
        window.host = self
        // Just above the app's own window; system UI stays above us.
        window.windowLevel = .normal + 1
        window.backgroundColor = .clear

        let controller = BannerOverlayHostingController(rootView: BannerOverlayRoot(host: self))
        controller.host = self
        controller.view.backgroundColor = .clear
        controller.view.isOpaque = false
        window.rootViewController = controller
        self.window = window
        mirrorAppearance()
        relevaLog("RelevaSDK: BannerOverlay - window created on scene (state \(scene.activationState.rawValue))")
    }

    /// The overlay window does not inherit a colour scheme the app forces on its own window; copy
    /// the app window's resolved style so the strip colours and the status bar match.
    private func mirrorAppearance() {
        guard let window = window else { return }
        let appWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0 !== window && $0.isKeyWindow }
        window.overrideUserInterfaceStyle = appWindow?.traitCollection.userInterfaceStyle ?? .unspecified
    }

    /// Hidden whenever nothing is drawn, so an idle overlay window cannot get in the way.
    private func updateVisibility() {
        // `objectWillChange` fires before the published values change; read them on the next
        // turn of the run loop so the decision sees the new state.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let shown: [String] = {
                guard let vm = self.viewModel else { return [] }
                return [vm.popupBanner.map { "popup \($0.token)" }, vm.flyoutBanner.map { "flyout \($0.token)" }]
                    .compactMap { $0 } + vm.barBanners.map { "bar \($0.token)" }
            }()
            let hasContent = !shown.isEmpty
            if hasContent && self.window == nil {
                // A banner arrived before any scene was connected at attach time; try again now.
                self.ensureWindow()
                self.mirrorAppearance()
            }
            guard let window = self.window else {
                if hasContent { relevaLog("RelevaSDK: BannerOverlay - \(shown.joined(separator: ", ")) pending, no window yet") }
                return
            }
            if window.isHidden == hasContent {
                relevaLog("RelevaSDK: BannerOverlay - \(hasContent ? "showing" : "hiding") window (\(shown.joined(separator: ", ")))")
            }
            window.isHidden = !hasContent
        }
    }
}

/// Publishes the safe-area insets to the host and keeps the status bar as the app has it.
final class BannerOverlayHostingController: UIHostingController<BannerOverlayRoot> {
    weak var host: BannerOverlayHost?

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        host?.safeAreaInsets = view.safeAreaInsets
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if host?.safeAreaInsets != view.safeAreaInsets { host?.safeAreaInsets = view.safeAreaInsets }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .default }
}

/// A window that only claims touches where a banner is drawn.
final class BannerOverlayWindow: UIWindow {
    weak var host: BannerOverlayHost?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let host = host else { return nil }
        let claims = host.coversScreen || host.interactiveFrames.contains { $0.contains(point) }
        guard claims else { return nil }
        return super.hitTest(point, with: event)
    }
}

/// Collects the screen-space frames of the overlay banners for `BannerOverlayWindow.hitTest`.
struct BannerFramesKey: PreferenceKey {
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    /// Registers this view's screen-space frame as touch-claiming for `BannerOverlayWindow`.
    func reportBannerFrame() -> some View {
        background(
            GeometryReader { geometry in
                Color.clear.preference(key: BannerFramesKey.self, value: [geometry.frame(in: .global)])
            }
        )
    }
}

/// The root view of the overlay window: bars pinned below the status bar and to the screen's
/// bottom edge, then the popup and flyout, all drawn with the same `BannerChrome` views the
/// presenter uses.
struct BannerOverlayRoot: View {
    @ObservedObject var host: BannerOverlayHost

    var body: some View {
        // Not `ignoresSafeArea()` here: the popup centres its card inside the safe area (its
        // dimmed overlay extends past it on its own), so a tall card never puts its close button
        // under the status bar. The bars and the flyout position themselves in the whole window.
        ZStack {
            if let viewModel = host.viewModel {
                BannerOverlayContent(viewModel: viewModel, host: host)
            }
        }
        .onPreferenceChange(BannerFramesKey.self) { frames in
            host.interactiveFrames = frames
        }
    }
}

private struct BannerOverlayContent: View {
    @ObservedObject var viewModel: BannerDisplayViewModel
    let host: BannerOverlayHost

    /// The bars at each placement, in arrival order.
    private func bars(at anchor: BannerCardStyle.Anchor) -> [BannerResponse] {
        viewModel.barBanners.filter { BannerCardStyle.barVerticalAnchor($0) == anchor }
    }

    var body: some View {
        ZStack {
            if !viewModel.barBanners.isEmpty {
                // Bars are positioned in the window below the status bar, as sdk-react-native
                // positions them in the host's content, which starts below it on iOS: top bars
                // stacked down from the safe-area top, bottom bars up from the window's bottom
                // edge, a centred bar in a layer spanning that height. Only the bottom bar flush
                // with the edge meets the system UI, and pads by the home indicator inside its
                // card. Percentages resolve against the window, as sdk-react-native's do.
                GeometryReader { geometry in
                    let safeArea = BannerChrome.barSafeArea(host.safeAreaInsets)
                    let top = bars(at: .start)
                    let bottom = bars(at: .end)
                    ZStack {
                        VStack(spacing: 0) {
                            ForEach(Array(top.enumerated()), id: \.element.token) { index, banner in
                                bar(banner, in: geometry.size, safeArea: safeArea, touchesEdge: index == 0)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                        ForEach(bars(at: .center), id: \.token) { banner in
                            bar(banner, in: geometry.size, safeArea: safeArea, touchesEdge: false)
                        }

                        VStack(spacing: 0) {
                            ForEach(Array(bottom.enumerated()), id: \.element.token) { index, banner in
                                bar(banner, in: geometry.size, safeArea: safeArea, touchesEdge: index == bottom.count - 1)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    }
                    .padding(.top, safeArea.top)
                }
                .ignoresSafeArea()
            }

            if let flyout = viewModel.flyoutBanner {
                // Spans the window with its dimmed overlay.
                BannerChrome.flyout(
                    flyout,
                    viewModel: viewModel,
                    safeArea: EdgeInsets(host.safeAreaInsets),
                    onLinkTap: host.onLinkTap
                )
                .ignoresSafeArea()
            }

            if let popup = viewModel.popupBanner {
                BannerChrome.popup(popup, viewModel: viewModel, onLinkTap: host.onLinkTap)
            }
        }
        .onAppear { host.coversScreen = coversScreen }
        .onChange(of: viewModel.popupBanner?.token) { _ in host.coversScreen = coversScreen }
        .onChange(of: viewModel.flyoutBanner?.token) { _ in host.coversScreen = coversScreen }
    }

    private var coversScreen: Bool { viewModel.popupBanner != nil || viewModel.flyoutBanner != nil }

    /// - Parameter safeArea: the window's; the bars' box starts at its top, so no bar meets it there.
    private func bar(_ banner: BannerResponse, in container: CGSize, safeArea: EdgeInsets, touchesEdge: Bool) -> some View {
        BannerChrome.bar(
            banner,
            viewModel: viewModel,
            layout: BarCardLayout(
                style: BannerCardStyle(banner),
                displayPosition: banner.displayPosition,
                container: container,
                safeArea: EdgeInsets(top: 0, leading: safeArea.leading, bottom: safeArea.bottom, trailing: safeArea.trailing),
                touchesEdge: touchesEdge
            ),
            containerWidth: container.width,
            onLinkTap: host.onLinkTap
        )
    }
}

extension EdgeInsets {
    init(_ insets: UIEdgeInsets) {
        self.init(top: insets.top, leading: insets.left, bottom: insets.bottom, trailing: insets.right)
    }
}
