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
    /// default must not change anything — mapping it to `0` would square off every popup.
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

    init(_ banner: BannerResponse) {
        let styles = banner.cssStyles
        backgroundColor = DesignRenderer.parseColor(css: Self.authored(styles, "cardBackgroundColor", default: "#fefefe"))
        width = Self.length(Self.authored(styles, "cardWidth", default: "auto"), isOffset: false)
        height = Self.length(Self.authored(styles, "cardHeight", default: "auto"), isOffset: false)
        let radius = Self.authored(styles, "cardBorderRadius", default: "0").flatMap { Double($0) }
        if let radius = radius, radius.isFinite, radius >= 0 {
            cornerRadius = CGFloat(radius)
        } else {
            cornerRadius = 10
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
    static func isBottomEdge(_ banner: BannerResponse) -> Bool {
        if let vertical = BannerCardStyle(banner).positionVertical { return vertical == .bottom }
        return banner.displayPosition == "bottom"
    }

    /// The value of `key` when the author changed it, else `nil`.
    private static func authored(_ styles: [String: JSONValue], _ key: String, default fallback: String) -> String? {
        let value = (styles[key]?.stringValue ?? fallback).trimmingCharacters(in: .whitespaces)
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
