import SwiftUI
import UIKit
import XCTest
@testable import RelevaSDK

/// The accessibility identifiers device QA reads, asserted on the accessibility tree UI
/// automation sees: `releva-banner-close` on the close control's whole tap target,
/// `releva-banner-<token>` on each banner's own view (a popup's or a flyout's card, a bar's
/// layer), and `releva-banner-placement` on the box a popup or a sized flyout is placed in.
///
/// SwiftUI builds that tree only while accessibility is on, so each test turns on the automation
/// mode XCUITest itself uses, and turns it off afterwards.
final class BannerAccessibilityIdentifierTests: XCTestCase {
    private static let windowSize = CGSize(width: 393, height: 852)
    private static let copy = "Hello from the banner"

    override func setUp() {
        super.setUp()
        AccessibilityTree.setAutomation(enabled: true)
    }

    override func tearDown() {
        AccessibilityTree.setAutomation(enabled: false)
        super.tearDown()
    }

    // MARK: - Harness

    /// Lays the overlay out in the production `BannerOverlayWindow`, iPhone-sized with a status
    /// bar and a home indicator, and hands `check` its accessibility tree, the frames the SDK
    /// reported for hit-testing, and the hosting view's safe area in window coordinates.
    @MainActor
    private func overlay(
        configure: (BannerDisplayViewModel) -> Void,
        check: (_ tree: AXNode, _ reported: [CGRect], _ safeArea: CGRect) throws -> Void
    ) throws {
        let viewModel = BannerDisplayViewModel()
        configure(viewModel)
        let host = BannerOverlayHost.shared
        host.attach(viewModel) { _ in }

        let controller = BannerOverlayHostingController(rootView: BannerOverlayRoot(host: host))
        controller.host = host
        controller.view.backgroundColor = .clear
        controller.additionalSafeAreaInsets = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        let window = BannerOverlayWindow(frame: CGRect(origin: .zero, size: Self.windowSize))
        window.host = host
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        drainMainQueue(turns: 6)
        window.layoutIfNeeded()
        defer {
            host.detach(viewModel)
            window.isHidden = true
        }

        let safeArea = controller.view.convert(controller.view.safeAreaLayoutGuide.layoutFrame, to: window)
        let tree = AccessibilityTree.tree(of: window)
        let failuresBefore = testRun?.totalFailureCount ?? 0
        defer {
            if (testRun?.totalFailureCount ?? 0) > failuresBefore { print(AccessibilityTree.describe(tree)) }
        }
        try check(tree, host.interactiveFrames, safeArea)
    }

    @MainActor
    private func design() -> [String: JSONValue] {
        [
            "body": [
                "values": ["popupWidth": "600px", "contentWidth": "500px"],
                "rows": [[
                    "values": ["backgroundColor": "#3A3FE0", "padding": "0px"],
                    "columns": [[
                        "values": [:],
                        "contents": [
                            ["type": "text", "values": ["text": .string("<p>\(Self.copy)</p>"), "fontSize": "18px", "containerPadding": "20px 10px", "color": "#FFFFFF"]]
                        ]
                    ]]
                ]]
            ]
        ]
    }

    // MARK: - Shared assertions

    /// The banner's id sits on exactly one element, a container with the banner's frame, and the
    /// close control and the copy stay separate elements without that id. A popup's or a flyout's
    /// id is on its card, which contains them; a bar's is on its layer, an empty element behind the
    /// card, so its frame stays the layer's when the card is moved.
    @MainActor
    private func assertBanner(
        _ token: String,
        in tree: AXNode,
        frame expected: CGRect,
        containsContent: Bool = true,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> AXNode {
        let matches = tree.nodes(BannerAccessibilityID.banner(token))
        XCTAssertEqual(matches.count, 1, "releva-banner-\(token) on exactly one element", file: file, line: line)
        let banner = try XCTUnwrap(matches.first, "no element carries releva-banner-\(token)", file: file, line: line)
        XCTAssertFalse(banner.isElement, "a container, so the views inside stay reachable", file: file, line: line)
        assertFrame(banner.frame, expected, "releva-banner-\(token) has the banner's frame", file: file, line: line)

        XCTAssertEqual(tree.nodes(BannerAccessibilityID.close).count, 1, "releva-banner-close on exactly one element", file: file, line: line)
        let scope = containsContent ? banner : tree
        let close = try XCTUnwrap(scope.nodes(BannerAccessibilityID.close).first, "the close control is in the tree", file: file, line: line)
        XCTAssertTrue(close.isElement, file: file, line: line)
        XCTAssertEqual(close.label, "Close", file: file, line: line)
        XCTAssertTrue(close.traits.contains(.button), "the close control keeps the button trait", file: file, line: line)

        let copy = scope.flattened.filter { $0.isElement && $0.label.contains(Self.copy) }
        XCTAssertFalse(copy.isEmpty, "the copy is its own element", file: file, line: line)
        XCTAssertTrue(copy.allSatisfy { $0.identifier.isEmpty }, "the banner's id does not spread to its copy", file: file, line: line)
        return close
    }

    /// The close element's frame is the whole tap target, centred on the visible button, which
    /// sits `inset` in from the card's top and its leading or trailing edge.
    @MainActor
    private func assertCloseIsTheHitBox(
        _ close: AXNode,
        in card: CGRect,
        inset: CGFloat = BannerChrome.closeControlInset,
        top: CGFloat? = nil,
        leading: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let style = BannerCloseButtonStyle(cssStyles: [:])
        XCTAssertLessThan(style.side, style.hitSide, "at the default size the visible button is smaller than its tap target", file: file, line: line)
        let ring = BannerChrome.closeRing(style)
        let minX = leading ? card.minX + inset - ring : card.maxX - inset + ring - style.hitSide
        assertFrame(
            close.frame,
            CGRect(x: minX, y: top ?? card.minY + inset - ring, width: style.hitSide, height: style.hitSide),
            "releva-banner-close is the tap target",
            file: file,
            line: line
        )
    }

    // MARK: - Popup

    @MainActor
    func testPopupCardPlacementAndCloseCarryTheirIds() throws {
        try overlay { vm in
            vm.popupBanner = BannerResponse(token: "popup-1", displayType: "popup", design: design())
        } check: { tree, reported, safeArea in
            let card = try XCTUnwrap(reported.first, "the popup reported no card frame")
            let close = try assertBanner("popup-1", in: tree, frame: card)
            assertCloseIsTheHitBox(close, in: card)

            let placement = tree.nodes(BannerAccessibilityID.placement)
            XCTAssertEqual(placement.count, 1, "a popup is always placed in the safe area")
            assertFrame(try XCTUnwrap(placement.first).frame, safeArea, "releva-banner-placement is the safe-area box")
            XCTAssertTrue(safeArea.contains(card), "the card sits inside the box")
        }
    }

    /// With nothing accessible in the design, the card's id stays on the card rather than moving
    /// to the close control, its only child.
    /// A content-sized card placed against the safe area's top edge: its id's frame is the card,
    /// not the card extended up through the status bar.
    @MainActor
    func testAPopupAgainstTheSafeAreaTopKeepsItsIdOnTheDrawnCard() throws {
        try overlay { vm in
            vm.popupBanner = BannerResponse(
                token: "popup-top-right",
                displayType: "popup",
                cssStyles: ["cardPositionVertical": "top", "cardPositionHorizontal": "right", "cardBackgroundColor": "#ff00ff"],
                design: design()
            )
        } check: { tree, reported, safeArea in
            let card = try XCTUnwrap(reported.first, "the popup reported no card frame")
            XCTAssertEqual(card.minY, safeArea.minY, accuracy: 0.5, "the card sits against the safe area's top")
            XCTAssertEqual(card.maxX, safeArea.maxX, accuracy: 0.5, "and its right")
            let close = try assertBanner("popup-top-right", in: tree, frame: card)
            assertCloseIsTheHitBox(close, in: card)
        }
    }

    @MainActor
    func testAPopupWithNothingAccessibleInsideKeepsItsIdOnTheCard() throws {
        let dividerOnly: [String: JSONValue] = [
            "body": [
                "values": ["popupWidth": "300px"],
                "rows": [[
                    "values": ["padding": "0px"],
                    "columns": [[
                        "values": [:],
                        "contents": [["type": "divider", "values": ["containerPadding": "40px"]]]
                    ]]
                ]]
            ]
        ]
        try overlay { vm in
            vm.popupBanner = BannerResponse(token: "popup-bare", displayType: "popup", design: dividerOnly)
        } check: { tree, reported, _ in
            let card = try XCTUnwrap(reported.first, "the popup reported no card frame")
            let banner = try XCTUnwrap(tree.nodes(BannerAccessibilityID.banner("popup-bare")).first, "no element carries releva-banner-popup-bare")
            XCTAssertFalse(banner.isElement)
            assertFrame(banner.frame, card, "releva-banner-popup-bare has the card's frame")
            XCTAssertEqual(banner.flattened.filter(\.isElement).count, 1, "the close control is the only element inside")
            let close = try XCTUnwrap(banner.nodes(BannerAccessibilityID.close).first, "the close control is inside the card")
            XCTAssertTrue(close.isElement)
            assertCloseIsTheHitBox(close, in: card)
        }
    }

    // MARK: - Bars

    /// A top bar's layer spans the width from the safe-area top, and its card carries no
    /// status-bar padding, so the control's visible button sits 4 below the card's top and 4 in
    /// from the right, its tap target reaching 2 past the card's edges.
    @MainActor
    func testTopBarLayerAndCloseCarryTheirIds() throws {
        try overlay { vm in
            vm.barBanners = [BannerResponse(token: "bar-top", displayType: "bar", displayPosition: "top", design: design())]
        } check: { tree, reported, safeArea in
            let card = try XCTUnwrap(reported.max { $0.width * $0.height < $1.width * $1.height }, "the bar reported no frame")
            // At least the host's safe-area top; the key window's inset can raise it.
            XCTAssertGreaterThanOrEqual(card.minY, safeArea.minY - 0.5, "the card starts below the status bar")
            XCTAssertEqual(card.width, Self.windowSize.width, accuracy: 0.5)
            let close = try assertBanner("bar-top", in: tree, frame: card, containsContent: false)
            assertCloseIsTheHitBox(close, in: card, inset: BannerChrome.barCloseInset)
            XCTAssertTrue(
                reported.contains { abs($0.minX - close.frame.minX) < 0.5 && abs($0.minY - close.frame.minY) < 0.5 },
                "the control's tap target claims touches where it reaches past the card"
            )
            XCTAssertTrue(tree.nodes(BannerAccessibilityID.placement).isEmpty, "a bar has no placement box")
        }
    }

    /// A bottom bar's control sits 4 above its content's top edge, as in sdk-react-native.
    @MainActor
    func testBottomBarLayerAndCloseCarryTheirIds() throws {
        try overlay { vm in
            vm.barBanners = [BannerResponse(token: "bar-bottom", displayType: "bar", displayPosition: "bottom", design: design())]
        } check: { tree, reported, _ in
            let card = try XCTUnwrap(reported.max { $0.width * $0.height < $1.width * $1.height }, "the bar reported no frame")
            XCTAssertEqual(card.maxY, Self.windowSize.height, accuracy: 0.5, "the full card, home-indicator padding included")
            let close = try assertBanner("bar-bottom", in: tree, frame: card, containsContent: false)
            let ring = BannerChrome.closeRing(BannerCloseButtonStyle(cssStyles: [:]))
            assertCloseIsTheHitBox(close, in: card, inset: BannerChrome.barCloseInset, top: card.minY - BannerChrome.barCloseInset - ring)
            XCTAssertTrue(tree.nodes(BannerAccessibilityID.placement).isEmpty, "a bar has no placement box")
        }
    }

    /// A centred, narrowed bar: the layer spans the window below the status bar, the card does not.
    @MainActor
    func testACentredBarsLayerSpansTheWindowBelowTheStatusBar() throws {
        try overlay { vm in
            vm.barBanners = [BannerResponse(
                token: "bar-centre",
                displayType: "bar",
                displayPosition: "top",
                cssStyles: ["cardPositionVertical": "center", "cardWidth": "200px"],
                design: design()
            )]
        } check: { tree, reported, safeArea in
            let card = try XCTUnwrap(reported.max { $0.width * $0.height < $1.width * $1.height }, "the bar reported no frame")
            XCTAssertEqual(card.width, 200, accuracy: 0.5)
            let layer = try XCTUnwrap(tree.nodes(BannerAccessibilityID.banner("bar-centre")).first, "no element carries releva-banner-bar-centre")
            // At least the host's safe-area top; the key window's inset can raise it.
            XCTAssertGreaterThanOrEqual(layer.frame.minY, safeArea.minY - 0.5, "from below the status bar")
            XCTAssertEqual(layer.frame.maxY, Self.windowSize.height, accuracy: 0.5, "down to the window's bottom")
            XCTAssertEqual(card.midY, layer.frame.midY, accuracy: 1, "the card centred in it")
            _ = try assertBanner(
                "bar-centre",
                in: tree,
                frame: CGRect(x: 0, y: layer.frame.minY, width: Self.windowSize.width, height: Self.windowSize.height - layer.frame.minY),
                containsContent: false
            )
        }
    }

    // MARK: - Flyouts

    @MainActor
    func testLeftFlyoutCarriesItsIdAndNoPlacement() throws {
        try overlay { vm in
            vm.flyoutBanner = BannerResponse(token: "fly-left", displayType: "flyout", displayPosition: "left", design: design())
        } check: { tree, reported, safeArea in
            let panel = try XCTUnwrap(reported.first, "the flyout reported no frame")
            XCTAssertEqual(panel.minX, 0, accuracy: 0.5)
            let close = try assertBanner("fly-left", in: tree, frame: panel)
            let ring = BannerChrome.closeRing(BannerCloseButtonStyle(cssStyles: [:]))
            assertCloseIsTheHitBox(close, in: panel, top: safeArea.minY + BannerChrome.closeControlInset - ring)
            XCTAssertTrue(tree.nodes(BannerAccessibilityID.placement).isEmpty, "an unsized flyout has no placement box")
        }
    }

    /// A right-hand flyout's control sits on its inner, leading edge.
    @MainActor
    func testRightFlyoutCarriesItsIdAndItsCloseOnTheInnerEdge() throws {
        try overlay { vm in
            vm.flyoutBanner = BannerResponse(token: "fly-right", displayType: "flyout", displayPosition: "right", design: design())
        } check: { tree, reported, safeArea in
            let panel = try XCTUnwrap(reported.first, "the flyout reported no frame")
            XCTAssertEqual(panel.maxX, Self.windowSize.width, accuracy: 0.5)
            let close = try assertBanner("fly-right", in: tree, frame: panel)
            let ring = BannerChrome.closeRing(BannerCloseButtonStyle(cssStyles: [:]))
            assertCloseIsTheHitBox(close, in: panel, top: safeArea.minY + BannerChrome.closeControlInset - ring, leading: true)
            XCTAssertTrue(tree.nodes(BannerAccessibilityID.placement).isEmpty, "an unsized flyout has no placement box")
        }
    }

    /// A sized flyout is placed in the safe area and carries that box; its control is not inset
    /// again.
    @MainActor
    func testASizedFlyoutCarriesItsPlacementBox() throws {
        try overlay { vm in
            vm.flyoutBanner = BannerResponse(token: "fly-sized", displayType: "flyout", displayPosition: "right", cssStyles: ["cardWidth": "200px"], design: design())
        } check: { tree, reported, safeArea in
            let panel = try XCTUnwrap(reported.first, "the flyout reported no frame")
            XCTAssertEqual(panel.width, 200, accuracy: 0.5)
            assertFrame(panel, CGRect(x: safeArea.maxX - 200, y: safeArea.minY, width: 200, height: safeArea.height), "the card fills the box's height")
            let close = try assertBanner("fly-sized", in: tree, frame: panel)
            assertCloseIsTheHitBox(close, in: panel, leading: true)

            let placement = tree.nodes(BannerAccessibilityID.placement)
            XCTAssertEqual(placement.count, 1, "a sized flyout carries its placement box")
            assertFrame(try XCTUnwrap(placement.first).frame, safeArea, "releva-banner-placement is the safe-area box")
        }
    }

    // MARK: - Static

    @MainActor
    func testAStaticBannerContainerCarriesItsId() throws {
        final class Measured { var frame: CGRect = .null }
        let measured = Measured()
        let banner = BannerResponse(token: "static-1", displayType: "static", design: design())
        let view = VStack(spacing: 0) {
            Color.gray.frame(height: 120)
            BannerChrome.inline(banner) { _ in }
                .background(GeometryReader { geometry in
                    Color.clear.onAppear { measured.frame = geometry.frame(in: .global) }
                })
            Spacer()
        }
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        drainMainQueue(turns: 4)
        window.layoutIfNeeded()
        defer { window.isHidden = true }

        let tree = AccessibilityTree.tree(of: window)
        XCTAssertFalse(measured.frame.isNull, "the static banner was not laid out")
        let matches = tree.nodes(BannerAccessibilityID.banner("static-1"))
        XCTAssertEqual(matches.count, 1, "releva-banner-static-1 on exactly one element\n\(AccessibilityTree.describe(tree))")
        let container = try XCTUnwrap(matches.first)
        XCTAssertFalse(container.isElement, "a container, so the views inside stay reachable")
        assertFrame(container.frame, measured.frame, "releva-banner-static-1 has the banner's frame")

        let copy = container.flattened.filter { $0.isElement && $0.label.contains(Self.copy) }
        XCTAssertFalse(copy.isEmpty, "the copy is its own element inside the banner")
        XCTAssertTrue(copy.allSatisfy { $0.identifier.isEmpty }, "the banner's id does not spread to its copy")
        XCTAssertTrue(tree.nodes(BannerAccessibilityID.close).isEmpty, "a static banner has no close control")
        XCTAssertTrue(tree.nodes(BannerAccessibilityID.placement).isEmpty, "a static banner has no placement box")
    }
}
