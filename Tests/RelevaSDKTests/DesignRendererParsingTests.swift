import XCTest
import SwiftUI
import UIKit
@testable import RelevaSDK

/// The pure parsing helpers behind `DesignRenderer`: colours, dimensions, insets, text
/// alignment, heading sizes, HTML stripping and background-image placement.
///
/// View rendering itself is out of scope — these are the value conversions that decide what a
/// banner ends up looking like, and they are the part that can be pinned without a host view.
final class DesignRendererParsingTests: XCTestCase {

    // MARK: - Helpers

    /// A named type rather than a 4-member tuple, so the members stay labelled at the
    /// call site without tripping `large_tuple`.
    private struct RGBAComponents {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
    }

    /// The sRGB components of a colour, so assertions do not depend on `Color`'s own equality.
    private func rgba(
        _ color: Color?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> RGBAComponents {
        let resolved = try XCTUnwrap(color, "expected a colour", file: file, line: line)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(
            UIColor(resolved).getRed(&red, green: &green, blue: &blue, alpha: &alpha),
            "expected an RGB-convertible colour",
            file: file,
            line: line
        )
        return RGBAComponents(
            red: Double(red),
            green: Double(green),
            blue: Double(blue),
            alpha: Double(alpha)
        )
    }

    private func assertColor(
        _ color: Color?,
        red: Double,
        green: Double,
        blue: Double,
        alpha: Double = 1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let components = try rgba(color, file: file, line: line)
        XCTAssertEqual(components.red, red, accuracy: 0.005, "red", file: file, line: line)
        XCTAssertEqual(components.green, green, accuracy: 0.005, "green", file: file, line: line)
        XCTAssertEqual(components.blue, blue, accuracy: 0.005, "blue", file: file, line: line)
        XCTAssertEqual(components.alpha, alpha, accuracy: 0.005, "alpha", file: file, line: line)
    }

    // MARK: - parseColor

    func testParseColorReadsSixDigitHex() throws {
        try assertColor(DesignRenderer.parseColor("#ff8800"), red: 1, green: 136.0 / 255, blue: 0)
    }

    func testParseColorReadsEightDigitHexAsRgba() throws {
        try assertColor(DesignRenderer.parseColor("#ff000080"), red: 1, green: 0, blue: 0, alpha: 128.0 / 255)
    }

    func testParseColorReadsFunctionalRgba() throws {
        try assertColor(
            DesignRenderer.parseColor("rgba(255, 128, 0, 0.5)"),
            red: 1,
            green: 128.0 / 255,
            blue: 0,
            alpha: 0.5
        )
    }

    func testParseColorTrimsSurroundingWhitespace() throws {
        try assertColor(DesignRenderer.parseColor("  #ffffff  "), red: 1, green: 1, blue: 1)
    }

    func testParseColorRejectsWhatItCannotUnderstand() {
        XCTAssertNil(DesignRenderer.parseColor(nil))
        XCTAssertNil(DesignRenderer.parseColor(""))
        XCTAssertNil(DesignRenderer.parseColor("   "))
        XCTAssertNil(DesignRenderer.parseColor(42), "a non-string value is not a colour")
        XCTAssertNil(DesignRenderer.parseColor("red"), "named CSS colours are not supported")
        XCTAssertNil(DesignRenderer.parseColor("rgb(255, 0, 0)"), "only the four-argument rgba form is supported")
        XCTAssertNil(DesignRenderer.parseColor("rgba(255, 0, 0)"), "an rgba missing its alpha is not usable")
        XCTAssertNil(DesignRenderer.parseColor("#nothex"))
    }

    func testParseColorDoesNotSupportThreeDigitHexShorthand() {
        XCTAssertNil(
            DesignRenderer.parseColor("#fff"),
            "#fff scans as a valid hex number but only 6- and 8-digit forms are mapped"
        )
    }

    // MARK: - colorFromHex

    func testColorFromHexAcceptsHexWithOrWithoutTheHash() throws {
        try assertColor(DesignRenderer.colorFromHex("#00ff00"), red: 0, green: 1, blue: 0)
        try assertColor(DesignRenderer.colorFromHex("00ff00"), red: 0, green: 1, blue: 0)
    }

    func testColorFromHexRejectsUnsupportedLengths() {
        XCTAssertNil(DesignRenderer.colorFromHex("#ffff"), "4 hex digits is not a supported form")
        XCTAssertNil(DesignRenderer.colorFromHex("#ffffffff0"), "9 hex digits is not a supported form")
        XCTAssertNil(DesignRenderer.colorFromHex("#zzzzzz"), "non-hex characters cannot be scanned")
    }

    // MARK: - parseDimensionRaw

    func testParseDimensionStripsPixelsPercentAndEm() {
        XCTAssertEqual(DesignRenderer.parseDimensionRaw("12px"), 12)
        XCTAssertEqual(DesignRenderer.parseDimensionRaw(" 24 px "), 24)
        XCTAssertEqual(DesignRenderer.parseDimensionRaw("50%"), 50, "the percent sign is dropped, not interpreted")
        XCTAssertEqual(DesignRenderer.parseDimensionRaw("1.5em"), 1.5)
    }

    func testParseDimensionAcceptsPlainNumbers() {
        XCTAssertEqual(DesignRenderer.parseDimensionRaw(8), 8, "Unlayer sometimes sends bare numbers")
        XCTAssertEqual(DesignRenderer.parseDimensionRaw(8.5), 8.5)
        XCTAssertEqual(DesignRenderer.parseDimensionRaw("0"), 0)
    }

    func testParseDimensionRejectsWhatIsNotANumber() {
        XCTAssertNil(DesignRenderer.parseDimensionRaw(nil))
        XCTAssertNil(DesignRenderer.parseDimensionRaw(""))
        XCTAssertNil(DesignRenderer.parseDimensionRaw("auto"))
        XCTAssertNil(DesignRenderer.parseDimensionRaw("12PX"), "unit stripping is case-sensitive")
    }

    func testParseDimensionDoesNotUnderstandRemUnits() {
        // "em" is stripped before "rem", so "2rem" is left as "2r" and fails to parse. Pinned
        // as observed behaviour rather than as an endorsement.
        XCTAssertNil(DesignRenderer.parseDimensionRaw("2rem"))
    }

    func testParseDimensionDelegatesToTheRawParser() {
        XCTAssertEqual(DesignRenderer.parseDimension("16px"), 16)
        XCTAssertNil(DesignRenderer.parseDimension("auto"))
    }

    // MARK: - parseEdgeInsets

    func testParseEdgeInsetsExpandsOneValueToAllSides() {
        XCTAssertEqual(
            DesignRenderer.parseEdgeInsets("10px"),
            EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
        )
    }

    func testParseEdgeInsetsExpandsTwoValuesToVerticalAndHorizontal() {
        XCTAssertEqual(
            DesignRenderer.parseEdgeInsets("10px 20px"),
            EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20)
        )
    }

    func testParseEdgeInsetsExpandsThreeValuesToTopHorizontalBottom() {
        XCTAssertEqual(
            DesignRenderer.parseEdgeInsets("10px 20px 30px"),
            EdgeInsets(top: 10, leading: 20, bottom: 30, trailing: 20)
        )
    }

    func testParseEdgeInsetsReadsFourValuesInCssOrder() {
        // CSS shorthand order is top right bottom left.
        XCTAssertEqual(
            DesignRenderer.parseEdgeInsets("10px 20px 30px 40px"),
            EdgeInsets(top: 10, leading: 40, bottom: 30, trailing: 20)
        )
    }

    func testParseEdgeInsetsDropsUnparseableComponents() {
        // "auto" is discarded, leaving a single value that expands to all sides.
        XCTAssertEqual(
            DesignRenderer.parseEdgeInsets("10px auto"),
            EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
        )
    }

    func testParseEdgeInsetsRejectsWhatItCannotUse() {
        XCTAssertNil(DesignRenderer.parseEdgeInsets(nil))
        XCTAssertNil(DesignRenderer.parseEdgeInsets(""))
        XCTAssertNil(DesignRenderer.parseEdgeInsets(10), "a non-string value is not shorthand")
        XCTAssertNil(DesignRenderer.parseEdgeInsets("auto"), "nothing parseable is left")
        XCTAssertNil(DesignRenderer.parseEdgeInsets("1px 2px 3px 4px 5px"), "five values is not CSS shorthand")
    }

    // MARK: - Text alignment

    func testParseTextAlignMapsCssValuesAndDefaultsToLeading() {
        XCTAssertEqual(DesignRenderer.parseTextAlign("center"), .center)
        XCTAssertEqual(DesignRenderer.parseTextAlign("right"), .trailing)
        XCTAssertEqual(DesignRenderer.parseTextAlign("left"), .leading)
        XCTAssertEqual(DesignRenderer.parseTextAlign("justify"), .leading, "unmapped values fall back to leading")
        XCTAssertEqual(DesignRenderer.parseTextAlign(nil), .leading)
        XCTAssertEqual(DesignRenderer.parseTextAlign(1), .leading, "a non-string value falls back to leading")
    }

    func testTextAlignToAlignmentMapsEachCase() {
        XCTAssertEqual(DesignRenderer.textAlignToAlignment(.center), .center)
        XCTAssertEqual(DesignRenderer.textAlignToAlignment(.trailing), .trailing)
        XCTAssertEqual(DesignRenderer.textAlignToAlignment(.leading), .leading)
    }

    // MARK: - parseLineHeight

    func testParseLineHeightConvertsPercentagesToAMultiplier() throws {
        XCTAssertEqual(try XCTUnwrap(DesignRenderer.parseLineHeight("140%")), 1.4, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(DesignRenderer.parseLineHeight("100%")), 1.0, accuracy: 0.0001)
    }

    func testParseLineHeightPassesThroughAbsoluteValues() {
        XCTAssertEqual(DesignRenderer.parseLineHeight("24px"), 24)
        XCTAssertEqual(DesignRenderer.parseLineHeight("1.5"), 1.5)
    }

    func testParseLineHeightOnlyAcceptsStrings() {
        XCTAssertNil(DesignRenderer.parseLineHeight(nil))
        XCTAssertNil(
            DesignRenderer.parseLineHeight(20),
            "unlike parseDimensionRaw, this helper requires a string and rejects bare numbers"
        )
        XCTAssertNil(DesignRenderer.parseLineHeight("normal"))
    }

    // MARK: - getHeadingFontSize

    func testHeadingFontSizesAreMappedPerLevel() {
        XCTAssertEqual(DesignRenderer.getHeadingFontSize("h1"), 32)
        XCTAssertEqual(DesignRenderer.getHeadingFontSize("h2"), 28)
        XCTAssertEqual(DesignRenderer.getHeadingFontSize("h3"), 24)
        XCTAssertEqual(DesignRenderer.getHeadingFontSize("h4"), 20)
        XCTAssertEqual(DesignRenderer.getHeadingFontSize("h5"), 18)
        XCTAssertEqual(DesignRenderer.getHeadingFontSize("h6"), 16)
    }

    func testAnUnknownHeadingLevelFallsBackToTheLargestSize() {
        XCTAssertEqual(DesignRenderer.getHeadingFontSize("H3"), 32, "the mapping is case-sensitive: H3 is not h3's 24")
        XCTAssertEqual(DesignRenderer.getHeadingFontSize("h7"), 32)
        XCTAssertEqual(DesignRenderer.getHeadingFontSize(""), 32)
    }

    // MARK: - stripHtml

    func testStripHtmlRemovesTagsAndKeepsTheText() {
        XCTAssertEqual(DesignRenderer.stripHtml("<p>Hello <b>world</b></p>"), "Hello world")
        XCTAssertEqual(DesignRenderer.stripHtml("<br/>"), "")
        XCTAssertEqual(DesignRenderer.stripHtml("<a href=\"https://example.com\">Shop</a>"), "Shop")
    }

    func testStripHtmlDecodesTheEntitiesItKnows() {
        XCTAssertEqual(DesignRenderer.stripHtml("Tom &amp; Jerry"), "Tom & Jerry")
        XCTAssertEqual(DesignRenderer.stripHtml("&quot;quoted&quot;"), "\"quoted\"")
        XCTAssertEqual(DesignRenderer.stripHtml("it&#39;s"), "it's")
        XCTAssertEqual(DesignRenderer.stripHtml("a&nbsp;b"), "a b")
    }

    func testStripHtmlDecodesEntitiesAfterRemovingTagsSoEscapedMarkupSurvives() {
        // Tags are removed first, so an escaped tag is decoded into literal text rather than
        // being stripped a second time.
        XCTAssertEqual(DesignRenderer.stripHtml("&lt;b&gt;bold&lt;/b&gt;"), "<b>bold</b>")
    }

    func testStripHtmlTrimsSurroundingWhitespace() {
        XCTAssertEqual(DesignRenderer.stripHtml("\n  <p> padded </p>\n"), "padded")
        XCTAssertEqual(DesignRenderer.stripHtml(""), "")
    }

    // MARK: - parseBackgroundImage

    func testBackgroundImageDefaultsToACenteredCover() throws {
        let parsed = try XCTUnwrap(DesignRenderer.parseBackgroundImage(["url": "https://cdn.example.com/bg.jpg"]))

        XCTAssertEqual(parsed.url.absoluteString, "https://cdn.example.com/bg.jpg")
        XCTAssertEqual(parsed.contentMode, .fill, "an unspecified size means cover")
        XCTAssertEqual(parsed.alignment, .center)
    }

    func testBackgroundImageSizeContainFits() throws {
        let parsed = try XCTUnwrap(
            DesignRenderer.parseBackgroundImage(["url": "https://cdn.example.com/bg.jpg", "size": "contain"])
        )

        XCTAssertEqual(parsed.contentMode, .fit)
    }

    func testBackgroundImageCustomFullWidthSizeFitsAndAnythingElseFills() throws {
        let fullWidth = try XCTUnwrap(DesignRenderer.parseBackgroundImage([
            "url": "https://cdn.example.com/bg.jpg",
            "size": "custom",
            "customSize": ["100%", "auto"]
        ]))
        let fixed = try XCTUnwrap(DesignRenderer.parseBackgroundImage([
            "url": "https://cdn.example.com/bg.jpg",
            "size": "custom",
            "customSize": ["100%", "50%"]
        ]))

        XCTAssertEqual(fullWidth.contentMode, .fit, "a percentage width with an automatic height is a width fit")
        XCTAssertEqual(fixed.contentMode, .fill)
    }

    func testForceCoverOverridesTheDeclaredSize() throws {
        let parsed = try XCTUnwrap(
            DesignRenderer.parseBackgroundImage(
                ["url": "https://cdn.example.com/bg.jpg", "size": "contain"],
                forceCover: true
            )
        )

        XCTAssertEqual(parsed.contentMode, .fill)
    }

    func testBackgroundImageNamedPositionsMapToAlignments() throws {
        let cases: [(String, Alignment)] = [
            ("top-center", .top),
            ("top-left", .topLeading),
            ("top-right", .topTrailing),
            ("bottom-center", .bottom),
            ("bottom-left", .bottomLeading),
            ("bottom-right", .bottomTrailing),
            ("center-left", .leading),
            ("center-right", .trailing)
            // Deliberately not "center-center": it has no `case` in the switch and
            // reaches `.center` through the `default` arm, so it would pass here
            // whatever the named mappings did. That arm is already covered by
            // testBackgroundImageDefaultsToACenteredCover, whose absent `position`
            // becomes the equally unlisted "center".
        ]

        for (position, expected) in cases {
            let parsed = try XCTUnwrap(
                DesignRenderer.parseBackgroundImage(["url": "https://cdn.example.com/bg.jpg", "position": .string(position)])
            )
            XCTAssertEqual(parsed.alignment, expected, "unexpected alignment for position \"\(position)\"")
        }
    }

    func testBackgroundImageCustomPositionIsBucketedIntoThirds() throws {
        let topLeading = try XCTUnwrap(DesignRenderer.parseBackgroundImage([
            "url": "https://cdn.example.com/bg.jpg",
            "position": "custom",
            "customPosition": ["10%", "20%"]
        ]))
        let bottomTrailing = try XCTUnwrap(DesignRenderer.parseBackgroundImage([
            "url": "https://cdn.example.com/bg.jpg",
            "position": "custom",
            "customPosition": ["90%", "80%"]
        ]))
        let middle = try XCTUnwrap(DesignRenderer.parseBackgroundImage([
            "url": "https://cdn.example.com/bg.jpg",
            "position": "custom",
            "customPosition": ["50%", "50%"]
        ]))

        XCTAssertEqual(topLeading.alignment, .topLeading)
        XCTAssertEqual(bottomTrailing.alignment, .bottomTrailing)
        XCTAssertEqual(middle.alignment, .center)
    }

    func testBackgroundImageNeedsAUsableUrl() {
        XCTAssertNil(DesignRenderer.parseBackgroundImage(nil))
        XCTAssertNil(DesignRenderer.parseBackgroundImage("https://cdn.example.com/bg.jpg"), "the value must be an object")
        XCTAssertNil(DesignRenderer.parseBackgroundImage(JSONValue.object([:])), "no url, no background")
        XCTAssertNil(DesignRenderer.parseBackgroundImage(["url": ""]), "an empty url is not a background")
        XCTAssertNil(DesignRenderer.parseBackgroundImage(["url": 42]), "a non-string url is not a background")
    }

    // MARK: - getDesignBodyValues

    func testDesignBodyValuesAreExtractedFromTheUnlayerDesign() {
        let banner = BannerResponse(token: "t", design: [
            "body": [
                "values": ["backgroundColor": "#ffffff", "contentWidth": "600px"],
                "rows": []
            ]
        ])

        let values = DesignRenderer.getDesignBodyValues(banner)

        XCTAssertEqual(values["backgroundColor"]?.stringValue, "#ffffff")
        XCTAssertEqual(values["contentWidth"]?.stringValue, "600px")
    }

    func testDesignBodyValuesAreEmptyWhenTheDesignIsMissingOrMalformed() {
        XCTAssertTrue(
            DesignRenderer.getDesignBodyValues(BannerResponse(token: "t")).isEmpty,
            "a banner without a design has no body values"
        )
        XCTAssertTrue(
            DesignRenderer.getDesignBodyValues(BannerResponse(token: "t", design: ["rows": []])).isEmpty,
            "a design without a body has no body values"
        )
        XCTAssertTrue(
            DesignRenderer.getDesignBodyValues(BannerResponse(token: "t", design: ["body": ["rows": []]])).isEmpty,
            "a body without values has no body values"
        )
    }
}
