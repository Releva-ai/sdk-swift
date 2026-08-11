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
        design: [String: JSONValue],
        maxWidth: CGFloat? = nil,
        transparentBody: Bool = false,
        onLinkTap: ((String) -> Void)? = nil
    ) -> some View {
        let body = design["body"]?.objectValue ?? [:]
        let bodyValues = body["values"]?.objectValue ?? [:]
        let rows = body["rows"]?.arrayValue?.compactMap { $0.objectValue } ?? []

        let backgroundColor = transparentBody ? Color.clear : (parseColor(bodyValues["backgroundColor"]) ?? .clear)
        let textColor = parseColor(bodyValues["textColor"]) ?? .black

        let contentWidthRaw = bodyValues["contentWidth"]?.stringValue ?? ""
        let isPercentWidth = contentWidthRaw.hasSuffix("%")
        let contentWidthPx = isPercentWidth ? nil : parseDimension(.string(contentWidthRaw))

        let effectiveMaxWidth = maxWidth ?? UIScreen.main.bounds.width
        let effectiveContentWidth: CGFloat? = contentWidthPx.map { min($0, effectiveMaxWidth) }

        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                buildRow(row: row, textColor: textColor, onLinkTap: onLinkTap)
            }
        }
        .frame(width: effectiveContentWidth)
        .frame(maxWidth: effectiveContentWidth == nil ? .infinity : nil, alignment: .center)
        .background(
            Group {
                if !transparentBody, let bgInfo = parseBackgroundImage(bodyValues["backgroundImage"], forceCover: true) {
                    AsyncImage(url: bgInfo.url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().aspectRatio(contentMode: bgInfo.contentMode)
                        }
                    }
                }
            }
        )
        .background(backgroundColor)
    }

    // MARK: - Row

    @ViewBuilder
    static func buildRow(
        row: [String: JSONValue],
        textColor: Color,
        onLinkTap: ((String) -> Void)?
    ) -> some View {
        let columns = row["columns"]?.arrayValue?.compactMap { $0.objectValue } ?? []
        let cells = row["cells"]?.arrayValue ?? []
        let rowValues = row["values"]?.objectValue ?? [:]

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
                        let flex = index < cells.count ? (cells[index].intValue ?? 1) : 1
                        buildColumn(column: column, textColor: textColor, onLinkTap: onLinkTap)
                            .frame(maxWidth: .infinity)
                            .layoutPriority(Double(flex))
                    }
                }
            }
        }
        .padding(padding ?? EdgeInsets())
        .background(
            Group {
                if let bgInfo = parseBackgroundImage(rowValues["backgroundImage"]) {
                    AsyncImage(url: bgInfo.url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().aspectRatio(contentMode: bgInfo.contentMode)
                        }
                    }
                }
            }
        )
        .background(effectiveBg ?? .clear)
    }

    // MARK: - Column

    @ViewBuilder
    static func buildColumn(
        column: [String: JSONValue],
        textColor: Color,
        onLinkTap: ((String) -> Void)?
    ) -> some View {
        let contents = column["contents"]?.arrayValue?.compactMap { $0.objectValue } ?? []
        let colValues = column["values"]?.objectValue ?? [:]

        let backgroundColor = parseColor(colValues["backgroundColor"])
        let padding = parseEdgeInsets(colValues["padding"])
        let borderRadius = parseDimensionRaw(colValues["borderRadius"])

        VStack(spacing: 0) {
            ForEach(Array(contents.enumerated()), id: \.offset) { _, content in
                buildContent(content: content, textColor: textColor, onLinkTap: onLinkTap)
            }
        }
        .padding(padding ?? EdgeInsets())
        .background(
            RoundedRectangle(cornerRadius: borderRadius ?? 0)
                .fill(backgroundColor ?? .clear)
        )
    }

    // MARK: - Content

    @ViewBuilder
    static func buildContent(
        content: [String: JSONValue],
        textColor: Color,
        onLinkTap: ((String) -> Void)?
    ) -> some View {
        let type = content["type"]?.stringValue ?? ""
        let values = content["values"]?.objectValue ?? [:]
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
            case "carousel":
                CarouselView(content: content, onLinkTap: onLinkTap)
            case "divider":
                buildDivider(values: values)
            default:
                EmptyView()
            }
        }
        .padding(containerPadding ?? EdgeInsets())
    }

    // MARK: - Image

    @ViewBuilder
    static func buildImage(values: [String: JSONValue], onLinkTap: ((String) -> Void)?) -> some View {
        let src = values["src"]?.objectValue ?? [:]
        let url = src["url"]?.stringValue ?? ""
        let actionValues = values["action"]?["values"]?.objectValue ?? [:]
        let href = actionValues["href"]?.stringValue ?? ""

        if !url.isEmpty, let imageUrl = URL(string: url) {
            let imageView = AsyncImage(url: imageUrl) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
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
    static func buildText(values: [String: JSONValue], defaultTextColor: Color) -> some View {
        let htmlText = values["text"]?.stringValue ?? ""
        let text = stripHtml(htmlText)

        if !text.isEmpty {
            let fontSize = parseDimensionRaw(values["fontSize"]) ?? 14
            let textAlign = parseTextAlign(values["textAlign"])
            let color = parseColor(values["color"]) ?? parseColor(values["textColor"]) ?? defaultTextColor

            Text(text)
                .font(.system(size: fontSize))
                .foregroundColor(color)
                .multilineTextAlignment(textAlign)
                .frame(maxWidth: .infinity, alignment: textAlignToAlignment(textAlign))
        }
    }

    // MARK: - Heading

    @ViewBuilder
    static func buildHeading(values: [String: JSONValue], defaultTextColor: Color) -> some View {
        let htmlText = values["text"]?.stringValue ?? ""
        let text = stripHtml(htmlText)

        if !text.isEmpty {
            let headingType = values["headingType"]?.stringValue ?? "h1"
            let fontSize = parseDimensionRaw(values["fontSize"]) ?? getHeadingFontSize(headingType)
            let textAlign = parseTextAlign(values["textAlign"])
            let color = parseColor(values["color"]) ?? parseColor(values["textColor"]) ?? defaultTextColor

            Text(text)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundColor(color)
                .multilineTextAlignment(textAlign)
                .frame(maxWidth: .infinity, alignment: textAlignToAlignment(textAlign))
        }
    }

    // MARK: - Button

    @ViewBuilder
    static func buildButton(values: [String: JSONValue], onLinkTap: ((String) -> Void)?) -> some View {
        let htmlText = values["text"]?.stringValue ?? ""
        let text = stripHtml(htmlText)

        if !text.isEmpty {
            let hrefValues = values["href"]?["values"]?.objectValue ?? [:]
            let url = hrefValues["href"]?.stringValue ?? ""

            let buttonColors = values["buttonColors"]?.objectValue ?? [:]
            let bgColor = parseColor(buttonColors["backgroundColor"]) ?? Color(red: 58 / 255, green: 174 / 255, blue: 224 / 255)
            let textColor = parseColor(buttonColors["color"]) ?? .white

            let fontSize = parseDimensionRaw(values["fontSize"]) ?? 14
            let padding = parseEdgeInsets(values["padding"]) ?? EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20)
            let borderRadius = parseDimensionRaw(values["borderRadius"]) ?? 4
            let textAlign = parseTextAlign(values["textAlign"])

            let size = values["size"]?.objectValue ?? [:]
            let autoWidth = size["autoWidth"]?.boolValue ?? true

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
    static func buildDivider(values: [String: JSONValue]) -> some View {
        let border = values["border"]?.objectValue ?? [:]
        let borderTopWidth = parseDimensionRaw(border["borderTopWidth"]) ?? 1
        let borderTopColor = parseColor(border["borderTopColor"]) ?? Color(white: 0.73)

        borderTopColor
            .frame(height: borderTopWidth)
    }

    // MARK: - Parsing Utilities

    /// Parses a backgroundImage JSON object into an image URL and content mode.
    /// - Parameters:
    ///   - value: The backgroundImage dictionary from Unlayer JSON
    ///   - forceCover: When true, always use .fill content mode
    /// - Returns: A labelled 3-tuple of (URL, ContentMode, Alignment), or nil if no valid URL.
    ///   A named type is deferred to the next major, since this is public API.
    public static func parseBackgroundImage(_ value: JSONValue?, forceCover: Bool = false) -> (url: URL, contentMode: ContentMode, alignment: Alignment)? { // swiftlint:disable:this large_tuple
        guard let bgImage = value?.objectValue,
              let urlStr = bgImage["url"]?.stringValue, !urlStr.isEmpty,
              let url = URL(string: urlStr) else { return nil }

        let contentMode: ContentMode
        if forceCover {
            contentMode = .fill
        } else {
            let size = bgImage["size"]?.stringValue ?? "cover"
            switch size {
            case "contain":
                contentMode = .fit
            case "custom":
                let customSize = bgImage["customSize"]?.arrayValue
                if let cs = customSize, cs.count == 2,
                   cs[0].stringValue?.contains("%") == true, cs[1].stringValue == "auto" {
                    contentMode = .fit  // fitWidth approximation
                } else {
                    contentMode = .fill
                }
            default:
                contentMode = .fill
            }
        }

        let position = bgImage["position"]?.stringValue ?? "center"
        let alignment: Alignment
        switch position {
        case "top-center": alignment = .top
        case "top-left": alignment = .topLeading
        case "top-right": alignment = .topTrailing
        case "bottom-center": alignment = .bottom
        case "bottom-left": alignment = .bottomLeading
        case "bottom-right": alignment = .bottomTrailing
        case "center-left": alignment = .leading
        case "center-right": alignment = .trailing
        default:
            if let customPos = bgImage["customPosition"]?.arrayValue, customPos.count == 2 {
                let x = Double("\(customPos[0].anyValue)".replacingOccurrences(of: "%", with: "")) ?? 50
                let y = Double("\(customPos[1].anyValue)".replacingOccurrences(of: "%", with: "")) ?? 50
                alignment = Alignment(
                    horizontal: x < 33 ? .leading : x > 66 ? .trailing : .center,
                    vertical: y < 33 ? .top : y > 66 ? .bottom : .center
                )
            } else {
                alignment = .center
            }
        }

        return (url, contentMode, alignment)
    }

    /// Parse a colour out of a design JSON value. Anything that is not a string is not a colour.
    public static func parseColor(_ value: JSONValue?) -> Color? {
        parseColor(css: value?.stringValue)
    }

    /// Parse a CSS colour string: `#rgb`, `#rrggbb`, `#rrggbbaa`, or `rgba(r, g, b, a)`.
    ///
    /// Colours that arrive already typed as `String` (story progress indicators, NPS appearance)
    /// call this directly rather than boxing themselves into a `JSONValue`.
    public static func parseColor(css value: String?) -> Color? {
        guard let str = value?.trimmingCharacters(in: .whitespaces), !str.isEmpty else { return nil }

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

    static func parseDimensionRaw(_ value: JSONValue?) -> CGFloat? {
        let str = "\(value?.anyValue ?? "")"
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "px", with: "")
            .replacingOccurrences(of: "em", with: "")
            .replacingOccurrences(of: "rem", with: "")
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let val = Double(str) else { return nil }
        return CGFloat(val)
    }

    static func parseDimension(_ value: JSONValue?) -> CGFloat? {
        parseDimensionRaw(value)
    }

    static func parseEdgeInsets(_ value: JSONValue?) -> EdgeInsets? {
        guard let str = value?.stringValue?.trimmingCharacters(in: .whitespaces), !str.isEmpty else { return nil }

        let parts = str.components(separatedBy: .whitespaces).compactMap { parseDimensionRaw(.string($0)) }
        switch parts.count {
        case 1: return EdgeInsets(top: parts[0], leading: parts[0], bottom: parts[0], trailing: parts[0])
        case 2: return EdgeInsets(top: parts[0], leading: parts[1], bottom: parts[0], trailing: parts[1])
        case 3: return EdgeInsets(top: parts[0], leading: parts[1], bottom: parts[2], trailing: parts[1])
        case 4: return EdgeInsets(top: parts[0], leading: parts[3], bottom: parts[2], trailing: parts[1])
        default: return nil
        }
    }

    static func parseTextAlign(_ value: JSONValue?) -> TextAlignment {
        switch value?.stringValue {
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

    static func parseLineHeight(_ value: JSONValue?) -> CGFloat? {
        guard let str = value?.stringValue else { return nil }
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
    public static func getDesignBodyValues(_ banner: BannerResponse) -> [String: JSONValue] {
        guard let design = banner.design,
              let body = design["body"]?.objectValue,
              let values = body["values"]?.objectValue else { return [:] }
        return values
    }
}

// MARK: - Carousel

/// A SwiftUI carousel view for Unlayer carousel content blocks.
/// Supports swipe navigation, left/right tap navigation, autoplay, loop, dot indicators, and preview strip.
struct CarouselView: View {
    let content: [String: JSONValue]
    let onLinkTap: ((String) -> Void)?

    @State private var currentPage: Int = 0
    @State private var autoplayTimer: Timer?

    private var values: [String: JSONValue] {
        content["values"]?.objectValue ?? [:]
    }

    private var images: [[String: JSONValue]] {
        content["embedded"]?["images"]?["values"]?.arrayValue?.compactMap { $0.objectValue } ?? []
    }

    private var autoplay: Bool { values["autoplay"]?.boolValue ?? false }
    private var loop: Bool { values["loop"]?.boolValue ?? false }
    private var showPreviews: Bool { values["showPreviews"]?.boolValue ?? false }
    private var previewWidth: CGFloat { DesignRenderer.parseDimensionRaw(values["previewWidth"]) ?? 100 }

    private var aspectRatio: CGFloat {
        let firstSrc = images.first?["src"]?.objectValue ?? [:]
        let width = firstSrc["width"]?.doubleValue ?? 16
        let height = firstSrc["height"]?.doubleValue ?? 9
        return CGFloat(width / height)
    }

    var body: some View {
        if images.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 0) {
                // Main image area with aspect ratio
                ZStack {
                    TabView(selection: $currentPage) {
                        ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                            carouselImage(image: image)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                    .aspectRatio(aspectRatio, contentMode: .fit)

                    // Left/right tap navigation overlay
                    HStack(spacing: 0) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { goPrevious() }

                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { goNext() }
                    }
                    .aspectRatio(aspectRatio, contentMode: .fit)
                }

                // Indicators
                if images.count > 1 {
                    if showPreviews {
                        previewStrip
                            .padding(.top, 8)
                    } else {
                        dotIndicators
                            .padding(.top, 8)
                    }
                }
            }
            .onAppear { startAutoplayIfNeeded() }
            .onDisappear { autoplayTimer?.invalidate() }
            .onChange(of: currentPage) { _ in
                // Reset autoplay timer on manual navigation
                if autoplay { restartAutoplay() }
            }
        }
    }

    // MARK: - Image

    @ViewBuilder
    private func carouselImage(image: [String: JSONValue]) -> some View {
        let url = image["src"]?["url"]?.stringValue ?? ""
        let href = image["action"]?["values"]?["href"]?.stringValue ?? ""

        if !url.isEmpty, let imageUrl = URL(string: url) {
            let imageView = AsyncImage(url: imageUrl) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    Color.gray.opacity(0.3)
                        .overlay(Image(systemName: "photo").foregroundColor(.gray))
                default:
                    Color.clear
                }
            }

            if !href.isEmpty, let onLinkTap = onLinkTap {
                imageView.onTapGesture { onLinkTap(href) }
            } else {
                imageView
            }
        }
    }

    // MARK: - Dot Indicators

    private var dotIndicators: some View {
        HStack(spacing: 8) {
            ForEach(0..<images.count, id: \.self) { index in
                Circle()
                    .fill(index == currentPage ? Color(white: 0.3) : Color(white: 0.8))
                    .frame(width: 8, height: 8)
            }
        }
    }

    // MARK: - Preview Strip

    private var previewStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                    let url = image["src"]?["url"]?.stringValue ?? ""

                    if !url.isEmpty, let imageUrl = URL(string: url) {
                        AsyncImage(url: imageUrl) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().scaledToFill()
                            default:
                                Color.gray.opacity(0.3)
                            }
                        }
                        .frame(width: previewWidth, height: previewWidth * 0.75)
                        .clipped()
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(index == currentPage ? Color(white: 0.3) : Color.clear, lineWidth: 2)
                        )
                        .onTapGesture {
                            withAnimation { currentPage = index }
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Navigation

    private func goNext() {
        withAnimation {
            if currentPage < images.count - 1 {
                currentPage += 1
            } else if loop {
                currentPage = 0
            }
        }
    }

    private func goPrevious() {
        withAnimation {
            if currentPage > 0 {
                currentPage -= 1
            } else if loop {
                currentPage = images.count - 1
            }
        }
    }

    // MARK: - Autoplay

    private func startAutoplayIfNeeded() {
        guard autoplay, images.count > 1 else { return }
        autoplayTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            goNext()
        }
    }

    private func restartAutoplay() {
        autoplayTimer?.invalidate()
        startAutoplayIfNeeded()
    }
}
