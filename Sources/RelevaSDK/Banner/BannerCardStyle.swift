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

    /// Where a card sits on one axis once the keys and `displayPosition` are resolved, as
    /// sdk-react-native's `resolveBannerChrome` reports it. `stretch` fills the axis: the bar's
    /// width, the flyout's height and both popup axes when nothing moved them.
    enum Anchor: Equatable {
        case start, center, end, stretch

        init(_ placement: HorizontalPlacement) {
            switch placement {
            case .left: self = .start
            case .center: self = .center
            case .right: self = .end
            }
        }

        init(_ placement: VerticalPlacement) {
            switch placement {
            case .top: self = .start
            case .center: self = .center
            case .bottom: self = .end
            }
        }

        /// The translation `offset` applies on an axis with this anchor: an end anchor negates,
        /// so a positive offset is always a gap from the edge the card is anchored to.
        func translation(_ offset: Length?, in extent: CGFloat) -> CGFloat {
            let raw = offset?.resolved(in: extent) ?? 0
            return self == .end ? -raw : raw
        }
    }

    /// The display types a card's anchors are resolved for; `displayPosition` decides the bar's
    /// vertical axis and the flyout's horizontal one, and nothing on a popup.
    enum Kind {
        case bar, flyout, popup
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
    /// `cardBorderRadius` when the author set one above zero, else `nil`: the bar and the flyout
    /// are square unless a radius is authored.
    let authoredCornerRadius: CGFloat?
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

    /// The translation `cardOffsetHorizontal` applies to a popup card, after the anchor's sign rule.
    ///
    /// A positive offset moves the card AWAY FROM THE EDGE IT IS ANCHORED TO, so a `right`
    /// placement negates it; `left`, `center` and an unauthored axis have no edge to move away
    /// from on that reading and take it as rightward. The contract is magellan-api
    /// `constants/banner-chrome-css-styles.md` — "an offset is a gap from an edge and not a
    /// dimension", `0` is "flush against the edge", and `-20px` "lets a flyout bleed slightly
    /// past the viewport edge", which only has that meaning if the positive direction is inward.
    func offsetTranslationX(in width: CGFloat) -> CGFloat {
        anchors(for: .popup, displayPosition: nil).horizontal.translation(offsetHorizontal, in: width)
    }

    /// The vertical twin of `offsetTranslationX(in:)`; a `bottom` placement negates.
    func offsetTranslationY(in height: CGFloat) -> CGFloat {
        anchors(for: .popup, displayPosition: nil).vertical.translation(offsetVertical, in: height)
    }

    /// Both axes' anchors for a card of `kind`. An authored position wins; otherwise
    /// `displayPosition` decides the bar's vertical axis (`top`/`bottom`, top otherwise) and the
    /// flyout's horizontal one (`left`/`right`, right otherwise), and every other axis stretches.
    func anchors(for kind: Kind, displayPosition: String?) -> (horizontal: Anchor, vertical: Anchor) {
        let horizontal: Anchor
        if let placement = positionHorizontal {
            horizontal = Anchor(placement)
        } else if kind == .flyout {
            horizontal = displayPosition == "left" ? .start : .end
        } else {
            horizontal = .stretch
        }

        let vertical: Anchor
        if let placement = positionVertical {
            vertical = Anchor(placement)
        } else if kind == .bar {
            vertical = displayPosition == "bottom" ? .end : .start
        } else {
            vertical = .stretch
        }
        return (horizontal, vertical)
    }

    /// The translation both offset keys apply to a card with these anchors. A percentage
    /// resolves against `extent`, the window on that axis.
    func offsetTranslation(horizontal: Anchor, vertical: Anchor, in extent: CGSize) -> CGSize {
        CGSize(
            width: horizontal.translation(offsetHorizontal, in: extent.width),
            height: vertical.translation(offsetVertical, in: extent.height)
        )
    }

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
            authoredCornerRadius = CGFloat(parsed)
        } else {
            cornerRadius = legacyDefault
            authoredCornerRadius = nil
        }
        contentVerticalAlign = Self.authored(styles, "contentVerticalAlign", default: "top").flatMap { VerticalPlacement(rawValue: $0.lowercased()) } ?? .top
        positionVertical = Self.authored(styles, "cardPositionVertical", default: "auto").flatMap { VerticalPlacement(rawValue: $0.lowercased()) }
        positionHorizontal = Self.authored(styles, "cardPositionHorizontal", default: "auto").flatMap { HorizontalPlacement(rawValue: $0.lowercased()) }
        offsetVertical = Self.length(Self.authored(styles, "cardOffsetVertical", default: "auto"), isOffset: true)
        offsetHorizontal = Self.length(Self.authored(styles, "cardOffsetHorizontal", default: "auto"), isOffset: true)
    }

    /// Where a bar sits vertically: the authored `cardPositionVertical` when there is one, else
    /// `displayPosition` (`bottom` is the bottom edge, anything else the top). Never `stretch`.
    ///
    /// Resolves just this one key rather than building a whole `BannerCardStyle`: the overlay
    /// and the presenter sort their bars by it inside `body`.
    static func barVerticalAnchor(_ banner: BannerResponse) -> Anchor {
        let vertical = Self.authored(banner.cssStyles, "cardPositionVertical", default: "auto")
            .flatMap { VerticalPlacement(rawValue: $0.lowercased()) }
        if let vertical = vertical { return Anchor(vertical) }
        return banner.displayPosition == "bottom" ? .end : .start
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
