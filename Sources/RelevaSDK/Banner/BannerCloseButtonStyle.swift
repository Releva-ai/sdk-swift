import SwiftUI

/// The close control's look, resolved from the close-button keys the API serves in a banner's
/// `cssStyles`. Shared contract with sdk-kotlin, sdk-react-native and sdk-flutter:
///
/// - `closeButtonColor` — the ✕ glyph colour. Default `#000`.
/// - `closeButtonBackgroundColor` — the button's fill. Default `#fff`.
/// - `closeButtonBorder` — the CSS shorthand (`1px solid #fff`). Only the width and the colour are
///   drawn, always as a solid stroke; absent, `''`, `none`, `0` or no parseable colour is NO border,
///   as on the web, which draws none by default.
/// - `closeFontSize` — the glyph size in points, clamped to 8...26. Default 14.
/// - `closeButtonBorderRadius` — the corner radius in points, capped at half the side. Default 20,
///   which is still a circle at the default size.
///
/// `closeButtonSymbol`, `closeButtonPadding`, `closeButtonFontWeight`, `closeButtonLineHeight`,
/// `closeButtonTopPosition` and `closeButtonRightPosition` are web-only and deliberately ignored:
/// the control keeps this SDK's own glyph and placement. The Unlayer design's
/// `popupCloseButton_*` body values are not read either — `cssStyles` is the only source.
///
/// Colours go through `DesignRenderer.parseColor(css:)`; every value is trimmed and
/// case-insensitive, and a blank or unparseable value reads as absent.
struct BannerCloseButtonStyle {
    struct Border {
        let width: CGFloat
        let color: Color
    }

    static let defaultFontSize: CGFloat = 14
    static let fontSizeRange: ClosedRange<CGFloat> = 8...26
    static let defaultCornerRadius: CGFloat = 20
    /// The smallest visible side — the 32 pt circle this SDK has always drawn.
    static let minimumSide: CGFloat = 32
    /// What the visible side adds around the glyph: `max(32, closeFontSize + 18)`.
    static let glyphPadding: CGFloat = 18

    let iconColor: Color
    let backgroundColor: Color
    /// `nil` draws no border.
    let border: Border?
    let fontSize: CGFloat
    /// The visible button's side: `max(32, fontSize + 18)`, so at most 44 at the 26 pt clamp —
    /// never larger than the hit box `BannerChrome.closeControlBand` is derived from.
    let side: CGFloat
    /// Already capped at half of `side`.
    let cornerRadius: CGFloat

    /// The tappable box, centred on the visible button: never below Apple's 44 pt minimum, and
    /// never below the visible side.
    var hitSide: CGFloat { max(BannerChrome.closeControlHitBox, side) }

    init(_ banner: BannerResponse) {
        self.init(cssStyles: banner.cssStyles)
    }

    init(cssStyles styles: [String: JSONValue]) {
        iconColor = DesignRenderer.parseColor(css: Self.text(styles, "closeButtonColor"))
            ?? Color(red: 0, green: 0, blue: 0)
        backgroundColor = DesignRenderer.parseColor(css: Self.text(styles, "closeButtonBackgroundColor"))
            ?? Color(red: 1, green: 1, blue: 1)
        border = Self.border(Self.text(styles, "closeButtonBorder"))

        let size = Self.number(styles, "closeFontSize").map {
            min(max($0, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
        }
        fontSize = size ?? Self.defaultFontSize
        side = max(Self.minimumSide, fontSize + Self.glyphPadding)

        let radius = Self.number(styles, "closeButtonBorderRadius").flatMap { $0 >= 0 ? $0 : nil }
        cornerRadius = min(radius ?? Self.defaultCornerRadius, side / 2)
    }

    /// The trimmed, lower-cased string value of `key`, or `nil` when absent, blank or not a
    /// string.
    private static func text(_ styles: [String: JSONValue], _ key: String) -> String? {
        guard let value = styles[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !value.isEmpty else { return nil }
        return value
    }

    /// A finite number from `key`: a JSON number, or a string spelling of one with an optional
    /// `px` unit. `nil` for anything else.
    private static func number(_ styles: [String: JSONValue], _ key: String) -> CGFloat? {
        if let value = styles[key]?.doubleValue {
            return value.isFinite ? CGFloat(value) : nil
        }
        guard let raw = text(styles, key) else { return nil }
        return pixels(raw)
    }

    /// `12`, `12px`, `1.5px` → the number; anything else → `nil`.
    private static func pixels(_ token: String) -> CGFloat? {
        let digits = token.hasSuffix("px") ? String(token.dropLast(2)) : token
        guard let value = Double(digits), value.isFinite else { return nil }
        return CGFloat(value)
    }

    /// The CSS `border` shorthand: a width token, a colour token, and any style keyword, in any
    /// order. The style is ignored — the stroke is always solid.
    static func border(_ value: String?) -> Border? {
        guard let value = value, value != "none" else { return nil }

        var width: CGFloat?
        var color: Color?
        for token in tokens(value) {
            if token == "none" { return nil }
            if width == nil, let parsed = pixels(token), parsed >= 0 {
                width = parsed
            } else if color == nil, let parsed = DesignRenderer.parseColor(css: token) {
                color = parsed
            }
        }

        let resolvedWidth = width ?? 1
        guard let resolvedColor = color, resolvedWidth > 0 else { return nil }
        return Border(width: resolvedWidth, color: resolvedColor)
    }

    /// Splits on whitespace outside parentheses, so `2px solid rgb(1, 2, 3)` is three tokens.
    private static func tokens(_ value: String) -> [String] {
        var result: [String] = []
        var current = ""
        var depth = 0
        for character in value {
            if character == "(" { depth += 1 }
            if character == ")" { depth = max(depth - 1, 0) }
            if depth == 0, character.isWhitespace {
                if !current.isEmpty { result.append(current) }
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
