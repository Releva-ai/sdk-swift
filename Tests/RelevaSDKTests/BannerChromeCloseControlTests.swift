import XCTest
@testable import RelevaSDK

/// The band the close control owns, and why it is asserted here rather than off a rendered
/// frame.
///
/// THE CONTROL IS DRAWN OVER THE CONTENT on every display type — it is a `ZStack` sibling, not
/// a view in flow beside it — so each one reserves `closeControlBand` for it: a bar on its
/// trailing edge, a popup and a flyout at the top. Without that, a design laid out to the full
/// width runs underneath it and the tail of a headline is painted beneath the glyph.
/// sdk-react-native photographed exactly that on 2026-10-03, where a narrow card's copy read
/// `CHR-08 bottom-left offse✕`.
///
/// WHAT THIS CAN AND CANNOT PROVE. It pins the band against the control's own geometry, so the
/// two cannot drift: raise the hit box for accessibility and the band has to follow, or this
/// fails. It does NOT prove the band is applied — that it reaches the padding and the height
/// budget at each of the three call sites. Measuring that needs the content's frame, and
/// `BannerOverlaySnapshotTests` records why this harness cannot see it: SwiftUI accessibility
/// identifiers do not surface as `UIView` identifiers, and the only frames the SDK publishes
/// are the touch-claiming ones it needs for hit-testing. Application is covered by the iOS
/// device pass, which is where the other three SDKs' equivalents were caught in the first place.
final class BannerChromeCloseControlTests: XCTestCase {
    /// The band has to contain the whole control, not just the circle that is visible: this SDK
    /// pads the tappable area out to Apple's minimum, so the box to clear is larger than the
    /// glyph. 56 against a 52pt control leaves 4 of clearance.
    func testTheBandCoversTheControlsWholeFootprint() {
        let footprint = BannerChrome.closeControlInset + BannerChrome.closeControlHitBox
        XCTAssertGreaterThanOrEqual(BannerChrome.closeControlBand, footprint, "copy inside the band would be drawn under the control")
        XCTAssertLessThanOrEqual(BannerChrome.closeControlBand - footprint, 12, "a band far wider than the control is wasted card")
    }

    /// Derived, not chosen. A literal here would silently stop covering the control the moment
    /// either constant moved, which is the drift the derivation exists to prevent.
    func testTheBandIsDerivedFromTheControlRatherThanHardCoded() {
        XCTAssertEqual(BannerChrome.closeControlBand, BannerChrome.closeControlInset + BannerChrome.closeControlHitBox + 4)
    }

    /// The hit box is Apple's 44pt minimum touch target, which is why the band is bigger than
    /// the 44/48 sdk-kotlin and sdk-flutter reserve — their controls are not padded out to it.
    func testTheHitBoxIsApplesMinimumTouchTarget() {
        XCTAssertGreaterThanOrEqual(BannerChrome.closeControlHitBox, 44)
    }
}
