import XCTest
@testable import RelevaSDK

/// The space each display type keeps clear for the close control, and where the control sits.
///
/// The control is drawn over the content, so a popup and a flyout keep a band at the top of their
/// content and a bar keeps a gutter on its trailing side. The numbers are sdk-react-native's
/// (`closeBandHeight`, `closeGutterWidth`): the control is placed by its visible button, and its
/// tap target grows outward around it. That the band reaches the layout is observed in
/// `BannerOverlaySnapshotTests`.
final class BannerChromeCloseControlTests: XCTestCase {
    private func style(fontSize: String? = nil) -> BannerCloseButtonStyle {
        BannerCloseButtonStyle(cssStyles: fontSize.map { ["closeFontSize": .string($0)] } ?? [:])
    }

    /// Popup and flyout: the control's 8 pt inset, its visible button and 8 of clearance — 48 at
    /// the default 32 pt button, growing with `closeFontSize`.
    func testTheBandIsTheInsetTheButtonAndEightOfClearance() {
        XCTAssertEqual(BannerChrome.closeBand(style()), 48)
        XCTAssertEqual(BannerChrome.closeBand(style(fontSize: "24")), 58, "a 42 pt button")
        XCTAssertEqual(BannerChrome.closeBand(style(fontSize: "26")), 60, "the 44 pt maximum")
    }

    /// Bar: the control's 4 pt inset, its visible button and 8 of clearance — 44 at the default.
    func testTheBarGutterIsTheInsetTheButtonAndEightOfClearance() {
        XCTAssertEqual(BannerChrome.closeGutter(style()), 44)
        XCTAssertEqual(BannerChrome.closeGutter(style(fontSize: "24")), 54)
    }

    /// The tap target is centred on the visible button, so it reaches past it by half the
    /// difference: 6 pt at the default, nothing once the button is 44 pt.
    func testTheTapTargetGrowsOutwardAroundTheVisibleButton() {
        XCTAssertEqual(BannerChrome.closeRing(style()), 6)
        XCTAssertEqual(BannerChrome.closeRing(style(fontSize: "24")), 1)
        XCTAssertEqual(BannerChrome.closeRing(style(fontSize: "26")), 0)
    }

    /// At every size the whole tap target of a popup's or a flyout's control stays inside the
    /// band, so a tap meant for the first line of the design never lands on the control.
    func testTheTapTargetFitsInTheBandAtEverySize() {
        for size in ["8", "14", "20", "24", "26"] {
            let resolved = style(fontSize: size)
            let targetBottom = BannerChrome.closeControlInset - BannerChrome.closeRing(resolved) + resolved.hitSide
            XCTAssertLessThanOrEqual(targetBottom, BannerChrome.closeBand(resolved), "closeFontSize \(size)")
        }
    }

    /// The hit box is Apple's 44 pt minimum touch target.
    func testTheHitBoxIsApplesMinimumTouchTarget() {
        XCTAssertGreaterThanOrEqual(BannerChrome.closeControlHitBox, 44)
    }
}
