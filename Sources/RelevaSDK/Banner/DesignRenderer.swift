import SwiftUI

/// Renders an Unlayer design JSON (body > rows > columns > contents) as native SwiftUI views.
public struct DesignRenderer {

    /// Render a full design JSON into a SwiftUI view
    /// - Parameters:
    ///   - design: The Unlayer design JSON dictionary
    ///   - maxWidth: Maximum available width in points
    ///   - onLinkTap: Callback when a link is tapped
    /// - Returns: A SwiftUI view representing the design
    @ViewBuilder
    public static func render(
        design: [String: Any],
        maxWidth: CGFloat? = nil,
        onLinkTap: ((String) -> Void)? = nil
    ) -> some View {
        let body = design["body"] as? [String: Any] ?? [:]
        let bodyValues = body["values"] as? [String: Any] ?? [:]
        let rows = body["rows"] as? [[String: Any]] ?? []

        let backgroundColor = parseColor(bodyValues["backgroundColor"]) ?? .clear
        let textColor = parseColor(bodyValues["textColor"]) ?? .black

        let contentWidthRaw = bodyValues["contentWidth"] as? String ?? ""
        let isPercentWidth = contentWidthRaw.hasSuffix("%")
        let contentWidthPx = isPercentWidth ? nil : parseDimension(contentWidthRaw)

        let effectiveMaxWidth = maxWidth ?? UIScreen.main.bounds.width
        let effectiveContentWidth: CGFloat? = contentWidthPx.map { min($0, effectiveMaxWidth) }

        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                buildRow(row: row, textColor: textColor, onLinkTap: onLinkTap)
            }
        }
        .frame(width: effectiveContentWidth)
        .frame(maxWidth: effectiveContentWidth == nil ? .infinity : nil, alignment: .center)
        .background(backgroundColor)
    }

    // MARK: - Row

    @ViewBuilder
    static func buildRow(
        row: [String: Any],
        textColor: Color,
        onLinkTap: ((String) -> Void)?
    ) -> some View {
        let columns = row["columns"] as? [[String: Any]] ?? []
        let cells = row["cells"] as? [Any] ?? []
        let rowValues = row["values"] as? [String: Any] ?? [:]

        let bgColor = parseColor(rowValues["backgroundColor"])
        let columnsBgColor = parseColor(rowValues["columnsBackgroundColor"])
        let padding = parseEdgeInsets(rowValues["padding"])

        let effectiveBg = bgColor ?? columnsBgColor

        Group {
            if columns.count == 1 {
                buildColumn(column: columns[0], textColor: textColor, onLinkTap: onLinkTap)
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                        let flex = index < cells.count ? ((cells[index] as? NSNumber)?.intValue ?? 1) : 1
                        buildColumn(column: column, textColor: textColor, onLinkTap: onLinkTap)
                            .frame(maxWidth: .infinity)
                            .layoutPriority(Double(flex))
                    }
                }
            }
        }
        .padding(padding ?? .zero)
        .background(effectiveBg ?? .clear)
    }

    // MARK: - Column

    @ViewBuilder
    static func buildColumn(
        column: [String: Any],
        textColor: Color,
        onLinkTap: ((String) -> Void)?
    ) -> some View {
        let contents = column["contents"] as? [[String: Any]] ?? []
        let colValues = column["values"] as? [String: Any] ?? [:]

        let backgroundColor = parseColor(colValues["backgroundColor"])
        let padding = parseEdgeInsets(colValues["padding"])
        let borderRadius = parseDimensionRaw(colValues["borderRadius"])

        VStack(spacing: 0) {
            ForEach(Array(contents.enumerated()), id: \.offset) { _, content in
                buildContent(content: content, textColor: textColor, onLinkTap: onLinkTap)
            }
        }
        .padding(padding ?? .zero)
        .background(
            RoundedRectangle(cornerRadius: borderRadius ?? 0)
                .fill(backgroundColor ?? .clear)
        )
    }

    // MARK: - Content

    @ViewBuilder
    static func buildContent(
        content: [String: Any],
        textColor: Color,
        onLinkTap: ((String) -> Void)?
    ) -> some View {
        let type = content["type"] as? String ?? ""
        let values = content["values"] as? [String: Any] ?? [:]
        let containerPadding = parseEdgeInsets(values["containerPadding"])

        Group {
            switch type {
            case "image":
                buildImage(values: values, onLinkTap: onLinkTap)
            case "text":
                buildText(values: values, defaultTextColor: textColor)
            case "heading":
                buildHeading(values: values, defaultTextColor: textColor)
            case "button":
                buildButton(values: values, onLinkTap: onLinkTap)
            case "divider":
                buildDivider(values: values)
            default:
                EmptyView()
            }
        }
        .padding(containerPadding ?? .zero)
    }

    // MARK: - Image

    @ViewBuilder
    static func buildImage(values: [String: Any], onLinkTap: ((String) -> Void)?) -> some View {
        let src = values["src"] as? [String: Any] ?? [:]
        let url = src["url"] as? String ?? ""
        let action = values["action"] as? [String: Any]
        let actionValues = action?["values"] as? [String: Any] ?? [:]
        let href = actionValues["href"] as? String ?? ""

        if !url.isEmpty, let imageUrl = URL(string: url) {
            let imageView = AsyncImage(url: imageUrl) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fit)
                case .failure:
                    EmptyView()
                default:
                    Color.clear.frame(height: 100)
                }
            }

            if !href.isEmpty, let onLinkTap = onLinkTap {
                imageView.onTapGesture { onLinkTap(href) }
            } else {
                imageView
            }
        }
    }

    // MARK: - Text

    @ViewBuilder
    static func buildText(values: [String: Any], defaultTextColor: Color) -> some View {
        let htmlText = values["text"] as? String ?? ""
        let text = stripHtml(htmlText)

        if !text.isEmpty {
            let fontSize = parseDimensionRaw(values["fontSize"]) ?? 14
            let textAlign = parseTextAlign(values["textAlign"])
            let color = parseColor(values["textColor"]) ?? defaultTextColor

            Text(text)
                .font(.system(size: fontSize))
                .foregroundColor(color)
                .multilineTextAlignment(textAlign)
                .frame(maxWidth: .infinity, alignment: textAlignToAlignment(textAlign))
        }
    }

    // MARK: - Heading

    @ViewBuilder
    static func buildHeading(values: [String: Any], defaultTextColor: Color) -> some View {
        let htmlText = values["text"] as? String ?? ""
        let text = stripHtml(htmlText)

        if !text.isEmpty {
            let headingType = values["headingType"] as? String ?? "h1"
            let fontSize = parseDimensionRaw(values["fontSize"]) ?? getHeadingFontSize(headingType)
            let textAlign = parseTextAlign(values["textAlign"])
            let color = parseColor(values["textColor"]) ?? defaultTextColor

            Text(text)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundColor(color)
                .multilineTextAlignment(textAlign)
                .frame(maxWidth: .infinity, alignment: textAlignToAlignment(textAlign))
        }
    }

    // MARK: - Button

    @ViewBuilder
    static func buildButton(values: [String: Any], onLinkTap: ((String) -> Void)?) -> some View {
        let htmlText = values["text"] as? String ?? ""
        let text = stripHtml(htmlText)

        if !text.isEmpty {
            let href = values["href"] as? [String: Any]
            let hrefValues = href?["values"] as? [String: Any] ?? [:]
            let url = hrefValues["href"] as? String ?? ""

            let buttonColors = values["buttonColors"] as? [String: Any] ?? [:]
            let bgColor = parseColor(buttonColors["backgroundColor"]) ?? Color(red: 58/255, green: 174/255, blue: 224/255)
            let textColor = parseColor(buttonColors["color"]) ?? .white

            let fontSize = parseDimensionRaw(values["fontSize"]) ?? 14
            let padding = parseEdgeInsets(values["padding"]) ?? EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20)
            let borderRadius = parseDimensionRaw(values["borderRadius"]) ?? 4
            let textAlign = parseTextAlign(values["textAlign"])

            let size = values["size"] as? [String: Any] ?? [:]
            let autoWidth = size["autoWidth"] as? Bool ?? true

            let buttonContent = Text(text)
                .font(.system(size: fontSize))
                .foregroundColor(textColor)
                .padding(padding)
                .background(
                    RoundedRectangle(cornerRadius: borderRadius)
                        .fill(bgColor)
                )

            if autoWidth {
                HStack {
                    if textAlign == .center || textAlign == .trailing { Spacer() }
                    if !url.isEmpty, let onLinkTap = onLinkTap {
                        buttonContent.onTapGesture { onLinkTap(url) }
                    } else {
                        buttonContent
                    }
                    if textAlign == .center || textAlign == .leading { Spacer() }
                }
            } else {
                if !url.isEmpty, let onLinkTap = onLinkTap {
                    buttonContent.frame(maxWidth: .infinity).onTapGesture { onLinkTap(url) }
                } else {
                    buttonContent.frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Divider

    @ViewBuilder
    static func buildDivider(values: [String: Any]) -> some View {
        let border = values["border"] as? [String: Any] ?? [:]
        let borderTopWidth = parseDimensionRaw(border["borderTopWidth"]) ?? 1
        let borderTopColor = parseColor(border["borderTopColor"]) ?? Color(white: 0.73)

        borderTopColor
            .frame(height: borderTopWidth)
    }

    // MARK: - Parsing Utilities

    public static func parseColor(_ value: Any?) -> Color? {
        guard let str = (value as? String)?.trimmingCharacters(in: .whitespaces), !str.isEmpty else { return nil }

        // rgba(r, g, b, a)
        if str.hasPrefix("rgba("), str.hasSuffix(")") {
            let inner = str.dropFirst(5).dropLast(1)
            let parts = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 4,
               let r = Double(parts[0]),
               let g = Double(parts[1]),
               let b = Double(parts[2]),
               let a = Double(parts[3]) {
                return Color(red: r / 255, green: g / 255, blue: b / 255, opacity: a)
            }
        }

        // hex color
        if str.hasPrefix("#") {
            return colorFromHex(str)
        }

        return nil
    }

    static func colorFromHex(_ hex: String) -> Color? {
        var hexStr = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexStr.hasPrefix("#") { hexStr.removeFirst() }

        var rgb: UInt64 = 0
        guard Scanner(string: hexStr).scanHexInt64(&rgb) else { return nil }

        switch hexStr.count {
        case 6:
            return Color(
                red: Double((rgb >> 16) & 0xFF) / 255,
                green: Double((rgb >> 8) & 0xFF) / 255,
                blue: Double(rgb & 0xFF) / 255
            )
        case 8:
            return Color(
                red: Double((rgb >> 24) & 0xFF) / 255,
                green: Double((rgb >> 16) & 0xFF) / 255,
                blue: Double((rgb >> 8) & 0xFF) / 255,
                opacity: Double(rgb & 0xFF) / 255
            )
        default:
            return nil
        }
    }

    static func parseDimensionRaw(_ value: Any?) -> CGFloat? {
        guard let str = "\(value ?? "")".trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "px", with: "")
            .replacingOccurrences(of: "em", with: "").replacingOccurrences(of: "rem", with: "")
            .replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces) as String?,
              let val = Double(str) else { return nil }
        return CGFloat(val)
    }

    static func parseDimension(_ value: Any?) -> CGFloat? {
        return parseDimensionRaw(value)
    }

    static func parseEdgeInsets(_ value: Any?) -> EdgeInsets? {
        guard let str = (value as? String)?.trimmingCharacters(in: .whitespaces), !str.isEmpty else { return nil }

        let parts = str.components(separatedBy: .whitespaces).compactMap { parseDimensionRaw($0) }
        switch parts.count {
        case 1: return EdgeInsets(top: parts[0], leading: parts[0], bottom: parts[0], trailing: parts[0])
        case 2: return EdgeInsets(top: parts[0], leading: parts[1], bottom: parts[0], trailing: parts[1])
        case 3: return EdgeInsets(top: parts[0], leading: parts[1], bottom: parts[2], trailing: parts[1])
        case 4: return EdgeInsets(top: parts[0], leading: parts[3], bottom: parts[2], trailing: parts[1])
        default: return nil
        }
    }

    static func parseTextAlign(_ value: Any?) -> TextAlignment {
        switch value as? String {
        case "center": return .center
        case "right": return .trailing
        default: return .leading
        }
    }

    static func textAlignToAlignment(_ textAlign: TextAlignment) -> Alignment {
        switch textAlign {
        case .center: return .center
        case .trailing: return .trailing
        default: return .leading
        }
    }

    static func parseLineHeight(_ value: Any?) -> CGFloat? {
        guard let str = value as? String else { return nil }
        if str.hasSuffix("%") {
            if let val = Double(str.replacingOccurrences(of: "%", with: "")) {
                return CGFloat(val / 100)
            }
        }
        return parseDimensionRaw(value)
    }

    static func getHeadingFontSize(_ headingType: String) -> CGFloat {
        switch headingType {
        case "h1": return 32
        case "h2": return 28
        case "h3": return 24
        case "h4": return 20
        case "h5": return 18
        case "h6": return 16
        default: return 32
        }
    }

    static func stripHtml(_ html: String) -> String {
        // Remove HTML tags
        var text = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // Decode HTML entities
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extract body values from a banner's design JSON
    public static func getDesignBodyValues(_ banner: BannerResponse) -> [String: Any] {
        guard let design = banner.design,
              let body = design["body"] as? [String: Any],
              let values = body["values"] as? [String: Any] else { return [:] }
        return values
    }
}
