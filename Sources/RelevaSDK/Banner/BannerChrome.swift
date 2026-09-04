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

    /// A popup is a centred card sized from the design's body values, the way the web SDK and
    /// Unlayer's own preview draw it: `popupWidth` (default 600 px, capped to the screen width
    /// minus a 16 pt margin on each side), `borderRadius`, `popupBackgroundColor` and
    /// `popupOverlay_backgroundColor`. Height follows the content; when the content is taller
    /// than the safe area the card fills it and scrolls inside. A `popupHeight` in `vh` units
    /// (for example "100vh") asks for the full-height card. The close button sits inside the
    /// card's top-right corner with a 44 pt hit target, like a native sheet.
    @ViewBuilder
    static func popup(
        _ banner: BannerResponse,
        viewModel: BannerDisplayViewModel,
        onLinkTap: @escaping (String) -> Void
    ) -> some View {
        let bodyValues = DesignRenderer.getDesignBodyValues(banner)
        let overlayColor = getOverlayColor(banner)
        let screenWidth = UIScreen.main.bounds.width
        let designWidth = DesignRenderer.parseDimensionRaw(bodyValues["popupWidth"]) ?? 600
        let cardWidth = min(designWidth, screenWidth - 32)
        let cornerRadius = DesignRenderer.parseDimensionRaw(bodyValues["borderRadius"]) ?? 10
        let cardBackground = DesignRenderer.parseColor(bodyValues["popupBackgroundColor"]) ?? .white
        let wantsFullHeight = (bodyValues["popupHeight"]?.stringValue ?? "").hasSuffix("vh")

        ZStack {
            // Overlay
            overlayColor
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    viewModel.dismissPopup(banner)
                }

            GeometryReader { geometry in
                let maxHeight = max(geometry.size.height - 32, 120)

                ZStack(alignment: .topTrailing) {
                    popupContent(
                        banner,
                        viewModel: viewModel,
                        width: cardWidth,
                        maxHeight: maxHeight,
                        fullHeight: wantsFullHeight,
                        onLinkTap: onLinkTap
                    )

                    closeButton(for: banner, size: 32) {
                        viewModel.dismissPopup(banner)
                    }
                    .padding(8)
                }
                .frame(width: cardWidth)
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .shadow(color: Color.black.opacity(0.25), radius: 24, y: 8)
                // Centre the card inside the safe area.
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
    }

    /// The rendered design inside a popup card: sized to its content when it fits, otherwise
    /// a scrolling area of `maxHeight`. `fullHeight` forces the scrolling area.
    @ViewBuilder
    private static func popupContent(
        _ banner: BannerResponse,
        viewModel: BannerDisplayViewModel,
        width: CGFloat,
        maxHeight: CGFloat,
        fullHeight: Bool,
        onLinkTap: @escaping (String) -> Void
    ) -> some View {
        let rendered = Group {
            if let design = banner.design {
                DesignRenderer.render(design: design, maxWidth: width) { url in
                    viewModel.dismissPopup(banner, track: false)
                    viewModel.trackClick(banner)
                    onLinkTap(url)
                }
            }
        }
        .frame(width: width)

        if fullHeight {
            ScrollView { rendered }
                .frame(height: maxHeight)
        } else if #available(iOS 16.0, *) {
            // No `.frame(maxHeight:)` here: that modifier grows to whatever height is offered,
            // so the card filled the screen with blank space above and below a short design
            // (snapshot, run 23). `ViewThatFits` alone gives the content's own height, or the
            // capped scrolling area when the design is taller than the screen.
            ViewThatFits(in: .vertical) {
                rendered
                ScrollView { rendered }
                    .frame(height: maxHeight)
            }
        } else {
            ScrollView { rendered }
                .frame(maxHeight: maxHeight)
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
                                transparentBody: hasBodyBgImage
                            ) { url in
                                viewModel.dismissFlyout(banner, track: false)
                                viewModel.trackClick(banner)
                                onLinkTap(url)
                            }
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
                    maxWidth: UIScreen.main.bounds.width - 32
                ) { url in
                    viewModel.trackClick(banner)
                    onLinkTap(url)
                }
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

        // The visible circle is `size` points; the tappable area is padded out to at least
        // 44 points (Apple's minimum touch target) so a 24–36 pt glyph is still easy to hit.
        let hitPadding = max(0, (44 - size) / 2)

        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundColor(iconColor)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(bgColor)
                        .overlay(Circle().stroke(borderColor, lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.15), radius: 2, y: 1)
                )
                .padding(hitPadding)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }

    // MARK: - Helpers

    private static func getOverlayColor(_ banner: BannerResponse) -> Color {
        let bodyValues = DesignRenderer.getDesignBodyValues(banner)
        if let color = DesignRenderer.parseColor(bodyValues["popupOverlay_backgroundColor"]) { return color }
        if let color = DesignRenderer.parseColor(banner.cssStyles["overlayColor"]) { return color }
        return Color.black.opacity(0.5)
    }
}
