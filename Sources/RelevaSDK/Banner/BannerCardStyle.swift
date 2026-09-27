import SwiftUI

/// The author-controlled chrome and position keys the API serves in a banner's `cssStyles`,
/// resolved against their documented defaults.
///
/// The same nine keys are validated server-side and honoured by the web SDK and by the other
/// mobile SDKs, but each SDK keeps its own layout: a key at its default means "whatever this
/// platform does today", not "what the web does". So a default resolves to `nil` here and the
/// call site runs unchanged; only an authored value becomes a layout decision. The comparison
/// is trimmed and case-insensitive, because the defaults are literals produced in another
/// repo and a case near-miss must not read as intent.
///
/// `displayPosition` is the legacy input and stays as it is: it is what `cardPositionVertical`
/// and `cardPositionHorizontal` fall back to when they are `auto`.
struct BannerCardStyle {
    /// A length from one of the size or offset keys: CSS pixels — one point each, as every
    /// other dimension in a design is read — or a percentage of the axis the key applies to.
    enum Length: Equatable {
        case points(CGFloat)
        case percent(CGFloat)

        /// - Parameter available: the extent of the axis this length applies to, which a
        ///   percentage resolves against.
        func resolved(in available: CGFloat) -> CGFloat {
            switch self {
            case .points(let value): return value
            case .percent(let value): return available * value / 100
            }
        }
    }

    enum HorizontalPlacement: String {
        case left, center, right

        var alignment: HorizontalAlignment {
            switch self {
            case .left: return .leading
            case .center: return .center
            case .right: return .trailing
            }
        }

        /// Which way a panel docked to this side casts its shadow: away from its own edge.
        var shadowDirection: CGFloat {
            switch self {
            case .left: return 1
            case .center: return 0
            case .right: return -1
            }
        }
    }

    enum VerticalPlacement: String {
        case top, center, bottom

        var alignment: VerticalAlignment {
            switch self {
            case .top: return .top
            case .center: return .center
            case .bottom: return .bottom
            }
        }
    }

    /// `cardBackgroundColor`, or `nil` to keep the colour the call site already uses.
    let backgroundColor: Color?
    /// `cardWidth` / `cardHeight`, or `nil` for the size the call site already computes.
    let width: Length?
    let height: Length?
    /// `cardBorderRadius`, already mapped to this SDK's own default. The key's documented
    /// default is `0`, but an iOS popup card has always been drawn with a 10 pt radius, and a
    /// default must not change anything — mapping it to `0` would square off every popup. The
    /// radius that default maps to is `init`'s `legacyDefault` — the popup call site's own
    /// `borderRadius` body-value read, which is `10` for every real banner today but keeps the
    /// same code path running unchanged, per the compatibility rule, rather than assuming that.
    let cornerRadius: CGFloat
    /// `contentVerticalAlign`: where the design sits in a card taller than it is. `top`, its
    /// default, is where a card that hugs its content puts it anyway.
    let contentVerticalAlign: VerticalPlacement
    /// `cardPositionVertical` / `cardPositionHorizontal`, or `nil` at `auto`, where placement
    /// falls back to `displayPosition`.
    let positionVertical: VerticalPlacement?
    let positionHorizontal: HorizontalPlacement?
    /// `cardOffsetVertical` / `cardOffsetHorizontal`, or `nil` for no offset.
    let offsetVertical: Length?
    let offsetHorizontal: Length?

    /// - Parameter legacyDefault: what `cornerRadius` resolves to when `cardBorderRadius` is
    ///   unauthored. Defaults to `10`, the radius this SDK's popup has always drawn, but the
    ///   popup call site passes its own `borderRadius` body-value read instead — see
    ///   `cornerRadius`'s doc comment.
    init(_ banner: BannerResponse, legacyDefault: CGFloat = 10) {
        let styles = banner.cssStyles
        backgroundColor = DesignRenderer.parseColor(css: Self.authored(styles, "cardBackgroundColor", default: "#fefefe"))
        width = Self.length(Self.authored(styles, "cardWidth", default: "auto"), isOffset: false)
        height = Self.length(Self.authored(styles, "cardHeight", default: "auto"), isOffset: false)
        // Compared as a parsed number rather than through `authored`'s string equality: the
        // default is documented as `0`, but a server that ever spells it `0.0` or `00` must
        // still read as "unchanged" — the string comparison alone would read that spelling as
        // authored and square every popup, which is the one regression this design exists to
        // prevent. `doubleValue` is tried first so a JSON number (`cardBorderRadius: 24`) is
        // read too, not just its string spelling — `stringValue` alone returns `nil` for a
        // `.int`/`.double` and would silently fall back to the default.
        let radiusValue = styles["cardBorderRadius"]
        let radius = radiusValue?.doubleValue ?? Double((radiusValue?.stringValue ?? "0").trimmingCharacters(in: .whitespaces))
        if let parsed = radius, parsed.isFinite, parsed > 0 {
            cornerRadius = CGFloat(parsed)
        } else {
            cornerRadius = legacyDefault
        }
        contentVerticalAlign = Self.authored(styles, "contentVerticalAlign", default: "top").flatMap { VerticalPlacement(rawValue: $0.lowercased()) } ?? .top
        positionVertical = Self.authored(styles, "cardPositionVertical", default: "auto").flatMap { VerticalPlacement(rawValue: $0.lowercased()) }
        positionHorizontal = Self.authored(styles, "cardPositionHorizontal", default: "auto").flatMap { HorizontalPlacement(rawValue: $0.lowercased()) }
        offsetVertical = Self.length(Self.authored(styles, "cardOffsetVertical", default: "auto"), isOffset: true)
        offsetHorizontal = Self.length(Self.authored(styles, "cardOffsetHorizontal", default: "auto"), isOffset: true)
    }

    /// Which screen edge a bar banner belongs to: the authored `cardPositionVertical` when there
    /// is one, else `displayPosition` as before. `center` is not an edge, so it groups with the
    /// top, the side a bar without a `displayPosition` has always gone to.
    ///
    /// Resolves just this one key rather than building a whole `BannerCardStyle` — this runs
    /// twice per bar per layout pass (`BannerOverlayContent.topBars`/`bottomBars` and
    /// `BannerBarStackView.banners`, both computed inside `body`), and the other eight keys
    /// would go unused.
    static func isBottomEdge(_ banner: BannerResponse) -> Bool {
        let vertical = Self.authored(banner.cssStyles, "cardPositionVertical", default: "auto")
            .flatMap { VerticalPlacement(rawValue: $0.lowercased()) }
        if let vertical = vertical { return vertical == .bottom }
        return banner.displayPosition == "bottom"
    }

    /// The popup card's width for a container `availableWidth` pt wide: the resolved
    /// `cardWidth` at its authored value, or `legacyDefault` (this SDK's own default of 600
    /// unless the call site passes its own `popupWidth` body-value read — see the popup call
    /// site), capped so the card never exceeds the container minus 16 pt each side.
    ///
    /// `availableWidth` must be the container the card is actually laid out in — the safe
    /// area's own width, not `UIScreen.main.bounds.width`, which is wrong whenever the window
    /// is narrower than the physical screen (iPad split view, a test window).
    ///
    /// Floored the same way `cardHeight`'s `maxHeight` is: `UIScreen.main.bounds.width` (what
    /// `availableWidth` replaces) could never be small enough for `availableWidth - 32` to go
    /// non-positive, but a `GeometryReader` reporting a narrow or zero size during an
    /// intermediate layout pass now can.
    func cardWidth(availableWidth: CGFloat, legacyDefault: CGFloat = 600) -> CGFloat {
        max(min(width?.resolved(in: availableWidth) ?? legacyDefault, availableWidth - 32), 120)
    }

    /// The popup card's fixed height when `cardHeight` is authored, clamped to `maxHeight` so
    /// an authored height still stays inside the safe area exactly as the content-hugging
    /// height does. `nil` at `cardHeight`'s default, where the card sizes to its content
    /// instead.
    func cardHeight(availableHeight: CGFloat, maxHeight: CGFloat) -> CGFloat? {
        height.map { min($0.resolved(in: availableHeight), maxHeight) }
    }

    /// The value of `key` when the author changed it, else `nil`.
    private static func authored(_ styles: [String: JSONValue], _ key: String, default fallback: String) -> String? {
        let value = (styles[key]?.stringValue ?? fallback).trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.caseInsensitiveCompare(fallback) != .orderedSame else { return nil }
        return value
    }

    /// One of the closed set of lengths the API validates: a number with `px` or with `%`.
    /// Offsets may also be a bare `0` and may be negative; a size may be neither, nor zero —
    /// a zero-extent card is not a card. Anything else — `vw`, `calc()`, a bare number as a
    /// size — is not a length and leaves the value at its default rather than reaching a
    /// layout call.
    private static func length(_ value: String?, isOffset: Bool) -> Length? {
        guard let text = value?.lowercased() else { return nil }
        if isOffset, text == "0" { return .points(0) }

        let number: String
        let make: (CGFloat) -> Length
        if text.hasSuffix("px") {
            number = String(text.dropLast(2))
            make = Length.points
        } else if text.hasSuffix("%") {
            number = String(text.dropLast(1))
            make = Length.percent
        } else {
            return nil
        }

        guard let parsed = Double(number), parsed.isFinite, isOffset || parsed > 0 else { return nil }
        return make(CGFloat(parsed))
    }
}
