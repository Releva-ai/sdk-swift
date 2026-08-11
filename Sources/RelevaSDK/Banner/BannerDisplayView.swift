import SwiftUI
import Combine

/// A SwiftUI view modifier that wraps content and displays banners.
///
/// Usage:
/// ```swift
/// HomeView()
///     .bannerDisplay(client: relevaClient, targetSelector: "#home-content") { url in
///         handleDeepLink(url)
///     }
/// ```
public struct BannerDisplayModifier: ViewModifier {
    let client: RelevaClient
    let targetSelector: String
    let onLinkTap: (String) -> Void

    @StateObject private var viewModel = BannerDisplayViewModel()

    public func body(content: Content) -> some View {
        ZStack {
            // Main content with static banners
            VStack(spacing: 0) {
                // afterbegin static banners
                ForEach(viewModel.staticBannersBeforeContent, id: \.token) { banner in
                    bannerContentView(for: banner)
                }

                // Original content
                if !viewModel.hasReplaceBanner {
                    content
                } else {
                    // Replace banner
                    ForEach(viewModel.replaceBanners, id: \.token) { banner in
                        bannerContentView(for: banner)
                    }
                }

                // beforeend / afterend static banners
                ForEach(viewModel.staticBannersAfterContent, id: \.token) { banner in
                    bannerContentView(for: banner)
                }
            }

            // Bar banners (overlay)
            ForEach(viewModel.barBanners, id: \.token) { banner in
                barBannerView(for: banner)
            }

            // Popup overlay
            if let popup = viewModel.popupBanner {
                BannerChrome.popup(popup, viewModel: viewModel, onLinkTap: onLinkTap)
            }

            // Flyout overlay
            if let flyout = viewModel.flyoutBanner {
                BannerChrome.flyout(flyout, viewModel: viewModel, onLinkTap: onLinkTap)
            }
        }
        .onAppear {
            viewModel.start(tracker: client, targetSelector: targetSelector, onLinkTap: onLinkTap)
        }
        .onDisappear {
            viewModel.stop()
        }
    }

    // MARK: - Banner Content View

    @ViewBuilder
    private func bannerContentView(for banner: BannerResponse) -> some View {
        if let design = banner.design {
            DesignRenderer.render(design: design, maxWidth: UIScreen.main.bounds.width) { url in
                viewModel.trackClick(banner)
                onLinkTap(url)
            }
        }
    }

    // MARK: - Bar Banner

    @ViewBuilder
    private func barBannerView(for banner: BannerResponse) -> some View {
        let isBottom = banner.displayPosition == "bottom"

        GeometryReader { geometry in
            VStack {
                if isBottom { Spacer() }

                BannerChrome.bar(
                    banner,
                    viewModel: viewModel,
                    isBottom: isBottom,
                    safeAreaInset: isBottom ? geometry.safeAreaInsets.bottom : geometry.safeAreaInsets.top,
                    onLinkTap: onLinkTap
                )

                if !isBottom { Spacer() }
            }
        }
        .edgesIgnoringSafeArea(isBottom ? .bottom : .top)
    }
}

// MARK: - View Extension

extension View {
    /// Add banner display capability to this view.
    /// - Parameters:
    ///   - client: The RelevaClient instance
    ///   - targetSelector: CSS selector for static banner targeting (e.g., "#home-content")
    ///   - onLinkTap: Callback when a banner link is tapped. Required — apps must handle link navigation.
    public func bannerDisplay(
        client: RelevaClient,
        targetSelector: String,
        onLinkTap: @escaping (String) -> Void
    ) -> some View {
        self.modifier(BannerDisplayModifier(
            client: client,
            targetSelector: targetSelector,
            onLinkTap: onLinkTap
        ))
    }
}

// MARK: - Tracking Seam

/// The part of `RelevaClient` that banner display uses.
///
/// `RelevaClient` builds its own `NetworkService` over `URLSession.shared`, so a test that
/// handed one to a view model or presenter would perform real network I/O. This protocol lets
/// a test substitute a spy instead. It is internal: `RelevaClient`'s public surface is unchanged.
@MainActor
protocol BannerTracker: AnyObject {
    func bannerImpression(_ banner: BannerResponse)
    func bannerAction(_ banner: BannerResponse, action: String)
}

extension RelevaClient: BannerTracker {}

// MARK: - ViewModel

@MainActor
class BannerDisplayViewModel: ObservableObject {
    @Published var staticBannersBeforeContent: [BannerResponse] = []
    @Published var staticBannersAfterContent: [BannerResponse] = []
    @Published var replaceBanners: [BannerResponse] = []
    @Published var barBanners: [BannerResponse] = []
    @Published var popupBanner: BannerResponse?
    @Published var flyoutBanner: BannerResponse?

    var hasReplaceBanner: Bool { !replaceBanners.isEmpty }

    /// Display types that do not need a place in the host's view hierarchy, and so can be
    /// shown by an overlay-only surface such as `BannerPresenter`.
    private static let overlayDisplayTypes: Set<String> = ["popup", "flyout", "bar"]

    private var tracker: BannerTracker?
    private var targetSelector: String = ""
    private var overlayOnly = false
    private var onLinkTap: ((String) -> Void)?
    private var cancellable: AnyCancellable?
    private var displayedBanners = Set<String>()

    /// - Parameter overlayOnly: when `true`, static and replace banners are dropped instead of
    ///   being collected into `staticBannersBeforeContent` and friends. `BannerPresenter` sets
    ///   this because it has nowhere to put a banner that belongs inline in the host's content,
    ///   and counting an impression for a banner that is never drawn would be a false report.
    func start(
        tracker: BannerTracker,
        targetSelector: String,
        overlayOnly: Bool = false,
        onLinkTap: ((String) -> Void)?
    ) {
        self.tracker = tracker
        self.targetSelector = targetSelector
        self.overlayOnly = overlayOnly
        self.onLinkTap = onLinkTap

        cancellable = BannerDisplayController.shared.bannerPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] banner in
                self?.handleBanner(banner)
            }
    }

    func stop() {
        cancellable?.cancel()
        cancellable = nil
    }

    private func handleBanner(_ banner: BannerResponse) {
        guard shouldDisplay(banner) else { return }
        guard !displayedBanners.contains(banner.token) else { return }
        displayedBanners.insert(banner.token)

        switch banner.displayType {
        case "popup":
            popupBanner = banner
        case "flyout":
            flyoutBanner = banner
        case "bar":
            barBanners.append(banner)
        case "static":
            addStaticBanner(banner)
        default:
            addStaticBanner(banner)
        }

        trackImpression(banner)
    }

    private func shouldDisplay(_ banner: BannerResponse) -> Bool {
        guard banner.design != nil else { return false }
        guard banner.displayType != "custom" else { return false }
        if overlayOnly { return Self.overlayDisplayTypes.contains(banner.displayType ?? "") }
        if banner.displayType == "static" && banner.cssSelector != targetSelector { return false }
        return true
    }

    private func addStaticBanner(_ banner: BannerResponse) {
        let strategy = banner.displayStrategy ?? "afterbegin"
        switch strategy {
        case "afterbegin":
            staticBannersBeforeContent.append(banner)
        case "beforeend", "afterend":
            staticBannersAfterContent.append(banner)
        case "replace":
            replaceBanners.append(banner)
        default:
            staticBannersAfterContent.append(banner)
        }
    }

    // MARK: - Dismiss

    func dismissPopup(_ banner: BannerResponse, track: Bool = true) {
        popupBanner = nil
        displayedBanners.remove(banner.token)
        if track { trackDismiss(banner) }
    }

    func dismissFlyout(_ banner: BannerResponse, track: Bool = true) {
        flyoutBanner = nil
        displayedBanners.remove(banner.token)
        if track { trackDismiss(banner) }
    }

    func dismissBar(_ banner: BannerResponse) {
        barBanners.removeAll { $0.token == banner.token }
        displayedBanners.remove(banner.token)
        trackDismiss(banner)
    }

    // MARK: - Tracking

    func trackImpression(_ banner: BannerResponse) {
        guard let tracker = tracker else { return }
        tracker.bannerImpression(banner)
    }

    func trackClick(_ banner: BannerResponse) {
        guard let tracker = tracker else { return }
        tracker.bannerAction(banner, action: "bannerClick")
    }

    func trackDismiss(_ banner: BannerResponse) {
        guard let tracker = tracker else { return }
        tracker.bannerAction(banner, action: "bannerClose")
    }
}
