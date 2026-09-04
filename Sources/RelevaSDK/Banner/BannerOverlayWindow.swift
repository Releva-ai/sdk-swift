import SwiftUI
import UIKit
import Combine

/// Hosts the overlay banners (popup, flyout, bar) of the SwiftUI `bannerDisplay` modifier in a
/// window of their own, above the app's navigation and tab bars.
///
/// Drawing them inside the modified view put them *under* `NavigationStack`'s bar: the title
/// and toolbar buttons rendered on top of a bar banner and stayed tappable (device run 21). The
/// web SDK positions these banners `fixed` over the whole page, and this is the UIKit equivalent.
/// Static banners stay inline in the host view; only the three overlay types move here.
///
/// The window passes touches through wherever no banner is drawn, so the app remains fully
/// usable around a bar or flyout. A popup covers the screen with its dimmed overlay and takes
/// every touch, as before.
@MainActor
final class BannerOverlayHost: ObservableObject {
    static let shared = BannerOverlayHost()

    @Published private(set) var viewModel: BannerDisplayViewModel?
    private(set) var onLinkTap: (String) -> Void = { _ in }

    /// The overlay window's safe-area insets, published from UIKit's layout pass because a
    /// `GeometryReader` that ignores the safe area has reported zero on the device.
    @Published fileprivate(set) var safeAreaInsets: UIEdgeInsets = .zero

    /// Screen-space frames of the bars and flyout currently drawn; touches outside them fall
    /// through to the app. Updated by `BannerOverlayRoot` from a preference.
    var interactiveFrames: [CGRect] = []
    /// `true` while a popup is shown: its overlay owns the whole screen.
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

    /// A started view model got a banner to show. If it is not the attached one — SwiftUI can
    /// fire a screen's onDisappear during launch while tabs and navigation settle, which
    /// detached it (device run 25: impression tracked, window never shown) — attach it again;
    /// a screen that is really gone has called stop() and receives nothing.
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

    /// The overlay window is a separate view hierarchy, so it does not inherit a colour scheme
    /// the app forces on its own window. Copy the app window's resolved style so the strip
    /// colours and the status bar match the app (device run 22: the overlay came up light
    /// over a dark app).
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
                // A banner arrived before any scene was connected at attach time (device run
                // 24: impression tracked, nothing on screen). Try again now.
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
private struct BannerFramesKey: PreferenceKey {
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

private extension View {
    func reportBannerFrame() -> some View {
        background(
            GeometryReader { geometry in
                Color.clear.preference(key: BannerFramesKey.self, value: [geometry.frame(in: .global)])
            }
        )
    }
}

/// The root view of the overlay window: bars pinned to the screen edges, then the popup and
/// flyout, all drawn with the same `BannerChrome` views the presenter uses.
struct BannerOverlayRoot: View {
    @ObservedObject var host: BannerOverlayHost

    var body: some View {
        // Not `ignoresSafeArea()` here: the popup and flyout centre their card inside the safe
        // area (their dimmed overlay extends past it on its own), so a tall card never puts its
        // close button under the status bar. The bars pin themselves to the screen edges below.
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

    private var topBars: [BannerResponse] { viewModel.barBanners.filter { $0.displayPosition != "bottom" } }
    private var bottomBars: [BannerResponse] { viewModel.barBanners.filter { $0.displayPosition == "bottom" } }

    var body: some View {
        ZStack {
            if !topBars.isEmpty {
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        ForEach(topBars, id: \.token) { banner in
                            BannerChrome.bar(
                                banner,
                                viewModel: viewModel,
                                isBottom: false,
                                safeAreaInset: host.safeAreaInsets.top,
                                width: geometry.size.width,
                                onLinkTap: host.onLinkTap
                            )
                        }
                    }
                    .reportBannerFrame()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .ignoresSafeArea()
            }

            if !bottomBars.isEmpty {
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        ForEach(bottomBars, id: \.token) { banner in
                            BannerChrome.bar(
                                banner,
                                viewModel: viewModel,
                                isBottom: true,
                                safeAreaInset: host.safeAreaInsets.bottom,
                                width: geometry.size.width,
                                onLinkTap: host.onLinkTap
                            )
                        }
                    }
                    .reportBannerFrame()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
                .ignoresSafeArea()
            }

            if let flyout = viewModel.flyoutBanner {
                BannerChrome.flyout(flyout, viewModel: viewModel, onLinkTap: host.onLinkTap)
                    .reportBannerFrame()
            }

            if let popup = viewModel.popupBanner {
                BannerChrome.popup(popup, viewModel: viewModel, onLinkTap: host.onLinkTap)
            }
        }
        .onAppear { host.coversScreen = viewModel.popupBanner != nil }
        .onChange(of: viewModel.popupBanner?.token) { _ in
            host.coversScreen = viewModel.popupBanner != nil
        }
    }
}
