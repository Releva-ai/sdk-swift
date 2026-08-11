import SwiftUI

/// The chrome around a rendered banner design: the dimmed overlay, the close button, and the
/// popup/flyout/bar framing.
///
/// This was private to `BannerDisplayModifier`. It moved here unchanged so `BannerPresenter`
/// can put the very same views inside a `UIHostingController` rather than growing a second,
/// UIKit-native renderer that would drift from the SwiftUI one. Every gesture routes back
/// through `BannerDisplayViewModel`, which is the single place that reports impressions,
/// clicks and dismissals to `RelevaClient`.
///
/// `@MainActor` because `BannerDisplayModifier` — a `ViewModifier`, which is `@MainActor` by
/// protocol — used to provide that isolation for free. A bare `enum` gets no such inference,
/// and the closures below call main-actor-isolated `BannerDisplayViewModel` methods.
@MainActor
enum BannerChrome {

    // MARK: - Popup Banner

    @ViewBuilder
    static func popup(
        _ banner: BannerResponse,
        viewModel: BannerDisplayViewModel,
        onLinkTap: @escaping (String) -> Void
    ) -> some View {
        let overlayColor = getOverlayColor(banner)
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
    static func flyout(
        _ banner: BannerResponse,
        viewModel: BannerDisplayViewModel,
        onLinkTap: @escaping (String) -> Void
    ) -> some View {
        let bodyValues = DesignRenderer.getDesignBodyValues(banner)
        let bgImageMap = bodyValues["backgroundImage"]
        let hasBodyBgImage = !(bgImageMap?["url"]?.stringValue ?? "").isEmpty
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

    // MARK: - Bar Banner

    /// The bar itself, without the positioning that puts it at the top or bottom of the
    /// screen: the SwiftUI modifier pins it with a `GeometryReader` and `Spacer`, while
    /// `BannerPresenter` pins it with layout constraints on a child view controller.
    /// - Parameter safeAreaInset: extra padding on the screen-edge side. The modifier reads
    ///   this off its `GeometryReader` because it draws past the safe area; a presenter that
    ///   constrains to the safe area passes `0`.
    @ViewBuilder
    static func bar(
        _ banner: BannerResponse,
        viewModel: BannerDisplayViewModel,
        isBottom: Bool,
        safeAreaInset: CGFloat,
        onLinkTap: @escaping (String) -> Void
    ) -> some View {
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
                .padding(isBottom ? .bottom : .top, safeAreaInset)
            }

            closeButton(for: banner, size: 24) {
                viewModel.dismissBar(banner)
            }
            .offset(x: 4, y: -4)
            .padding(isBottom ? .bottom : .top, safeAreaInset)
        }
        .background(Color.white)
        .shadow(radius: 5)
    }

    // MARK: - Close Button

    @ViewBuilder
    private static func closeButton(
        for banner: BannerResponse,
        size: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        let bodyValues = DesignRenderer.getDesignBodyValues(banner)

        let bgColor = DesignRenderer.parseColor(bodyValues["popupCloseButton_backgroundColor"])
            ?? DesignRenderer.parseColor(banner.cssStyles["closeButtonBackgroundColor"])
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

    private static func getOverlayColor(_ banner: BannerResponse) -> Color {
        let bodyValues = DesignRenderer.getDesignBodyValues(banner)
        if let color = DesignRenderer.parseColor(bodyValues["popupOverlay_backgroundColor"]) { return color }
        if let color = DesignRenderer.parseColor(banner.cssStyles["overlayColor"]) { return color }
        return Color.black.opacity(0.5)
    }
}
