import SwiftUI
import UIKit
import XCTest
@testable import RelevaSDK

/// The accessibility identifiers device QA reads, asserted on the accessibility tree UI
/// automation sees: `releva-banner-close` on the close control's whole tap target,
/// `releva-banner-<token>` on each banner's own view, and `releva-banner-placement` on the box a
/// popup or a sized flyout is placed in.
///
/// SwiftUI builds that tree only while accessibility is on, so each test turns on the automation
/// mode XCUITest itself uses, and turns it off afterwards.
final class BannerAccessibilityIdentifierTests: XCTestCase {
    /// One element of the accessibility tree, with its children.
    private struct AXNode {
        let identifier: String
        let label: String
        let frame: CGRect
        let isElement: Bool
        let traits: UIAccessibilityTraits
        let children: [AXNode]

        /// This node and every node below it, depth first.
        var flattened: [AXNode] { [self] + children.flatMap(\.flattened) }

        func nodes(_ identifier: String) -> [AXNode] { flattened.filter { $0.identifier == identifier } }
    }

    private static let windowSize = CGSize(width: 393, height: 852)
    private static let copy = "Hello from the banner"

    override func setUp() {
        super.setUp()
        Self.setAutomation(enabled: true)
    }

    override func tearDown() {
        Self.setAutomation(enabled: false)
        super.tearDown()
    }

    /// `_AXSSetAutomationEnabled`, which XCUITest calls to make an app build its accessibility tree.
    private static func setAutomation(enabled: Bool) {
        guard let handle = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
              let symbol = dlsym(handle, "_AXSSetAutomationEnabled") else {
            return XCTFail("libAccessibility's _AXSSetAutomationEnabled is unavailable, so the accessibility tree cannot be read")
        }
        typealias SetEnabled = @convention(c) (Int32) -> Void
        unsafeBitCast(symbol, to: SetEnabled.self)(enabled ? 1 : 0)
    }

    private static func tree(of object: NSObject) -> AXNode {
        var children: [NSObject] = []
        let count = object.accessibilityElementCount()
        if let elements = object.accessibilityElements as? [NSObject] {
            children = elements
        } else if count != NSNotFound, count > 0 {
            children = (0..<count).compactMap { object.accessibilityElement(at: $0) as? NSObject }
        } else if let view = object as? UIView {
            children = view.subviews
        }
        let identifier = object.responds(to: NSSelectorFromString("accessibilityIdentifier"))
            ? object.value(forKey: "accessibilityIdentifier") as? String
            : nil
        return AXNode(
            identifier: identifier ?? "",
            label: object.accessibilityLabel ?? "",
            frame: object.accessibilityFrame,
            isElement: object.isAccessibilityElement,
            traits: object.accessibilityTraits,
            children: children.map { tree(of: $0) }
        )
    }

    private static func describe(_ node: AXNode, depth: Int = 0) -> String {
        let line = "\(String(repeating: "  ", count: depth))id=\(node.identifier) label=\(node.label) frame=\(node.frame)"
        return ([line] + node.children.map { describe($0, depth: depth + 1) }).joined(separator: "\n")
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
        let tree = Self.tree(of: window)
        let failuresBefore = testRun?.totalFailureCount ?? 0
        defer {
            if (testRun?.totalFailureCount ?? 0) > failuresBefore { print(Self.describe(tree)) }
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
    /// close control and the copy inside it stay separate elements without that id.
    @MainActor
    private func assertBanner(
        _ token: String,
        in tree: AXNode,
        frame expected: CGRect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> AXNode {
        let matches = tree.nodes(BannerAccessibilityID.banner(token))
        XCTAssertEqual(matches.count, 1, "releva-banner-\(token) on exactly one element", file: file, line: line)
        let banner = try XCTUnwrap(matches.first, "no element carries releva-banner-\(token)", file: file, line: line)
        XCTAssertFalse(banner.isElement, "a container, so the views inside stay reachable", file: file, line: line)
        assertFrame(banner.frame, expected, "releva-banner-\(token) has the banner's frame", file: file, line: line)

        XCTAssertEqual(tree.nodes(BannerAccessibilityID.close).count, 1, "releva-banner-close on exactly one element", file: file, line: line)
        let close = try XCTUnwrap(banner.nodes(BannerAccessibilityID.close).first, "the close control is inside the banner", file: file, line: line)
        XCTAssertTrue(close.isElement, file: file, line: line)
        XCTAssertEqual(close.label, "Close", file: file, line: line)
        XCTAssertTrue(close.traits.contains(.button), "the close control keeps the button trait", file: file, line: line)

        let copy = banner.flattened.filter { $0.isElement && $0.label.contains(Self.copy) }
        XCTAssertFalse(copy.isEmpty, "the copy is its own element inside the banner", file: file, line: line)
        XCTAssertTrue(copy.allSatisfy { $0.identifier.isEmpty }, "the banner's id does not spread to its copy", file: file, line: line)
        return close
    }

    /// The close element's frame is the whole tap target: a `hitSide` square `closeControlInset`
    /// in from the banner's trailing edge, not the smaller visible button inside it.
    @MainActor
    private func assertCloseIsTheHitBox(
        _ close: AXNode,
        in banner: CGRect,
        top: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let style = BannerCloseButtonStyle(cssStyles: [:])
        XCTAssertLessThan(style.side, style.hitSide, "at the default size the visible button is smaller than its tap target", file: file, line: line)
        assertFrame(
            close.frame,
            CGRect(x: banner.maxX - BannerChrome.closeControlInset - style.hitSide, y: top, width: style.hitSide, height: style.hitSide),
            "releva-banner-close is the tap target",
            file: file,
            line: line
        )
    }

    private func assertFrame(_ frame: CGRect, _ expected: CGRect, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let matches = abs(frame.minX - expected.minX) <= 0.5 && abs(frame.minY - expected.minY) <= 0.5
            && abs(frame.width - expected.width) <= 0.5 && abs(frame.height - expected.height) <= 0.5
        XCTAssertTrue(matches, "\(message): got \(frame), want \(expected)", file: file, line: line)
    }

    // MARK: - Popup

    @MainActor
    func testPopupCardPlacementAndCloseCarryTheirIds() throws {
        try overlay { vm in
            vm.popupBanner = BannerResponse(token: "popup-1", displayType: "popup", design: design())
        } check: { tree, reported, safeArea in
            let card = try XCTUnwrap(reported.first, "the popup reported no card frame")
            let close = try assertBanner("popup-1", in: tree, frame: card)
            assertCloseIsTheHitBox(close, in: card, top: card.minY + BannerChrome.closeControlInset)

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
            assertCloseIsTheHitBox(close, in: card, top: card.minY + BannerChrome.closeControlInset)
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
            assertCloseIsTheHitBox(close, in: card, top: card.minY + BannerChrome.closeControlInset)
        }
    }

    // MARK: - Bars

    @MainActor
    func testTopBarStripAndCloseCarryTheirIds() throws {
        try overlay { vm in
            vm.barBanners = [BannerResponse(token: "bar-top", displayType: "bar", displayPosition: "top", design: design())]
        } check: { tree, reported, safeArea in
            let strip = try XCTUnwrap(reported.first, "the bar reported no frame")
            XCTAssertEqual(strip.minY, 0, accuracy: 0.5, "the full strip, status-bar padding included")
            XCTAssertEqual(strip.width, Self.windowSize.width, accuracy: 0.5)
            let close = try assertBanner("bar-top", in: tree, frame: strip)
            // The status-bar padding is at least the host's inset; the key window's can raise it.
            XCTAssertGreaterThanOrEqual(close.frame.minY, safeArea.minY + BannerChrome.closeControlInset - 0.5)
            assertCloseIsTheHitBox(close, in: strip, top: close.frame.minY)
            XCTAssertTrue(tree.nodes(BannerAccessibilityID.placement).isEmpty, "a bar has no placement box")
        }
    }

    @MainActor
    func testBottomBarStripAndCloseCarryTheirIds() throws {
        try overlay { vm in
            vm.barBanners = [BannerResponse(token: "bar-bottom", displayType: "bar", displayPosition: "bottom", design: design())]
        } check: { tree, reported, _ in
            let strip = try XCTUnwrap(reported.first, "the bar reported no frame")
            XCTAssertEqual(strip.maxY, Self.windowSize.height, accuracy: 0.5, "the full strip, home-indicator padding included")
            let close = try assertBanner("bar-bottom", in: tree, frame: strip)
            assertCloseIsTheHitBox(close, in: strip, top: strip.minY + BannerChrome.closeControlInset)
            XCTAssertTrue(tree.nodes(BannerAccessibilityID.placement).isEmpty, "a bar has no placement box")
        }
    }

    // MARK: - Flyouts

    @MainActor
    func testLeftFlyoutCarriesItsIdAndNoPlacement() throws {
        try overlay { vm in
            vm.flyoutBanner = BannerResponse(token: "fly-left", displayType: "flyout", displayPosition: "left", design: design())
        } check: { tree, reported, _ in
            let panel = try XCTUnwrap(reported.first, "the flyout reported no frame")
            XCTAssertEqual(panel.minX, 0, accuracy: 0.5)
            let close = try assertBanner("fly-left", in: tree, frame: panel)
            assertCloseIsTheHitBox(close, in: panel, top: panel.minY + BannerChrome.closeControlInset)
            XCTAssertTrue(tree.nodes(BannerAccessibilityID.placement).isEmpty, "an unsized flyout has no placement box")
        }
    }

    @MainActor
    func testRightFlyoutCarriesItsIdAndNoPlacement() throws {
        try overlay { vm in
            vm.flyoutBanner = BannerResponse(token: "fly-right", displayType: "flyout", displayPosition: "right", design: design())
        } check: { tree, reported, _ in
            let panel = try XCTUnwrap(reported.first, "the flyout reported no frame")
            XCTAssertEqual(panel.maxX, Self.windowSize.width, accuracy: 0.5)
            let close = try assertBanner("fly-right", in: tree, frame: panel)
            assertCloseIsTheHitBox(close, in: panel, top: panel.minY + BannerChrome.closeControlInset)
            XCTAssertTrue(tree.nodes(BannerAccessibilityID.placement).isEmpty, "an unsized flyout has no placement box")
        }
    }

    /// A sized flyout carries the box it is placed in: from the top of the safe area to the bottom
    /// of the screen, which the drawer reaches.
    @MainActor
    func testASizedFlyoutCarriesItsPlacementBox() throws {
        try overlay { vm in
            vm.flyoutBanner = BannerResponse(token: "fly-sized", displayType: "flyout", displayPosition: "right", cssStyles: ["cardWidth": "200px"], design: design())
        } check: { tree, reported, safeArea in
            let panel = try XCTUnwrap(reported.first, "the flyout reported no frame")
            XCTAssertEqual(panel.width, 200, accuracy: 0.5)
            _ = try assertBanner("fly-sized", in: tree, frame: panel)

            let placement = tree.nodes(BannerAccessibilityID.placement)
            XCTAssertEqual(placement.count, 1, "a sized flyout carries its placement box")
            let box = CGRect(x: safeArea.minX, y: safeArea.minY, width: safeArea.width, height: Self.windowSize.height - safeArea.minY)
            assertFrame(try XCTUnwrap(placement.first).frame, box, "releva-banner-placement is the box the drawer is placed in")
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

        let tree = Self.tree(of: window)
        XCTAssertFalse(measured.frame.isNull, "the static banner was not laid out")
        let matches = tree.nodes(BannerAccessibilityID.banner("static-1"))
        XCTAssertEqual(matches.count, 1, "releva-banner-static-1 on exactly one element\n\(Self.describe(tree))")
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
