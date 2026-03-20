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
                popupBannerView(for: popup)
            }

            // Flyout overlay
            if let flyout = viewModel.flyoutBanner {
                flyoutBannerView(for: flyout)
            }
        }
        .onAppear {
            viewModel.start(client: client, targetSelector: targetSelector, onLinkTap: onLinkTap)
        }
        .onDisappear {
            viewModel.stop()
        }
    }

    // MARK: - Banner Content View

    @ViewBuilder
    private func bannerContentView(for banner: BannerResponse) -> some View {
        if let design = banner.design {
            DesignRenderer.render(design: design, maxWidth: UIScreen.main.bounds.width, onLinkTap: { url in
                viewModel.trackClick(banner)
                onLinkTap(url)
            })
        }
    }

    // MARK: - Bar Banner

    @ViewBuilder
    private func barBannerView(for banner: BannerResponse) -> some View {
        let isBottom = banner.displayPosition == "bottom"

        VStack {
            if isBottom { Spacer() }

            ZStack(alignment: .topTrailing) {
                if let design = banner.design {
                    DesignRenderer.render(
                        design: design,
                        maxWidth: UIScreen.main.bounds.width - 32,
                        onLinkTap: { url in
                            viewModel.trackClick(banner)
                            onLinkTap(url)
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                closeButton(for: banner, size: 24) {
                    viewModel.dismissBar(banner)
                }
                .offset(x: 4, y: -4)
            }
            .background(Color.white)
            .shadow(radius: 5)

            if !isBottom { Spacer() }
        }
        .edgesIgnoringSafeArea(isBottom ? .bottom : .top)
    }

    // MARK: - Popup Banner

    @ViewBuilder
    private func popupBannerView(for banner: BannerResponse) -> some View {
        let bodyValues = DesignRenderer.getDesignBodyValues(banner)
        let overlayColor = getOverlayColor(banner)
        let bgImageMap = bodyValues["backgroundImage"] as? [String: Any]
        let hasBodyBgImage = bgImageMap != nil && !(bgImageMap?["url"] as? String ?? "").isEmpty
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height

        ZStack {
            // Overlay
            overlayColor
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    viewModel.dismissPopup(banner)
                }

            // Full-screen popup
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        if let design = banner.design {
                            DesignRenderer.render(
                                design: design,
                                maxWidth: screenWidth,
                                onLinkTap: { url in
                                    viewModel.dismissPopup(banner, track: false)
                                    viewModel.trackClick(banner)
                                    onLinkTap(url)
                                }
                            )
                        }
                    }
                    .frame(minHeight: geometry.size.height)
                }
            }
            .frame(width: screenWidth, height: screenHeight)
            .edgesIgnoringSafeArea(.all)

            // Close button overlaid at top-right
            VStack {
                HStack {
                    Spacer()
                    closeButton(for: banner, size: 32) {
                        viewModel.dismissPopup(banner)
                    }
                    .padding(8)
                }
                Spacer()
            }
        }
    }

    // MARK: - Flyout Banner

    @ViewBuilder
    private func flyoutBannerView(for banner: BannerResponse) -> some View {
        let bodyValues = DesignRenderer.getDesignBodyValues(banner)
        let bgImageMap = bodyValues["backgroundImage"] as? [String: Any]
        let hasBodyBgImage = bgImageMap != nil && !(bgImageMap?["url"] as? String ?? "").isEmpty
        let overlayColor = getOverlayColor(banner)
        let isLeft = banner.displayPosition == "left"
        let flyoutWidth = UIScreen.main.bounds.width * 0.8

        ZStack {
            // Overlay
            overlayColor
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    viewModel.dismissFlyout(banner)
                }

            HStack(spacing: 0) {
                if !isLeft { Spacer() }

                VStack(spacing: 0) {
                    // Close button on outer edge
                    HStack {
                        if isLeft { Spacer() }
                        closeButton(for: banner, size: 32) {
                            viewModel.dismissFlyout(banner)
                        }
                        .padding(8)
                        if !isLeft { Spacer() }
                    }

                    // Scrollable content
                    ScrollView {
                        if let design = banner.design {
                            DesignRenderer.render(
                                design: design,
                                maxWidth: flyoutWidth,
                                transparentBody: hasBodyBgImage,
                                onLinkTap: { url in
                                    viewModel.dismissFlyout(banner, track: false)
                                    viewModel.trackClick(banner)
                                    onLinkTap(url)
                                }
                            )
                        }
                    }
                }
                .frame(width: flyoutWidth)
                .background(
                    Group {
                        if hasBodyBgImage, let bgInfo = DesignRenderer.parseBackgroundImage(bgImageMap, forceCover: true) {
                            AsyncImage(url: bgInfo.url) { phase in
                                if case .success(let image) = phase {
                                    image.resizable().aspectRatio(contentMode: bgInfo.contentMode)
                                }
                            }
                        } else {
                            Color.white
                        }
                    }
                )
                .shadow(radius: 10)

                if isLeft { Spacer() }
            }
            .edgesIgnoringSafeArea(.all)
        }
    }

    // MARK: - Close Button

    @ViewBuilder
    private func closeButton(for banner: BannerResponse, size: CGFloat, action: @escaping () -> Void) -> some View {
        let bodyValues = DesignRenderer.getDesignBodyValues(banner)

        let bgColor = DesignRenderer.parseColor(bodyValues["popupCloseButton_backgroundColor"])
            ?? DesignRenderer.parseColor(banner.cssStyles["closeButtonBackgroudColor"])
            ?? .white
        let iconColor = DesignRenderer.parseColor(bodyValues["popupCloseButton_iconColor"])
            ?? DesignRenderer.parseColor(banner.cssStyles["closeButtonColor"])
            ?? Color(white: 0.3)
        let borderColor = DesignRenderer.parseColor(banner.cssStyles["closeButtonBorder"])
            ?? Color(white: 0.8)

        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(bgColor)
                        .overlay(Circle().stroke(borderColor, lineWidth: 1))
                )
        }
    }

    // MARK: - Helpers

    private func getOverlayColor(_ banner: BannerResponse) -> Color {
        let bodyValues = DesignRenderer.getDesignBodyValues(banner)
        if let color = DesignRenderer.parseColor(bodyValues["popupOverlay_backgroundColor"]) { return color }
        if let color = DesignRenderer.parseColor(banner.cssStyles["overlayColor"]) { return color }
        return Color.black.opacity(0.5)
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

// MARK: - ViewModel

class BannerDisplayViewModel: ObservableObject {
    @Published var staticBannersBeforeContent: [BannerResponse] = []
    @Published var staticBannersAfterContent: [BannerResponse] = []
    @Published var replaceBanners: [BannerResponse] = []
    @Published var barBanners: [BannerResponse] = []
    @Published var popupBanner: BannerResponse?
    @Published var flyoutBanner: BannerResponse?

    var hasReplaceBanner: Bool { !replaceBanners.isEmpty }

    private var client: RelevaClient?
    private var targetSelector: String = ""
    private var onLinkTap: ((String) -> Void)?
    private var cancellable: AnyCancellable?
    private var displayedBanners = Set<String>()

    func start(client: RelevaClient, targetSelector: String, onLinkTap: ((String) -> Void)?) {
        self.client = client
        self.targetSelector = targetSelector
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
        guard let client = client else { return }
        client.bannerImpression(banner)
    }

    func trackClick(_ banner: BannerResponse) {
        guard let client = client else { return }
        client.bannerAction(banner, action: "bannerClick")
    }

    func trackDismiss(_ banner: BannerResponse) {
        guard let client = client else { return }
        client.bannerAction(banner, action: "bannerClose")
    }
}
