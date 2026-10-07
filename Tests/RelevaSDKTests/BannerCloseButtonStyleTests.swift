import SwiftUI
import UIKit
import XCTest
@testable import RelevaSDK

/// `BannerCloseButtonStyle` resolves the close-button keys the API serves in `cssStyles` — the
/// contract shared with sdk-kotlin, sdk-react-native and sdk-flutter. The inputs below are the
/// ones qa-shared's `QA-CLS-01`…`QA-CLS-10` device rows serve, so a unit failure here and a
/// device failure there point at the same row.
final class BannerCloseButtonStyleTests: XCTestCase {
    /// What magellan-api `constants/default-popup-css-styling.js` fills every missing key with.
    private let serverDefaults: [String: JSONValue] = [
        "closeButtonColor": "#000",
        "closeFontSize": "14",
        "closeButtonBorderRadius": "20",
        "closeButtonBackgroundColor": "#fff",
        "closeButtonLineHeight": "14",
        "closeButtonPadding": "4px 5px",
        "closeButtonBorder": "",
        "closeButtonTopPosition": "-14",
        "closeButtonRightPosition": "-14",
        "closeButtonSymbol": "X",
        "closeButtonFontWeight": "400"
    ]

    private func style(_ overrides: [String: JSONValue] = [:]) -> BannerCloseButtonStyle {
        BannerCloseButtonStyle(cssStyles: serverDefaults.merging(overrides) { _, new in new })
    }

    // MARK: - Helpers

    private func assertColor(
        _ color: Color?,
        red: Double,
        green: Double,
        blue: Double,
        alpha: Double = 1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let resolved = try XCTUnwrap(color, "expected a colour", file: file, line: line)
        var actualRed: CGFloat = 0
        var actualGreen: CGFloat = 0
        var actualBlue: CGFloat = 0
        var actualAlpha: CGFloat = 0
        XCTAssertTrue(
            UIColor(resolved).getRed(&actualRed, green: &actualGreen, blue: &actualBlue, alpha: &actualAlpha),
            "expected an RGB-convertible colour",
            file: file,
            line: line
        )
        XCTAssertEqual(Double(actualRed), red, accuracy: 0.005, "red", file: file, line: line)
        XCTAssertEqual(Double(actualGreen), green, accuracy: 0.005, "green", file: file, line: line)
        XCTAssertEqual(Double(actualBlue), blue, accuracy: 0.005, "blue", file: file, line: line)
        XCTAssertEqual(Double(actualAlpha), alpha, accuracy: 0.005, "alpha", file: file, line: line)
    }

    /// Black ✕ on a white circle, no ring, 14 pt glyph in a 32 pt button — CLS-01.
    private func assertDefaultLook(
        _ resolved: BannerCloseButtonStyle,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        try assertColor(resolved.iconColor, red: 0, green: 0, blue: 0, file: file, line: line)
        try assertColor(resolved.backgroundColor, red: 1, green: 1, blue: 1, file: file, line: line)
        XCTAssertNil(resolved.border, "no border by default, as on the web", file: file, line: line)
        XCTAssertEqual(resolved.fontSize, 14, file: file, line: line)
        XCTAssertEqual(resolved.side, 32, file: file, line: line)
        XCTAssertEqual(resolved.cornerRadius, 16, "the default 20 caps at half the side: a circle", file: file, line: line)
    }

    // MARK: - QA-CLS rows

    /// CLS-01: no keys at all, and the keys the server fills in, resolve identically.
    func testCls01DefaultsAreBlackOnWhiteWithNoBorder() throws {
        try assertDefaultLook(BannerCloseButtonStyle(cssStyles: [:]))
        try assertDefaultLook(style())
    }

    func testCls02ThreeDigitHex() throws {
        let resolved = style(["closeButtonColor": "#f00", "closeButtonBackgroundColor": "#ff0"])
        try assertColor(resolved.iconColor, red: 1, green: 0, blue: 0)
        try assertColor(resolved.backgroundColor, red: 1, green: 1, blue: 0)
    }

    /// Alpha LAST: yellow, not magenta; half-transparent red, not navy.
    func testCls03EightDigitHexReadsAlphaLast() throws {
        let resolved = style(["closeButtonColor": "#ffff00ff", "closeButtonBackgroundColor": "#ff000080"])
        try assertColor(resolved.iconColor, red: 1, green: 1, blue: 0)
        try assertColor(resolved.backgroundColor, red: 1, green: 0, blue: 0, alpha: 128.0 / 255)
    }

    func testCls04BorderShorthandDrawsItsWidthAndColour() throws {
        let border = try XCTUnwrap(style(["closeButtonBorder": "2px solid #e00000"]).border)
        XCTAssertEqual(border.width, 2)
        try assertColor(border.color, red: 224.0 / 255, green: 0, blue: 0)
    }

    func testCls05FontSize24MakesA42PointButton() {
        let resolved = style(["closeFontSize": "24"])
        XCTAssertEqual(resolved.fontSize, 24)
        XCTAssertEqual(resolved.side, 42)
        XCTAssertEqual(resolved.cornerRadius, 20, "20 is under half of 42, so it is no longer a circle")
    }

    func testCls06SquareButtonInFunctionalRgb() throws {
        let resolved = style([
            "closeButtonBorderRadius": "0",
            "closeButtonColor": "rgba(255, 255, 255, 1)",
            "closeButtonBackgroundColor": "rgb(0, 160, 0)"
        ])
        XCTAssertEqual(resolved.cornerRadius, 0)
        try assertColor(resolved.iconColor, red: 1, green: 1, blue: 1)
        try assertColor(resolved.backgroundColor, red: 0, green: 160.0 / 255, blue: 0)
    }

    /// The six web-only keys change nothing, however extreme.
    func testCls07WebOnlyKeysAreIgnored() throws {
        try assertDefaultLook(style([
            "closeButtonSymbol": "CLOSE",
            "closeButtonPadding": "20px 40px",
            "closeButtonFontWeight": "900",
            "closeButtonLineHeight": "40",
            "closeButtonTopPosition": "-40",
            "closeButtonRightPosition": "-40"
        ]))
    }

    /// The design's `popupCloseButton_*` body values are no longer read: `cssStyles` only.
    func testCls08DesignCloseButtonColoursAreIgnored() throws {
        let banner = BannerResponse(
            token: "t",
            cssStyles: serverDefaults,
            design: [
                "body": [
                    "values": [
                        "popupCloseButton_iconColor": "#ff00ff",
                        "popupCloseButton_backgroundColor": "#00ff00"
                    ]
                ]
            ]
        )
        try assertDefaultLook(BannerCloseButtonStyle(banner))
    }

    func testCls09BarWhiteOnBlack() throws {
        let resolved = style(["closeButtonColor": "#fff", "closeButtonBackgroundColor": "#000"])
        try assertColor(resolved.iconColor, red: 1, green: 1, blue: 1)
        try assertColor(resolved.backgroundColor, red: 0, green: 0, blue: 0)
        XCTAssertNil(resolved.border)
    }

    func testCls10FlyoutGreenRing() throws {
        let resolved = style([
            "closeButtonColor": "#0a0",
            "closeButtonBackgroundColor": "#fff",
            "closeButtonBorder": "3px solid #0a0"
        ])
        try assertColor(resolved.iconColor, red: 0, green: 170.0 / 255, blue: 0)
        try assertColor(resolved.backgroundColor, red: 1, green: 1, blue: 1)
        let border = try XCTUnwrap(resolved.border)
        XCTAssertEqual(border.width, 3)
        try assertColor(border.color, red: 0, green: 170.0 / 255, blue: 0)
    }

    // MARK: - Colours

    func testBlankOrGarbageColoursFallBackToTheDefaults() throws {
        for value in ["", "   ", "red", "#12", "rgb(1, 2)", "#gggggg"] as [JSONValue] {
            let resolved = style(["closeButtonColor": value, "closeButtonBackgroundColor": value])
            try assertColor(resolved.iconColor, red: 0, green: 0, blue: 0)
            try assertColor(resolved.backgroundColor, red: 1, green: 1, blue: 1)
        }
        let numeric = style(["closeButtonColor": 42, "closeButtonBackgroundColor": 42])
        try assertColor(numeric.iconColor, red: 0, green: 0, blue: 0)
        try assertColor(numeric.backgroundColor, red: 1, green: 1, blue: 1)
    }

    func testFourDigitHexReadsAlphaLast() throws {
        try assertColor(style(["closeButtonBackgroundColor": "#f008"]).backgroundColor, red: 1, green: 0, blue: 0, alpha: 136.0 / 255)
    }

    func testColoursAreTrimmedAndCaseInsensitive() throws {
        try assertColor(style(["closeButtonColor": "  #F00  "]).iconColor, red: 1, green: 0, blue: 0)
        try assertColor(style(["closeButtonColor": "RGB(0, 0, 255)"]).iconColor, red: 0, green: 0, blue: 1)
        try assertColor(style(["closeButtonBackgroundColor": "Transparent"]).backgroundColor, red: 0, green: 0, blue: 0, alpha: 0)
    }

    // MARK: - Border

    func testNoBorderForBlankNoneZeroOrColourless() {
        for value in ["", "  ", "none", "NONE", "0", "0px solid #fff", "1px solid", "2px", "solid", "garbage"] {
            XCTAssertNil(style(["closeButtonBorder": .string(value)]).border, "'\(value)' must draw no border")
        }
    }

    func testBorderWidthDefaultsToOneWhenOnlyAColourIsGiven() throws {
        let border = try XCTUnwrap(style(["closeButtonBorder": "#fff"]).border)
        XCTAssertEqual(border.width, 1)
        try assertColor(border.color, red: 1, green: 1, blue: 1)
    }

    func testBorderAcceptsAnyTokenOrderAFunctionalColourAndABareWidth() throws {
        let functional = try XCTUnwrap(style(["closeButtonBorder": "2px solid rgb(1, 2, 3)"]).border)
        XCTAssertEqual(functional.width, 2)
        try assertColor(functional.color, red: 1.0 / 255, green: 2.0 / 255, blue: 3.0 / 255)

        let reordered = try XCTUnwrap(style(["closeButtonBorder": " DASHED #000 4 "]).border)
        XCTAssertEqual(reordered.width, 4, "the style keyword is ignored; a bare number is a width")
        try assertColor(reordered.color, red: 0, green: 0, blue: 0)
    }

    // MARK: - Size and radius

    func testFontSizeIsClampedAndGarbageFallsBackToTheDefault() {
        XCTAssertEqual(style(["closeFontSize": "2"]).fontSize, 8)
        XCTAssertEqual(style(["closeFontSize": "-5"]).fontSize, 8)
        XCTAssertEqual(style(["closeFontSize": "100"]).fontSize, 26)
        XCTAssertEqual(style(["closeFontSize": "20px"]).fontSize, 20)
        XCTAssertEqual(style(["closeFontSize": 18]).fontSize, 18, "a JSON number is read too")
        XCTAssertEqual(style(["closeFontSize": ""]).fontSize, 14)
        XCTAssertEqual(style(["closeFontSize": "big"]).fontSize, 14)
    }

    func testVisibleSideIsMax32OrFontSizePlus18() {
        XCTAssertEqual(style(["closeFontSize": "8"]).side, 32)
        XCTAssertEqual(style(["closeFontSize": "14"]).side, 32)
        XCTAssertEqual(style(["closeFontSize": "24"]).side, 42)
        XCTAssertEqual(style(["closeFontSize": "26"]).side, 44)
        XCTAssertEqual(style(["closeFontSize": "100"]).side, 44)
    }

    func testRadiusIsCappedAtHalfTheSide() {
        XCTAssertEqual(style(["closeButtonBorderRadius": "999"]).cornerRadius, 16)
        XCTAssertEqual(style(["closeButtonBorderRadius": "999", "closeFontSize": "26"]).cornerRadius, 22)
        XCTAssertEqual(style(["closeButtonBorderRadius": "6px"]).cornerRadius, 6)
        XCTAssertEqual(style(["closeButtonBorderRadius": ""]).cornerRadius, 16, "blank is the default 20, capped")
        XCTAssertEqual(style(["closeButtonBorderRadius": "-3"]).cornerRadius, 16, "a negative radius is not a radius")
    }

    // MARK: - Tap target

    /// The tap target never drops below Apple's 44 pt nor below the visible side, and the visible
    /// side never outgrows the hit box `BannerChrome.closeControlBand` is derived from — so card
    /// geometry is untouched by any authored size.
    func testTapTargetIsAtLeast44AndTheVisibleSideFitsTheBand() {
        for size in ["8", "14", "24", "26", "100"] {
            let resolved = style(["closeFontSize": .string(size)])
            XCTAssertGreaterThanOrEqual(resolved.hitSide, 44)
            XCTAssertGreaterThanOrEqual(resolved.hitSide, resolved.side)
            XCTAssertLessThanOrEqual(resolved.side, BannerChrome.closeControlHitBox)
        }
    }
}
