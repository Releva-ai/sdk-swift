import SwiftUI

/// The chrome around a rendered banner design: the dimmed overlay, the close button, the
/// popup/flyout/bar framing, and the inline static banner.
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

    /// A card holding the design, sized and placed from the banner's chrome keys
    /// (`BannerCardStyle`) over what this SDK has always drawn: `popupWidth` capped to the
    /// available width minus 16 pt each side (default 600), `borderRadius` (default 10),
    /// `popupBackgroundColor` (default white), centred inside the safe area. The rest of the
    /// screen is dimmed black at 50%, as sdk-react-native's Modal overlay is.
    /// Height follows the content and scrolls inside the card when taller than the safe area,
    /// unless `cardHeight` fixes it, in which case `contentVerticalAlign` places the design in
    /// the card. The close button sits 8 in from the top-right corner, its 44 pt tap target
    /// centred on it.
    @ViewBuilder
    static func popup(
        _ banner: BannerResponse,
        viewModel: BannerDisplayViewModel,
        onLinkTap: @escaping (String) -> Void
    ) -> some View {
        // These three are the popup's own pre-existing reads of the design's body values — kept
        // as the default branch each new key falls through to (the same pattern the flyout below
        // uses for `popupBackgroundColor`), so a key at its default still
        // runs exactly today's code path per the compatibility rule, rather than a hardcoded
        // literal standing in for a measurement of production data that could go stale.
        let bodyValues = DesignRenderer.getDesignBodyValues(banner)
        let legacyCardWidth = DesignRenderer.parseDimensionRaw(bodyValues["popupWidth"]) ?? 600
        let legacyCornerRadius = DesignRenderer.parseDimensionRaw(bodyValues["borderRadius"]) ?? 10
        let style = BannerCardStyle(banner, legacyDefault: legacyCornerRadius)
        let closeStyle = BannerCloseButtonStyle(banner)
        let band = closeBand(closeStyle)
        let ring = closeRing(closeStyle)
        let cardBackground = style.backgroundColor
            ?? DesignRenderer.parseColor(bodyValues["popupBackgroundColor"])
            ?? .white

        ZStack {
            // Overlay
            Color.black.opacity(0.5)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    viewModel.dismissPopup(banner)
                }

            GeometryReader { geometry in
                // The container's own width, not `UIScreen.main.bounds.width`: only this is
                // right when the window is narrower than the physical screen (iPad split view,
                // the snapshot test's window).
                let cardWidth = style.cardWidth(availableWidth: geometry.size.width, legacyDefault: legacyCardWidth)
                let maxHeight = max(geometry.size.height - 32, 120)
                // An authored height still stays inside the safe area, as the measured one does.
                let cardHeight = style.cardHeight(availableHeight: geometry.size.height, maxHeight: maxHeight)

                ZStack(alignment: .topTrailing) {
                    // The band comes out of an authored card's height, not on top of it, so the
                    // card keeps the size the author asked for and `contentVerticalAlign: bottom`
                    // copy stays inside it. A content-sized card grows by the band.
                    popupContent(
                        banner,
                        viewModel: viewModel,
                        width: cardWidth,
                        maxHeight: max((cardHeight ?? maxHeight) - band, 1),
                        dismissForLink: { viewModel.dismissPopup(banner, track: false) },
                        onLinkTap: onLinkTap
                    )
                    .padding(.top, band)
                    .frame(
                        height: cardHeight,
                        alignment: Alignment(horizontal: .center, vertical: style.contentVerticalAlign.alignment)
                    )

                    closeButton(for: banner) {
                        viewModel.dismissPopup(banner)
                    }
                    .padding(closeControlInset - ring)
                }
                .frame(width: cardWidth)
                // A colour background reaches into the safe area wherever the card touches its
                // edge; that is clipped away below but still widens the accessibility frame.
                .background(cardBackground, ignoresSafeAreaEdges: [])
                .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
                .shadow(color: Color.black.opacity(0.25), radius: 24, y: 8)
                // Reports the card's own on-screen frame, so a snapshot test can observe its
                // width and position the same way it does for a bar or a flyout: the placement
                // and offset modifiers below apply to this view and its background together.
                // `coversScreen` is what gates touch pass-through for a popup, so this does not
                // change hit-testing.
                .reportBannerFrame()
                .bannerAccessibilityContainer(BannerAccessibilityID.banner(banner.token))
                // Place the card inside the safe area: centred unless the position keys say
                // otherwise, then moved by the offset keys.
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height,
                    alignment: Alignment(
                        horizontal: style.positionHorizontal?.alignment ?? .center,
                        vertical: style.positionVertical?.alignment ?? .center
                    )
                )
                .offset(
                    x: style.offsetTranslationX(in: geometry.size.width),
                    y: style.offsetTranslationY(in: geometry.size.height)
                )
            }
            // The safe-area box the card is placed in.
            .bannerAccessibilityMarker(BannerAccessibilityID.placement)
        }
    }

    /// The rendered design inside a popup card: sized to its content when it fits, otherwise
    /// a scrolling area of `maxHeight`.
    @ViewBuilder
    // swiftlint:disable:next function_parameter_count
    private static func popupContent(
        _ banner: BannerResponse,
        viewModel: BannerDisplayViewModel,
        width: CGFloat,
        maxHeight: CGFloat,
        bottomInset: CGFloat = 0,
        topBleedColor: Color? = nil,
        dismissForLink: @escaping () -> Void,
        onLinkTap: @escaping (String) -> Void
    ) -> some View {
        let rendered = Group {
            if let design = banner.design {
                DesignRenderer.render(
                    design: design,
                    maxWidth: width,
                    onLinkTap: linkTap(banner, viewModel: viewModel, close: dismissForLink, onLinkTap: onLinkTap)
                )
            }
        }
        .frame(width: width)

        CappedHeightContent(maxHeight: maxHeight, bottomInset: bottomInset, topBleedColor: topBleedColor) { rendered }
    }

    // MARK: - Flyout Banner

    /// How a flyout and its dim slide up from the bottom of the window when it opens and back down
    /// when it closes: the spring UIKit runs a `.coverVertical` modal transition with, which is how
    /// sdk-react-native presents a flyout (`Modal animationType="slide"`). Critically damped, mass
    /// 3, stiffness 1000.
    static let flyoutSlide = Animation.interpolatingSpring(
        mass: 3,
        stiffness: 1000,
        damping: 2 * (3.0 * 1000).squareRoot(),
        initialVelocity: 0
    )

    /// How long UIKit's `.coverVertical` transition runs.
    nonisolated static let flyoutSlideDuration: TimeInterval = 0.5

    /// The flyout, placed as sdk-react-native places it on iOS (see `FlyoutCardLayout`): a card 80%
    /// of the window wide against the side `cardPositionHorizontal` or `displayPosition` names, full
    /// height unless `cardHeight` is authored, then moved by the offset keys and rounded by
    /// `cardBorderRadius`. A card with no size runs under the status bar and the home indicator and
    /// insets its content and close control instead. The close control sits on the card's inner
    /// edge. The rest of the window is dimmed black at 50%, and a tap there closes the flyout, as
    /// sdk-react-native's Modal overlay does.
    /// - Parameter safeArea: the window's safe-area insets. The view itself spans the window.
    @ViewBuilder
    static func flyout(
        _ banner: BannerResponse,
        viewModel: BannerDisplayViewModel,
        safeArea: EdgeInsets,
        onLinkTap: @escaping (String) -> Void
    ) -> some View {
        let style = BannerCardStyle(banner)
        let closeStyle = BannerCloseButtonStyle(banner)
        let bodyValues = DesignRenderer.getDesignBodyValues(banner)
        let bgImageMap = bodyValues["backgroundImage"]
        let hasBodyBgImage = !(bgImageMap?["url"]?.stringValue ?? "").isEmpty
        // Colours for the parts of the card the content does not cover: the first row's above it,
        // the last row's below it. `popupBackgroundColor` is what `cardBackgroundColor` falls back
        // to, before the body's `backgroundColor`.
        let rows = banner.design?["body"]?["rows"]?.arrayValue?.compactMap { $0.objectValue } ?? []
        let fallback = style.backgroundColor
            ?? DesignRenderer.parseColor(bodyValues["popupBackgroundColor"])
            ?? DesignRenderer.parseColor(bodyValues["backgroundColor"])
            ?? Color.white
        let topColor = rowColor(rows.first) ?? fallback
        let bottomColor = rowColor(rows.last) ?? fallback
        let band = closeBand(closeStyle)
        let ring = closeRing(closeStyle)

        GeometryReader { geometry in
            let layout = FlyoutCardLayout(style: style, displayPosition: banner.displayPosition, window: geometry.size, safeArea: safeArea)
            let insets = layout.insets
            let card = layout.frame
            // Below the top inset: the close band, then the content aligned in the rest.
            let region = max(card.height - insets.top, 1)
            let closeSideInset = layout.closeOnLeading ? insets.leading : insets.trailing

            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.5)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .onTapGesture { viewModel.dismissFlyout(banner) }

                if layout.isSized {
                    Color.clear
                        .frame(width: layout.box.width, height: layout.box.height)
                        .bannerAccessibilityMarker(BannerAccessibilityID.placement)
                        .offset(x: layout.box.minX, y: layout.box.minY)
                }

                ZStack(alignment: layout.closeOnLeading ? .topLeading : .topTrailing) {
                    VStack(spacing: 0) {
                        // An image-backed card's image already spans the band.
                        (hasBodyBgImage ? Color.clear : topColor).frame(height: insets.top + band)
                        popupContent(
                            banner,
                            viewModel: viewModel,
                            width: max(card.width - insets.leading - insets.trailing, 1),
                            maxHeight: max(region - band - insets.bottom, 1),
                            bottomInset: insets.bottom,
                            topBleedColor: topColor,
                            dismissForLink: { viewModel.dismissFlyout(banner, track: false) },
                            onLinkTap: onLinkTap
                        )
                        .frame(
                            height: max(region - band, 1),
                            alignment: Alignment(horizontal: .center, vertical: style.contentVerticalAlign.alignment)
                        )
                    }
                    .padding(.leading, insets.leading)
                    .padding(.trailing, insets.trailing)

                    closeButton(for: banner) {
                        viewModel.dismissFlyout(banner)
                    }
                    .padding(.top, insets.top + closeControlInset - ring)
                    .padding(layout.closeOnLeading ? .leading : .trailing, closeSideInset + closeControlInset - ring)
                }
                .frame(width: card.width, height: card.height, alignment: .top)
                .background(
                    Group {
                        if hasBodyBgImage, let bgInfo = DesignRenderer.parseBackgroundImage(bgImageMap, forceCover: true) {
                            CachedRemoteImage(url: bgInfo.url) { phase in
                                if case .success(let image) = phase {
                                    image.resizable().aspectRatio(contentMode: bgInfo.contentMode)
                                }
                            }
                        } else {
                            bottomColor
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: style.authoredCornerRadius ?? 0, style: .circular))
                // A tap on the card where the design draws nothing stays on the card.
                .contentShape(Rectangle())
                .shadow(color: Color.black.opacity(0.25), radius: 16, x: layout.shadowDirection * 4, y: 0)
                .reportBannerFrame()
                .bannerAccessibilityContainer(BannerAccessibilityID.banner(banner.token))
                .offset(x: card.minX + layout.translation.width, y: card.minY + layout.translation.height)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
    }

    /// A row's visible colour: its own background, its columns' background, or the first
    /// column's; nil when the row has none.
    private static func rowColor(_ row: [String: JSONValue]?) -> Color? {
        guard let row = row else { return nil }
        let values = row["values"]?.objectValue ?? [:]
        let firstColumn = row["columns"]?.arrayValue?.first?["values"]?.objectValue ?? [:]
        return DesignRenderer.parseColor(values["backgroundColor"])
            ?? DesignRenderer.parseColor(values["columnsBackgroundColor"])
            ?? DesignRenderer.parseColor(firstColumn["backgroundColor"])
    }

    // MARK: - Bar Banner

    /// A bar, laid out as sdk-react-native lays one out on iOS (see `BarCardLayout`): a layer across
    /// the container, pinned to an edge or centred in it, holding a card that the card keys size,
    /// round, paint, align and move. The card is unpainted unless `cardBackgroundColor` is
    /// authored, so only the design's own colours paint it. It pads the design 16 on the leading
    /// side and 12 above and below, keeps a gutter on the trailing side for the close control, and
    /// pads by the system UI it overlaps. A tap on the card outside the design does nothing, as in
    /// sdk-react-native; the layer around the card passes touches through to the app.
    /// - Parameter containerWidth: the width of the box the layer spans, which the design is laid
    ///   out against.
    @ViewBuilder
    static func bar(
        _ banner: BannerResponse,
        viewModel: BannerDisplayViewModel,
        layout: BarCardLayout,
        containerWidth: CGFloat,
        onLinkTap: @escaping (String) -> Void
    ) -> some View {
        let style = BannerCardStyle(banner)
        let closeStyle = BannerCloseButtonStyle(banner)
        let insets = layout.insets
        let gutter = closeGutter(closeStyle) + layout.closeInset
        let designWidth = max((layout.cardWidth ?? containerWidth) - insets.leading - insets.trailing - barContentLeading - gutter, 1)
        let ring = closeRing(closeStyle)
        // A bottom bar's control sits above its content's top edge, as in sdk-react-native.
        let closeTop = layout.vertical == .end ? -barCloseInset : barCloseInset

        Group {
            if let design = banner.design {
                DesignRenderer.render(
                    design: design,
                    maxWidth: designWidth,
                    onLinkTap: linkTap(banner, viewModel: viewModel, onLinkTap: onLinkTap)
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.leading, barContentLeading)
        .padding(.trailing, gutter)
        .padding(.vertical, barContentVertical)
        // The visible button is placed from the content's top-right corner; its tap target grows
        // outward around it, past the card's edge where the inset is smaller than the growth.
        .overlay(alignment: .topTrailing) {
            closeButton(for: banner) {
                viewModel.dismissBar(banner)
            }
            .reportBannerFrame()
            .offset(x: ring - barCloseInset - layout.closeInset, y: closeTop - ring)
        }
        .frame(
            width: layout.cardWidth.map { max($0 - insets.leading - insets.trailing, 0) },
            height: layout.cardHeight.map { max($0 - insets.top - insets.bottom, 0) },
            alignment: Alignment(horizontal: .leading, vertical: style.contentVerticalAlign.alignment)
        )
        .padding(insets)
        .background {
            RoundedRectangle(cornerRadius: style.authoredCornerRadius ?? 0, style: .circular)
                .fill(style.backgroundColor ?? Color.clear)
        }
        .reportBannerFrame()
        .offset(layout.translation)
        .frame(
            maxWidth: layout.hugsWidth ? nil : .infinity,
            maxHeight: layout.spansHeight ? .infinity : nil,
            alignment: Alignment(horizontal: layout.cardAlignment, vertical: .center)
        )
        // On the layer, behind the card, so the id's frame stays the layer's when the card moves.
        .bannerAccessibilityMarker(BannerAccessibilityID.banner(banner.token))
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: layout.layerAlignment, vertical: .center))
    }

    /// The key window's safe-area insets, used as a floor for where top bars start.
    private static var keyWindowSafeAreaInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .safeAreaInsets ?? .zero
    }

    /// The window's safe-area insets that bars are laid out by: `insets`, with the key window's top
    /// inset as a floor, because a view that ignores the safe area can be handed zero.
    static func barSafeArea(_ insets: UIEdgeInsets) -> EdgeInsets {
        EdgeInsets(
            top: max(insets.top, keyWindowSafeAreaInsets.top),
            leading: insets.left,
            bottom: insets.bottom,
            trailing: insets.right
        )
    }

    // MARK: - Links

    /// What a link tapped inside a banner's design does: run `close`, then report a click and route
    /// the link. A popup or a flyout passes a `close` that takes it down without a `bannerClose`:
    /// it is drawn above the app, so anything the link opens in the app would be under its dim. A
    /// bar passes none and stays up.
    static func linkTap(
        _ banner: BannerResponse,
        viewModel: BannerDisplayViewModel,
        close: (() -> Void)? = nil,
        onLinkTap: @escaping (String) -> Void
    ) -> (String) -> Void {
        { url in
            close?()
            viewModel.trackClick(banner)
            onLinkTap(url)
        }
    }

    // MARK: - Static Banner

    /// A static or replace banner: the design inline in the host's content, at the screen's width.
    @ViewBuilder
    static func inline(_ banner: BannerResponse, onLinkTap: @escaping (String) -> Void) -> some View {
        if let design = banner.design {
            DesignRenderer.render(design: design, maxWidth: UIScreen.main.bounds.width, onLinkTap: onLinkTap)
                .bannerAccessibilityContainer(BannerAccessibilityID.banner(banner.token))
        }
    }

    // MARK: - Close Control Geometry

    // The control is drawn over the content, so each display type keeps clear the band or gutter
    // it needs (`closeBand`, `closeGutter`); without it the end of a headline runs under the ✕.
    // The numbers are sdk-react-native's: the control is placed by its visible button, and its
    // tap target grows outward around it by `closeRing`.

    /// How far a popup's or a flyout's visible close button sits in from the card's corner.
    static let closeControlInset: CGFloat = 8

    /// Apple's minimum touch target, which `closeButton` pads its button out to.
    static let closeControlHitBox: CGFloat = 44

    /// How far a bar's visible close button sits in from its content's top-right corner.
    static let barCloseInset: CGFloat = 4

    /// A bar's padding around its design: on the leading side, and above and below.
    static let barContentLeading: CGFloat = 16
    static let barContentVertical: CGFloat = 12

    /// The band a popup or a flyout keeps clear at the top of its content for the close control:
    /// the control's inset, its visible button and 8 of clearance. 48 at the default size.
    nonisolated static func closeBand(_ style: BannerCloseButtonStyle) -> CGFloat {
        closeControlInset + style.side + 8
    }

    /// The gutter a bar keeps clear on its trailing side for the close control: the control's
    /// inset, its visible button and 8 of clearance. 44 at the default size.
    nonisolated static func closeGutter(_ style: BannerCloseButtonStyle) -> CGFloat {
        barCloseInset + style.side + 8
    }

    /// How far the tap target reaches past the visible button on each side. The control is placed
    /// by its visible button, so it is pulled out by this much.
    nonisolated static func closeRing(_ style: BannerCloseButtonStyle) -> CGFloat {
        max(0, (style.hitSide - style.side) / 2)
    }

    /// The thickness of the ✕'s two strokes.
    static let closeGlyphStroke: CGFloat = 2

    // MARK: - Close Button

    /// The close control, styled from `cssStyles` alone — see `BannerCloseButtonStyle`.
    @ViewBuilder
    private static func closeButton(
        for banner: BannerResponse,
        action: @escaping () -> Void
    ) -> some View {
        let style = BannerCloseButtonStyle(banner)
        let shape = RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)

        // The visible button is `style.side` points (32–44); the tappable area is padded out to
        // `style.hitSide`, at least `closeControlHitBox` (Apple's minimum touch target), centred
        // on it.
        let hitPadding = closeRing(style)

        Button(action: action) {
            // The ✕ as sdk-react-native draws it: two strokes `closeFontSize` long and 2 thick,
            // crossed at ±45° in a `closeFontSize` square. No shadow, as on its iOS path.
            ZStack {
                ForEach([45.0, -45.0], id: \.self) { angle in
                    Rectangle()
                        .fill(style.iconColor)
                        .frame(width: style.fontSize, height: closeGlyphStroke)
                        .rotationEffect(.degrees(angle))
                }
            }
            .frame(width: style.fontSize, height: style.fontSize)
            .frame(width: style.side, height: style.side)
            .background(
                shape
                    .fill(style.backgroundColor)
                    .overlay {
                        if let border = style.border {
                            shape.strokeBorder(border.color, lineWidth: border.width)
                        }
                    }
            )
            .padding(hitPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
        .accessibilityIdentifier(BannerAccessibilityID.close)
    }
}

// MARK: - Accessibility identifiers

/// The accessibility identifiers device QA reads; the same ids sdk-react-native sets as testIDs.
enum BannerAccessibilityID {
    /// The close control. Its frame is the whole tap target.
    static let close = "releva-banner-close"
    /// The box a popup, or a sized flyout, is placed in.
    static let placement = "releva-banner-placement"

    /// A banner's own view: the popup or flyout card, the bar strip, or a static banner's container.
    static func banner(_ token: String) -> String { "releva-banner-\(token)" }
}

extension View {
    /// Makes this view an accessibility container carrying `identifier`. The id stays on this
    /// view, and the views inside it stay individually accessible.
    func bannerAccessibilityContainer(_ identifier: String) -> some View {
        // SwiftUI frames a container by what is drawn inside it; the clear fill makes that at
        // least this view's own bounds.
        background(Color.clear.allowsHitTesting(false))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(identifier)
    }

    /// An empty accessibility container carrying `identifier`, drawn behind this view with its
    /// bounds. For a box whose only accessible child is itself a container: SwiftUI merges a
    /// container wrapped around a single container into one element with one id.
    func bannerAccessibilityMarker(_ identifier: String, when condition: Bool = true) -> some View {
        background {
            if condition {
                Color.clear
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(identifier)
            }
        }
    }
}

// MARK: - Capped height

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Shows `content` at its own height, or inside a scroll view of `maxHeight` when taller. The
/// content is measured once; `ViewThatFits` compares against the offered height, which in the
/// overlay window is the whole safe area.
struct CappedHeightContent<Content: View>: View {
    let maxHeight: CGFloat
    /// Space to keep clear below the content (the home indicator when the container reaches
    /// the screen bottom). Added as padding when the content is shown as is; when it scrolls,
    /// the scroll view is given the extra height and its content is inset by the same amount,
    /// so the last line stops above the indicator while the panel colour fills the strip.
    var bottomInset: CGFloat = 0
    /// Drawn above the content inside the scroll view so a bounce at the top shows this colour
    /// instead of the container's background.
    var topBleedColor: Color?
    @ViewBuilder let content: () -> Content

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        let measured = content()
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(key: ContentHeightKey.self, value: geometry.size.height)
                }
            )

        Group {
            if contentHeight > maxHeight {
                ScrollView {
                    measured
                        .padding(.bottom, bottomInset)
                        .background(alignment: .top) {
                            if let color = topBleedColor {
                                color.frame(height: 2000).offset(y: -2000)
                            }
                        }
                }
                .frame(height: maxHeight + bottomInset)
            } else {
                measured.padding(.bottom, bottomInset)
            }
        }
        .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
    }
}
