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

    /// A card holding the design, sized and placed from the banner's chrome keys
    /// (`BannerCardStyle`) over what this SDK has always drawn: `popupWidth` capped to the
    /// available width minus 16 pt each side (default 600), `borderRadius` (default 10),
    /// `popupBackgroundColor` (default white), centred inside the safe area, with the design's
    /// `popupOverlay_backgroundColor` dimming the rest of the screen.
    /// Height follows the content and scrolls inside the card when taller than the safe area,
    /// unless `cardHeight` fixes it, in which case `contentVerticalAlign` places the design in
    /// the card. The close button sits inside the top-right corner with a 44 pt hit target.
    @ViewBuilder
    static func popup(
        _ banner: BannerResponse,
        viewModel: BannerDisplayViewModel,
        onLinkTap: @escaping (String) -> Void
    ) -> some View {
        // These three are the popup's own pre-existing reads of the design's body values — kept
        // as the default branch each new key falls through to (the same pattern the flyout below
        // already uses for `popupWidth`/`popupBackgroundColor`), so a key at its default still
        // runs exactly today's code path per the compatibility rule, rather than a hardcoded
        // literal standing in for a measurement of production data that could go stale.
        let bodyValues = DesignRenderer.getDesignBodyValues(banner)
        let legacyCardWidth = DesignRenderer.parseDimensionRaw(bodyValues["popupWidth"]) ?? 600
        let legacyCornerRadius = DesignRenderer.parseDimensionRaw(bodyValues["borderRadius"]) ?? 10
        let style = BannerCardStyle(banner, legacyDefault: legacyCornerRadius)
        let overlayColor = getOverlayColor(banner)
        let cardBackground = style.backgroundColor
            ?? DesignRenderer.parseColor(bodyValues["popupBackgroundColor"])
            ?? .white

        ZStack {
            // Overlay
            overlayColor
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
                    // The band comes OUT of the card's height, not on top of it: the outer
                    // `.frame(height: cardHeight)` still reports the size the author asked for,
                    // and the content gets what is left. Padding without taking it off the
                    // budget would make an authored card 56pt taller than it asked to be, and
                    // push `contentVerticalAlign: bottom` copy past the card's own edge.
                    popupContent(
                        banner,
                        viewModel: viewModel,
                        width: cardWidth,
                        maxHeight: max((cardHeight ?? maxHeight) - closeControlBand, 1),
                        dismissForLink: { viewModel.dismissPopup(banner, track: false) },
                        onLinkTap: onLinkTap
                    )
                    .padding(.top, closeControlBand)
                    .frame(
                        height: cardHeight,
                        alignment: Alignment(horizontal: .center, vertical: style.contentVerticalAlign.alignment)
                    )

                    closeButton(for: banner, size: 32) {
                        viewModel.dismissPopup(banner)
                    }
                    .padding(8)
                }
                .frame(width: cardWidth)
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
                .shadow(color: Color.black.opacity(0.25), radius: 24, y: 8)
                // Reports the card's own on-screen frame, so a snapshot test can observe its
                // width and position the same way it already does for a bar or a flyout: the
                // placement and offset modifiers below still apply to this view and its
                // background together, exactly as they do for the bar's `VStack`. `coversScreen`
                // is what actually gates touch pass-through for a popup, so this does not change
                // hit-testing.
                .reportBannerFrame()
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
                DesignRenderer.render(design: design, maxWidth: width) { url in
                    dismissForLink()
                    viewModel.trackClick(banner)
                    onLinkTap(url)
                }
            }
        }
        .frame(width: width)

        CappedHeightContent(maxHeight: maxHeight, bottomInset: bottomInset, topBleedColor: topBleedColor) { rendered }
    }

    // MARK: - Flyout Banner

    /// The mobile flyout: a drawer flush with the screen edge `cardPositionHorizontal` names —
    /// or, at its `auto` default, with the one `displayPosition` names — from the top of the safe
    /// area to the screen bottom, no corner radius, width hugging the design's content (an
    /// image-only design gets its image width plus padding) unless `cardWidth` sets it, capped to
    /// 72 % of the screen either way, scrolling when the content is taller. A deliberate deviation
    /// from the web flyout (`bottom: 0; left/right: 20px; width: auto`), which reads as a popup on
    /// a phone. The close button sits inside the panel's top-right corner; there is no dimmed
    /// overlay and the page around the panel stays usable.
    @ViewBuilder
    static func flyout(
        _ banner: BannerResponse,
        viewModel: BannerDisplayViewModel,
        bottomInset: CGFloat = 0,
        onLinkTap: @escaping (String) -> Void
    ) -> some View {
        let style = BannerCardStyle(banner)
        let bodyValues = DesignRenderer.getDesignBodyValues(banner)
        let bgImageMap = bodyValues["backgroundImage"]
        let hasBodyBgImage = !(bgImageMap?["url"]?.stringValue ?? "").isEmpty
        let legacySide: BannerCardStyle.HorizontalPlacement = banner.displayPosition == "left" ? .left : .right
        let side = style.positionHorizontal ?? legacySide
        // `popupWidth` stays as the *default* branch `cardWidth` falls back to (not read
        // directly any more, only through `style.width` below): at `cardWidth`'s default this
        // is exactly today's pre-cap width source, so a design without an authored width still
        // renders identically on a container wide enough for the cap not to dominate (see
        // `BannerCardStyle.swift`'s `cardWidth`/`length` doc comments for the same pattern).
        let contentWidth = banner.design.flatMap { DesignRenderer.intrinsicImageWidth(in: $0) }
            ?? DesignRenderer.parseDimensionRaw(bodyValues["popupWidth"])
            ?? DesignRenderer.parseDimensionRaw(bodyValues["contentWidth"])
            ?? 360
        // Colours for the parts of the drawer the content does not cover: the first row's above
        // it, the last row's below it.
        let rows = banner.design?["body"]?["rows"]?.arrayValue?.compactMap { $0.objectValue } ?? []
        // Same pattern as the width above: `popupBackgroundColor` is the default branch
        // `cardBackgroundColor` falls back to, not read directly, so a design with no first/last
        // row colour and no authored `cardBackgroundColor` still bleeds today's white rather than
        // the body `backgroundColor`.
        let fallback = style.backgroundColor
            ?? DesignRenderer.parseColor(bodyValues["popupBackgroundColor"])
            ?? DesignRenderer.parseColor(bodyValues["backgroundColor"])
            ?? Color.white
        let topColor = rowColor(rows.first) ?? fallback
        let bottomColor = rowColor(rows.last) ?? fallback

        // `geometry` spans from the top of the safe area to the bottom of the screen. The drawer
        // fills it: content at the top, scrolling when taller, the design's colours filling the
        // rest.
        GeometryReader { geometry in
            let designWidth = style.width?.resolved(in: geometry.size.width) ?? contentWidth
            let width = max(160, min(designWidth, geometry.size.width * 0.72))
            let maxHeight = max(160, geometry.size.height - bottomInset)

            ZStack(alignment: .topTrailing) {
                // As the popup above: the control is drawn over this, so the band it owns is
                // taken off the content's budget and added back as padding. sdk-flutter's
                // flyout does not need this because its control is the first child of a
                // `Column`, in flow above the content rather than over it.
                popupContent(
                    banner,
                    viewModel: viewModel,
                    width: width,
                    maxHeight: max(maxHeight - closeControlBand, 1),
                    bottomInset: bottomInset,
                    topBleedColor: topColor,
                    dismissForLink: { viewModel.dismissFlyout(banner, track: false) },
                    onLinkTap: onLinkTap
                )
                .padding(.top, closeControlBand)

                closeButton(for: banner, size: 32) {
                    viewModel.dismissFlyout(banner)
                }
                .padding(8)
            }
            .frame(width: width, height: geometry.size.height, alignment: .top)
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
            .clipped()
            .shadow(color: Color.black.opacity(0.25), radius: 16, x: side.shadowDirection * 4, y: 0)
            .reportBannerFrame()
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: Alignment(horizontal: side.alignment, vertical: .bottom)
            )
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

    /// The bar itself, without the positioning that puts it at the top or bottom of the
    /// screen: the SwiftUI modifier pins it with a `GeometryReader` and `Spacer`, while
    /// `BannerPresenter` pins it with layout constraints on a child view controller.
    ///
    /// The bar as the web SDK draws it: a full-width strip at the screen edge, no dimmed overlay,
    /// the design edge to edge, the body colour as the strip's background, the close button inside
    /// the top-right corner. A tap on the strip outside the design closes the bar; the page around
    /// it stays usable.
    /// - Parameter safeAreaInset: extra padding on the screen-edge side. The modifier reads
    ///   this off its `GeometryReader` because it draws past the safe area; a presenter that
    ///   constrains to the safe area passes `0`. For a top bar the key window's own inset is the
    ///   floor, because a `GeometryReader` that ignores the safe area can report `0`.
    @ViewBuilder
    static func bar(
        _ banner: BannerResponse,
        viewModel: BannerDisplayViewModel,
        isBottom: Bool,
        safeAreaInset: CGFloat,
        width: CGFloat? = nil,
        onLinkTap: @escaping (String) -> Void
    ) -> some View {
        // The strip behind the design: the first row's colour, else the first column's, else the
        // system background. Unlayer's default body colour (#F7F8F9) is not used; it reads as a
        // white strip over a dark app.
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
                // `width` is the container's real width; `UIScreen` is a fallback that is wrong
                // when the window is not the screen (iPad split view, the snapshot test's window).
                // Rendered to the width it will actually occupy, not the bar's: the band
                // below is reserved for the close control, and a design laid out against the
                // full width would be re-flowed or clipped by it rather than fitting it.
                DesignRenderer.render(
                    design: design,
                    maxWidth: max((width ?? UIScreen.main.bounds.width) - closeControlBand, 1)
                ) { url in
                    viewModel.trackClick(banner)
                    onLinkTap(url)
                }
                .frame(maxWidth: .infinity)
                .padding(.trailing, closeControlBand)
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

    /// The band the close control owns, measured in from the card's edge: its own 8pt inset,
    /// plus the 44pt tappable box `closeButton` pads a 32pt circle out to, plus 4 of clearance.
    ///
    /// The control is drawn OVER the content — it is a `ZStack` sibling, not a view in flow
    /// beside it — so without this reserved the design runs underneath it and the tail of a
    /// headline is painted beneath the glyph. sdk-react-native photographed exactly that on
    /// 2026-10-03, where a narrow card's copy read "CHR-08 bottom-left offse✕"; sdk-kotlin
    /// reserves a `closeGutter` and sdk-flutter a `_closeControlBand` for the same reason.
    ///
    /// Bigger than their 44/48 because this SDK pads the control's hit area out to Apple's
    /// 44pt minimum, so the box to clear is larger than the circle you can see.
    static let closeControlBand: CGFloat = 56

    /// Accessibility identifier on the close control, so a test can measure its frame.
    static let closeControlIdentifier = "releva-banner-close"

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
        // The snapshot harness finds views by identifier; without one, no test can ask where
        // this control is relative to the copy it is drawn over.
        .accessibilityIdentifier(Self.closeControlIdentifier)
    }

    // MARK: - Helpers

    private static func getOverlayColor(_ banner: BannerResponse) -> Color {
        let bodyValues = DesignRenderer.getDesignBodyValues(banner)
        if let color = DesignRenderer.parseColor(bodyValues["popupOverlay_backgroundColor"]) { return color }
        if let color = DesignRenderer.parseColor(banner.cssStyles["overlayColor"]) { return color }
        return Color.black.opacity(0.5)
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
