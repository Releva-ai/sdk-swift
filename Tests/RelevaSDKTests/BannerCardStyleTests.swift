import SwiftUI
import XCTest
@testable import RelevaSDK

/// `BannerCardStyle` resolves the nine author-controlled chrome and position keys the API serves
/// in `cssStyles`. The contract those keys are written against is "a value equal to its default
/// changes nothing on this platform", so most of what is pinned here is what the type reports for
/// a default: nothing authored, and the call site left as it was.
final class BannerCardStyleTests: XCTestCase {
    /// Every key written out at the value the API documents as its default.
    private let documentedDefaults: [String: JSONValue] = [
        "cardBackgroundColor": "#fefefe",
        "cardWidth": "auto",
        "cardHeight": "auto",
        "cardBorderRadius": "0",
        "contentVerticalAlign": "top",
        "cardPositionVertical": "auto",
        "cardPositionHorizontal": "auto",
        "cardOffsetVertical": "auto",
        "cardOffsetHorizontal": "auto"
    ]

    private func style(_ cssStyles: [String: JSONValue]) -> BannerCardStyle {
        BannerCardStyle(BannerResponse(token: "t", cssStyles: cssStyles))
    }

    // MARK: - Defaults

    /// The acceptance criterion for the whole adoption: a banner whose author never opened these
    /// controls — every banner in production today — must resolve exactly like one that spells
    /// the defaults out, and neither may report a single authored value.
    func testKeysAtTheirDocumentedDefaultsResolveLikeNoKeysAtAll() {
        for cssStyles in [[:], documentedDefaults] as [[String: JSONValue]] {
            let resolved = style(cssStyles)
            XCTAssertNil(resolved.backgroundColor)
            XCTAssertNil(resolved.width)
            XCTAssertNil(resolved.height)
            XCTAssertNil(resolved.positionVertical)
            XCTAssertNil(resolved.positionHorizontal)
            XCTAssertNil(resolved.offsetVertical)
            XCTAssertNil(resolved.offsetHorizontal)
            XCTAssertEqual(resolved.contentVerticalAlign, .top)
            XCTAssertEqual(resolved.cornerRadius, 10, "the radius this SDK has always drawn")
        }
    }

    /// `cardBorderRadius` defaults to `0` in the schema, but this SDK's popup card has always been
    /// drawn with a 10 pt radius, and `BannerChrome.popup` passes this value straight into the
    /// card's `RoundedRectangle`. Mapping the default to the schema's `0` would square off every
    /// popup on iOS, so the default resolves to 10 and only an authored radius moves it.
    func testTheDefaultBorderRadiusStaysThisSdksTenPoints() {
        XCTAssertEqual(style([:]).cornerRadius, 10)
        XCTAssertEqual(style(["cardBorderRadius": "0"]).cornerRadius, 10)
        XCTAssertEqual(style(["cardBorderRadius": "24"]).cornerRadius, 24)
        XCTAssertEqual(style(["cardBorderRadius": "24px"]).cornerRadius, 10, "the key is unitless; a unit is not a number")
        XCTAssertEqual(style(["cardBorderRadius": "-4"]).cornerRadius, 10, "a negative radius is not a radius")
    }

    /// The default is documented as the literal `0`, but it is compared as a parsed number, not
    /// as a string: a server that ever spells its own default `0.0` or `00` must still read as
    /// "unchanged", or the popup this key is meant to leave alone gets squared off instead.
    func testABorderRadiusOfZeroStaysTheDefaultHoweverItIsSpelled() {
        XCTAssertEqual(style(["cardBorderRadius": "0.0"]).cornerRadius, 10)
        XCTAssertEqual(style(["cardBorderRadius": "00"]).cornerRadius, 10)
        XCTAssertEqual(style(["cardBorderRadius": " 0 "]).cornerRadius, 10)
    }

    /// The schema documents `cardBorderRadius` as a string, but `stringValue` alone returns
    /// `nil` for a JSON number, so a server that ever sends the unitless number as a `.int` or
    /// `.double` rather than its string spelling must still be read, not silently dropped to
    /// the default.
    func testABorderRadiusSentAsAJsonNumberIsStillRead() {
        XCTAssertEqual(style(["cardBorderRadius": 24]).cornerRadius, 24)
        XCTAssertEqual(style(["cardBorderRadius": 0]).cornerRadius, 10)
    }

    /// The default literals are produced in another repo, so a case or whitespace near-miss must
    /// read as "unchanged" rather than as author intent.
    func testADefaultIsRecognisedWhateverItsCaseOrSurroundingWhitespace() {
        let resolved = style([
            "cardWidth": " AUTO ",
            "cardBackgroundColor": "#FEFEFE",
            "cardPositionVertical": "Auto",
            "contentVerticalAlign": "TOP"
        ])
        XCTAssertNil(resolved.width)
        XCTAssertNil(resolved.backgroundColor)
        XCTAssertNil(resolved.positionVertical)
        XCTAssertEqual(resolved.contentVerticalAlign, .top)
    }

    func testAnAuthoredColourIsRead() {
        XCTAssertNotNil(style(["cardBackgroundColor": "#ff0000"]).backgroundColor)
        XCTAssertNil(style(["cardBackgroundColor": "rebeccapurple"]).backgroundColor, "an unparseable colour leaves the card as it was")
    }

    // MARK: - Lengths

    func testSizesAreReadInPixelsAndInPercentOfTheirAxis() {
        XCTAssertEqual(style(["cardWidth": "480px"]).width, .points(480))
        XCTAssertEqual(style(["cardHeight": "70%"]).height, .percent(70))
        XCTAssertEqual(style(["cardHeight": "70%"]).height?.resolved(in: 800), 560)
        XCTAssertEqual(style(["cardWidth": "480px"]).width?.resolved(in: 393), 480, "a pixel length ignores the axis")
    }

    /// `px` and `%` are the only units the API accepts, so the parser only has to handle those
    /// two — and anything else must fall back to the default rather than reach a layout call.
    /// A zero or negative size is rejected with them: neither is a card anyone can see.
    func testSizesRejectEverythingOutsideThatClosedSet() {
        for value in ["80vw", "calc(100% - 2rem)", "", "20", "0", "0px", "0%", "-20px", "-5%", "px", "auto%"] {
            XCTAssertNil(style(["cardWidth": .string(value)]).width, "\(value) is not a size")
        }
    }

    /// Offsets are the one place a bare `0` and a negative length are meaningful.
    func testOffsetsAllowABareZeroAndNegativeLengths() {
        XCTAssertEqual(style(["cardOffsetVertical": "0"]).offsetVertical, .points(0))
        XCTAssertEqual(style(["cardOffsetVertical": "-20px"]).offsetVertical, .points(-20))
        XCTAssertEqual(style(["cardOffsetHorizontal": "-5%"]).offsetHorizontal, .percent(-5))
        XCTAssertEqual(style(["cardOffsetHorizontal": "-5%"]).offsetHorizontal?.resolved(in: 400), -20)
    }

    func testOffsetsRejectTheSameUnitsSizesDo() {
        for value in ["80vw", "calc(100% - 2rem)", "", "20"] {
            XCTAssertNil(style(["cardOffsetHorizontal": .string(value)]).offsetHorizontal, "\(value) is not an offset")
        }
    }

    // MARK: - Popup geometry

    /// At the default, `cardWidth` reproduces exactly what the popup has always drawn: 600 pt
    /// capped to the container minus 16 pt each side — the container, not the physical screen,
    /// which is the bug this method replaces the inline `UIScreen` read to fix.
    func testCardWidthAtItsDefaultIsSixHundredCappedToTheContainer() {
        XCTAssertEqual(style([:]).cardWidth(availableWidth: 393), min(600, 393 - 32))
        XCTAssertEqual(style([:]).cardWidth(availableWidth: 1200), 600, "on a wide container the 600 pt default wins, not the cap")
    }

    /// An authored `cardWidth` still goes through the same cap, and a percentage resolves
    /// against the container passed in — never against a fixed axis, so a width and a height of
    /// different sizes cannot be swapped without a test noticing.
    func testCardWidthResolvesAnAuthoredLengthAgainstTheContainerPassedIn() {
        XCTAssertEqual(style(["cardWidth": "300px"]).cardWidth(availableWidth: 393), 300)
        XCTAssertEqual(style(["cardWidth": "50%"]).cardWidth(availableWidth: 400), 200)
        XCTAssertEqual(style(["cardWidth": "1000px"]).cardWidth(availableWidth: 393), 393 - 32, "still capped to the container")
    }

    /// At the default, `cardHeight` is `nil` — the card sizes to its content, exactly as before
    /// this key existed.
    func testCardHeightAtItsDefaultIsNil() {
        XCTAssertNil(style([:]).cardHeight(availableHeight: 800, maxHeight: 700))
    }

    /// An authored height resolves against the height passed in, then is clamped to `maxHeight`
    /// so it still stays inside the safe area exactly as the content-hugging height does.
    func testCardHeightResolvesAgainstAvailableHeightAndClampsToMaxHeight() {
        XCTAssertEqual(style(["cardHeight": "70%"]).cardHeight(availableHeight: 800, maxHeight: 700), 560)
        XCTAssertEqual(style(["cardHeight": "900px"]).cardHeight(availableHeight: 800, maxHeight: 700), 700, "clamped to maxHeight")
    }

    // MARK: - Placement

    func testPlacementsReadTheirOwnVocabularyAndNothingElse() {
        XCTAssertEqual(style(["cardPositionVertical": "bottom"]).positionVertical, .bottom)
        XCTAssertEqual(style(["cardPositionHorizontal": "LEFT"]).positionHorizontal, .left)
        XCTAssertEqual(style(["contentVerticalAlign": "center"]).contentVerticalAlign, .center)
        XCTAssertNil(style(["cardPositionVertical": "middle"]).positionVertical, "a value outside the vocabulary means nothing")
        XCTAssertNil(style(["cardPositionHorizontal": "top"]).positionHorizontal, "the two axes do not share a vocabulary")
    }

    /// Which edge a bar is pinned to. `displayPosition` is the legacy input and still decides it
    /// on its own; an authored `cardPositionVertical` takes over, including for the recommender
    /// banners that never carry a `displayPosition` at all.
    func testABarSortsToTheEdgeTheResolvedVerticalAxisNames() {
        func isBottom(displayPosition: String?, cssStyles: [String: JSONValue] = [:]) -> Bool {
            BannerCardStyle.isBottomEdge(
                BannerResponse(token: "bar", displayPosition: displayPosition, cssStyles: cssStyles)
            )
        }

        XCTAssertTrue(isBottom(displayPosition: "bottom"))
        XCTAssertFalse(isBottom(displayPosition: "top"))
        XCTAssertFalse(isBottom(displayPosition: nil))
        XCTAssertTrue(isBottom(displayPosition: nil, cssStyles: ["cardPositionVertical": "bottom"]))
        XCTAssertFalse(isBottom(displayPosition: "bottom", cssStyles: ["cardPositionVertical": "top"]))
        XCTAssertTrue(isBottom(displayPosition: "bottom", cssStyles: ["cardPositionVertical": "auto"]))
        XCTAssertFalse(isBottom(displayPosition: nil, cssStyles: ["cardPositionVertical": "center"]), "a bar has no middle; centre stays on the top edge")
    }
}
