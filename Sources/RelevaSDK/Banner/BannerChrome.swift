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
                            CachedRemoteImage(url: bgInfo.url) { phase in
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
    ///
    /// Mirrors the web SDK's bar (`render.js`): a full-width strip at the screen edge with no
    /// dimmed overlay, the design drawn edge to edge with no padding of ours, the design's body
    /// colour as the strip's background, and the close button inside the strip's top-right
    /// corner exactly like the popup card. A tap on the strip itself, outside the design's
    /// content, closes the bar (the web closes on a click on the modal element); taps on the
    /// page around the bar are left alone because a bar is not modal.
    /// - Parameter safeAreaInset: extra padding on the screen-edge side. The modifier reads
    ///   this off its `GeometryReader` because it draws past the safe area; a presenter that
    ///   constrains to the safe area passes `0`. For a top bar the key window's own inset is
    ///   used as a floor, because a `GeometryReader` that ignores the safe area has reported
    ///   `0` on the device and the bar then sat under the status bar (device run 20).
    @ViewBuilder
    static func bar(
        _ banner: BannerResponse,
        viewModel: BannerDisplayViewModel,
        isBottom: Bool,
        safeAreaInset: CGFloat,
        width: CGFloat? = nil,
        onLinkTap: @escaping (String) -> Void
    ) -> some View {
        // The strip behind the design and under the status bar / home indicator: the first
        // row's own colour when it has one (that is the colour the user sees as "the banner"),
        // else the first column's, else the system background so it follows light/dark mode.
        // Unlayer's default body colour (#F7F8F9) is deliberately not used: it reads as a
        // white strip over a dark app (device run 22).
        let firstRow = banner.design?["body"]?["rows"]?.arrayValue?.first?.objectValue ?? [:]
        let firstRowValues = firstRow["values"]?.objectValue ?? [:]
        let firstColumnValues = firstRow["columns"]?.arrayValue?.first?["values"]?.objectValue ?? [:]
        let barBackground = DesignRenderer.parseColor(firstRowValues["backgroundColor"])
            ?? DesignRenderer.parseColor(firstRowValues["columnsBackgroundColor"])
            ?? DesignRenderer.parseColor(firstColumnValues["backgroundColor"])
            ?? Color(UIColor.systemBackground)
        let edgeInset = isBottom ? safeAreaInset : max(safeAreaInset, keyWindowSafeAreaInsets.top)

        ZStack(alignment: .topTrailing) {
            if let design = banner.design {
                // `width` is the container's real width; `UIScreen` is only a fallback because
                // it is wrong whenever the window is not the screen (iPad split view, and the
                // snapshot test's 393 pt window on a 402 pt simulator).
                DesignRenderer.render(
                    design: design,
                    maxWidth: width ?? UIScreen.main.bounds.width
                ) { url in
                    viewModel.trackClick(banner)
                    onLinkTap(url)
                }
                .frame(maxWidth: .infinity)
                .padding(isBottom ? .bottom : .top, edgeInset)
            }

            closeButton(for: banner, size: 32) {
                viewModel.dismissBar(banner)
            }
            .padding(.top, (isBottom ? 0 : edgeInset) + 8)
            .padding(.trailing, 8)
        }
        .frame(maxWidth: .infinity)
        .background(
            barBackground
                .contentShape(Rectangle())
                .onTapGesture { viewModel.dismissBar(banner) }
        )
        .shadow(color: Color.black.opacity(0.2), radius: 6, y: isBottom ? -2 : 2)
    }

    /// The key window's safe-area insets, used as a floor for a top bar's status-bar padding.
    private static var keyWindowSafeAreaInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .safeAreaInsets ?? .zero
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
