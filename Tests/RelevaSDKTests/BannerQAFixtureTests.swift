import SwiftUI
import UIKit
import XCTest
@testable import RelevaSDK

/// The qa-shared CHR and CLS fixtures (`backend/fixtures.mjs`), drawn in the overlay window at the
/// QA simulator's size, and checked against the geometry device QA's sections Q and R hold
/// sdk-react-native to. Frames are read the way the device pass reads them: the card from the
/// frames the SDK reports for hit-testing, the ids and the copy from the accessibility tree.
///
/// With `RLV_SNAPSHOT_DIR` set each row also writes `<row>.png` and `<row>.json` (the frames it
/// read), so two builds can be compared.
final class BannerQAFixtureTests: XCTestCase {
    private static let windowSize = CGSize(width: 402, height: 874)
    private static let magenta = RGB(red: 255, green: 0, blue: 255)
    /// The app behind the overlay: one flat colour, so an unpainted card shows it.
    private static let backdrop = RGB(red: 0, green: 128, blue: 128)

    override func setUp() {
        super.setUp()
        Self.setAutomation(enabled: true)
    }

    override func tearDown() {
        Self.setAutomation(enabled: false)
        super.tearDown()
    }

    // MARK: - Fixtures

    /// fixtures.mjs `design`: one 18 px paragraph, padded 10, on `bg` (none when `nil`).
    private static func design(_ label: String, bg: String? = "#1d4ed8", fg: String = "#ffffff") -> [String: JSONValue] {
        let background: JSONValue = bg.map { .string($0) } ?? .null
        return [
            "body": [
                "rows": [[
                    "cells": [1],
                    "columns": [[
                        "contents": [[
                            "type": "text",
                            "values": [
                                "text": .string("<p style=\"color:\(fg);font-size:18px\">\(label)</p>"),
                                "color": .string(fg),
                                "containerPadding": "10px"
                            ]
                        ]]
                    ]],
                    "values": ["backgroundColor": background]
                ]],
                "values": ["backgroundColor": background, "contentWidth": "100%"]
            ]
        ]
    }

    /// fixtures.mjs `chromeDesign`: one h4 heading, padded 10, painting nothing.
    private static func chromeDesign(_ label: String, fg: String = "#ffffff") -> [String: JSONValue] {
        [
            "body": [
                "rows": [[
                    "cells": [1],
                    "columns": [[
                        "contents": [[
                            "type": "heading",
                            "values": ["text": .string(label), "headingType": "h4", "color": .string(fg), "containerPadding": "10px"]
                        ]]
                    ]],
                    "values": [:]
                ]],
                "values": ["contentWidth": "100%"]
            ]
        ]
    }

    /// The block's keys over everything else at the defaults the server fills in.
    private static func cssStyles(_ keys: [String: JSONValue]) -> [String: JSONValue] {
        let closeDefaults: [String: JSONValue] = [
            "closeButtonColor": "#000", "closeButtonBackgroundColor": "#fff",
            "closeFontSize": "14", "closeButtonBorderRadius": "20", "closeButtonBorder": ""
        ]
        return documentedBannerCardStyleDefaults.merging(closeDefaults) { $1 }.merging(keys) { $1 }
    }

    private static func banner(
        _ token: String,
        _ displayType: String,
        position: String? = nil,
        keys: [String: JSONValue] = [:],
        design: [String: JSONValue]
    ) -> BannerResponse {
        BannerResponse(token: token, displayType: displayType, displayPosition: position, cssStyles: cssStyles(keys), design: design)
    }

    // MARK: - Harness

    private struct RGB: Equatable, CustomStringConvertible {
        let red: Int, green: Int, blue: Int
        var description: String { "rgb(\(red), \(green), \(blue))" }
        func isClose(to other: RGB, tolerance: Int = 8) -> Bool {
            abs(red - other.red) <= tolerance && abs(green - other.green) <= tolerance && abs(blue - other.blue) <= tolerance
        }
    }

    /// What one row measured, in window points.
    private struct Measured {
        /// The frames the SDK reports for hit-testing; the card is the largest.
        let reported: [CGRect]
        /// `releva-banner-<token>`, `releva-banner-close` and `releva-banner-placement`.
        let banner: CGRect?
        let close: CGRect?
        let placement: CGRect?
        /// The smallest accessibility element whose label holds the copy.
        let copy: CGRect?
        let safeArea: UIEdgeInsets
        let image: UIImage

        var card: CGRect? { reported.max { $0.width * $0.height < $1.width * $1.height } }

        func color(at point: CGPoint) -> RGB {
            var pixel = [UInt8](repeating: 0, count: 4)
            let space = CGColorSpaceCreateDeviceRGB()
            let info = CGImageAlphaInfo.premultipliedLast.rawValue
            if let cgImage = image.cgImage,
               let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space, bitmapInfo: info) {
                let scale = CGFloat(cgImage.width) / image.size.width
                context.draw(
                    cgImage,
                    in: CGRect(
                        x: -point.x * scale,
                        y: point.y * scale - CGFloat(cgImage.height) + 1,
                        width: CGFloat(cgImage.width),
                        height: CGFloat(cgImage.height)
                    )
                )
            }
            return RGB(red: Int(pixel[0]), green: Int(pixel[1]), blue: Int(pixel[2]))
        }
    }

    private struct AXNode {
        let identifier: String
        let label: String
        let frame: CGRect
        let isElement: Bool
        let children: [AXNode]
        var flattened: [AXNode] { [self] + children.flatMap(\.flattened) }
    }

    private static func setAutomation(enabled: Bool) {
        guard let handle = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
              let symbol = dlsym(handle, "_AXSSetAutomationEnabled") else { return }
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
            children: children.map { tree(of: $0) }
        )
    }

    /// Draws `banners` over a flat backdrop in a 402 × 874 window and hands `check` what it read.
    @MainActor
    private func draw(
        _ name: String,
        _ banners: [BannerResponse],
        copy: String? = nil,
        check: (Measured) throws -> Void
    ) throws {
        let viewModel = BannerDisplayViewModel()
        for banner in banners {
            switch banner.displayType {
            case "popup": viewModel.popupBanner = banner
            case "flyout": viewModel.flyoutBanner = banner
            default: viewModel.barBanners.append(banner)
            }
        }
        let host = BannerOverlayHost.shared
        host.attach(viewModel) { _ in }

        let controller = BannerOverlayHostingController(rootView: BannerOverlayRoot(host: host))
        controller.host = host
        controller.view.backgroundColor = .clear
        let backdrop = UIViewController()
        backdrop.view.backgroundColor = UIColor(red: 0, green: 128 / 255, blue: 128 / 255, alpha: 1)
        let window = UIWindow(frame: CGRect(origin: .zero, size: Self.windowSize))
        window.rootViewController = backdrop
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        window.addSubview(controller.view)
        backdrop.addChild(controller)
        window.layoutIfNeeded()
        drainMainQueue(turns: 6)
        window.layoutIfNeeded()
        defer {
            host.detach(viewModel)
            window.isHidden = true
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { context in
            window.layer.render(in: context.cgContext)
        }
        let nodes = Self.tree(of: window).flattened
        func frame(_ identifier: String) -> CGRect? {
            nodes.filter { $0.identifier == identifier }.map(\.frame).max { $0.width * $0.height < $1.width * $1.height }
        }
        let copyFrame = copy.flatMap { text in
            nodes.filter { $0.isElement && $0.label.contains(text) }.map(\.frame).min { $0.width * $0.height < $1.width * $1.height }
        }
        let measured = Measured(
            reported: host.interactiveFrames,
            banner: banners.first.flatMap { frame("releva-banner-\($0.token)") },
            close: frame("releva-banner-close"),
            placement: frame("releva-banner-placement"),
            copy: copyFrame,
            safeArea: host.safeAreaInsets,
            image: image
        )

        if let dir = ProcessInfo.processInfo.environment["RLV_SNAPSHOT_DIR"] {
            let base = URL(fileURLWithPath: dir)
            try image.pngData()?.write(to: base.appendingPathComponent("qa_\(name).png"))
            func list(_ rect: CGRect?) -> [Double] {
                guard let rect = rect else { return [] }
                return [rect.minX, rect.minY, rect.maxX, rect.maxY].map { (Double($0) * 10).rounded() / 10 }
            }
            let record: [String: Any] = [
                "reported": measured.reported.map { list($0) },
                "banner": list(measured.banner),
                "close": list(measured.close),
                "placement": list(measured.placement),
                "copy": list(measured.copy)
            ]
            let json = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys, .prettyPrinted])
            try json.write(to: base.appendingPathComponent("qa_\(name).json"))
        }
        try check(measured)
    }

    private func assertFrame(_ frame: CGRect?, _ expected: CGRect, _ what: String, accuracy: CGFloat = 0.6, file: StaticString = #filePath, line: UInt = #line) {
        guard let frame = frame else { return XCTFail("\(what): not found", file: file, line: line) }
        let matches = abs(frame.minX - expected.minX) <= accuracy && abs(frame.minY - expected.minY) <= accuracy
            && abs(frame.maxX - expected.maxX) <= accuracy && abs(frame.maxY - expected.maxY) <= accuracy
        XCTAssertTrue(matches, "\(what): got \(frame), want \(expected)", file: file, line: line)
    }

    // MARK: - Bars (section Q: CHR-01..06, CHR-15)

    /// CHR-01: all nine keys at their defaults draw QA-BAN-03's bar, and the card stays unpainted.
    @MainActor
    func testCHR01DefaultsDrawTheBarNoKeysDraw() throws {
        var baseline: Measured?
        try draw("BAN-03", [Self.banner("ban03", "bar", position: "top", design: Self.design("CHR-01 bar top at defaults", bg: nil, fg: "#111111"))]) { baseline = $0 }
        let keys = documentedBannerCardStyleDefaults.merging(["cardBackgroundColor": "#FEFEFE"]) { $1 }
        try draw("CHR-01", [Self.banner("chr01", "bar", position: "top", keys: keys, design: Self.design("CHR-01 bar top at defaults", bg: nil, fg: "#111111"))]) { row in
            let base = try XCTUnwrap(baseline)
            XCTAssertEqual(row.reported, base.reported, "the same card and control")
            assertFrame(row.banner, try XCTUnwrap(base.banner), "the same layer")
            let card = try XCTUnwrap(row.card)
            XCTAssertEqual(card.minY, 0, accuracy: 0.5)
            XCTAssertEqual(card.width, Self.windowSize.width, accuracy: 0.5)
            let sample = row.color(at: CGPoint(x: card.minX + 4, y: card.minY + 4))
            XCTAssertTrue(sample.isClose(to: Self.backdrop), "unpainted: drew \(sample)")
        }
    }

    /// CHR-02: a 240 pt magenta card centred in a layer that spans the width, its bottom corners
    /// rounded 16.
    @MainActor
    func testCHR02BarCentred240Radius16() throws {
        let keys: [String: JSONValue] = ["cardPositionHorizontal": "center", "cardWidth": "240px", "cardBorderRadius": "16", "cardBackgroundColor": "#ff00ff"]
        try draw("CHR-02", [Self.banner("chr02", "bar", position: "top", keys: keys, design: Self.chromeDesign("CHR-02 centred 240"))]) { row in
            let card = try XCTUnwrap(row.card)
            assertFrame(card, CGRect(x: (Self.windowSize.width - 240) / 2, y: 0, width: 240, height: card.height), "card")
            assertFrame(row.banner, CGRect(x: 0, y: 0, width: Self.windowSize.width, height: card.height), "layer")
            XCTAssertTrue(row.color(at: CGPoint(x: card.midX, y: card.maxY - 2)).isClose(to: Self.magenta), "painted")
            XCTAssertTrue(row.color(at: CGPoint(x: card.minX + 1, y: card.maxY - 1)).isClose(to: Self.backdrop), "bottom-left corner rounded")
            XCTAssertTrue(row.color(at: CGPoint(x: card.maxX - 1, y: card.maxY - 1)).isClose(to: Self.backdrop), "bottom-right corner rounded")
        }
    }

    /// CHR-03: a 200 pt card in the vertical middle of a layer spanning the window, which passes
    /// touches through beside the card.
    @MainActor
    func testCHR03BarCentredVerticallyPassesTouchesBesideIt() throws {
        let keys: [String: JSONValue] = ["cardPositionVertical": "center", "cardWidth": "200px", "cardBackgroundColor": "#ff00ff"]
        try draw("CHR-03", [Self.banner("chr03", "bar", position: "top", keys: keys, design: Self.chromeDesign("CHR-03 tap through"))]) { row in
            let card = try XCTUnwrap(row.card)
            XCTAssertEqual(card.minX, 0, accuracy: 0.5)
            XCTAssertEqual(card.width, 200, accuracy: 0.5)
            XCTAssertEqual(card.midY, Self.windowSize.height / 2, accuracy: 1)
            XCTAssertGreaterThan(card.minY, row.safeArea.top, "no status-bar padding away from the edge")
            assertFrame(row.banner, CGRect(origin: .zero, size: Self.windowSize), "layer")
            let beside = CGPoint(x: 300, y: card.midY)
            XCTAssertFalse(row.reported.contains { $0.contains(beside) }, "a touch beside the card reaches the app")
        }
    }

    /// CHR-04: `cardPositionVertical: bottom` beats `displayPosition: top`.
    @MainActor
    func testCHR04BottomKeyBeatsTopPosition() throws {
        let keys: [String: JSONValue] = ["cardPositionVertical": "bottom", "cardBackgroundColor": "#ff00ff"]
        try draw("CHR-04", [Self.banner("chr04", "bar", position: "top", keys: keys, design: Self.chromeDesign("CHR-04 key beats top"))]) { row in
            let card = try XCTUnwrap(row.card)
            XCTAssertEqual(card.maxY, Self.windowSize.height, accuracy: 0.5)
            assertFrame(row.banner, card, "layer")
            XCTAssertGreaterThan(card.minY, Self.windowSize.height * 2 / 3)
        }
    }

    /// CHR-05: the card is translated 40 pt down and 5% of the window right; the layer stays a
    /// default top bar, and the control is pulled back on screen with the gutter.
    @MainActor
    func testCHR05OffsetsTranslateTheCardNotTheLayer() throws {
        let keys: [String: JSONValue] = ["cardOffsetVertical": "40px", "cardOffsetHorizontal": "5%", "cardBackgroundColor": "#ff00ff"]
        try draw("CHR-05", [Self.banner("chr05", "bar", position: "top", keys: keys, design: Self.chromeDesign("CHR-05 offset 40px 5%"))]) { row in
            let card = try XCTUnwrap(row.card)
            let shift = Self.windowSize.width * 0.05
            assertFrame(card, CGRect(x: shift, y: 40, width: Self.windowSize.width, height: card.height), "card")
            assertFrame(row.banner, CGRect(x: 0, y: 0, width: Self.windowSize.width, height: card.height), "layer")
            let close = try XCTUnwrap(row.close)
            XCTAssertLessThanOrEqual(close.maxX, Self.windowSize.width + 2.5, "the control stays on screen")
        }
    }

    /// CHR-06: a 120 pt card with its copy centred in the part below the status bar.
    @MainActor
    func testCHR06FixedHeightCentresTheCopy() throws {
        let keys: [String: JSONValue] = ["cardHeight": "120px", "contentVerticalAlign": "center", "cardBackgroundColor": "#ff00ff"]
        try draw("CHR-06", [Self.banner("chr06", "bar", position: "top", keys: keys, design: Self.chromeDesign("CHR-06 copy centred"))], copy: "CHR-06 copy centred") { row in
            let card = try XCTUnwrap(row.card)
            XCTAssertEqual(card.minY, 0, accuracy: 0.5)
            XCTAssertEqual(card.height, 120, accuracy: 0.5)
            let copy = try XCTUnwrap(row.copy)
            XCTAssertEqual(copy.midY, (row.safeArea.top + 120) / 2, accuracy: 1)
        }
    }

    /// CHR-15: a 45% card centred, then translated 60 pt right.
    @MainActor
    func testCHR15CentredAndOffsetOnTheSameAxis() throws {
        let keys: [String: JSONValue] = ["cardPositionHorizontal": "center", "cardOffsetHorizontal": "60px", "cardWidth": "45%", "cardBackgroundColor": "#ff00ff"]
        try draw("CHR-15", [Self.banner("chr15", "bar", position: "top", keys: keys, design: Self.chromeDesign("CHR-15 off-centre"))]) { row in
            let card = try XCTUnwrap(row.card)
            XCTAssertEqual(card.width, Self.windowSize.width * 0.45, accuracy: 0.5)
            XCTAssertEqual(card.midX, Self.windowSize.width / 2 + 60, accuracy: 0.5)
            XCTAssertEqual(card.minY, 0, accuracy: 0.5)
        }
    }

    // MARK: - Popups (section Q: CHR-07..10, CHR-16, CHR-17)

    /// The safe-area box a popup is placed in.
    private func box(_ row: Measured) -> CGRect {
        CGRect(
            x: 0,
            y: row.safeArea.top,
            width: Self.windowSize.width,
            height: Self.windowSize.height - row.safeArea.top - row.safeArea.bottom
        )
    }

    @MainActor
    func testCHR07And08PopupSizedAndPlaced() throws {
        let chr07: [String: JSONValue] = ["cardWidth": "300px", "cardHeight": "400px", "cardBorderRadius": "24", "cardBackgroundColor": "#ff00ff"]
        try draw("CHR-07", [Self.banner("chr07", "popup", keys: chr07, design: Self.chromeDesign("CHR-07 popup 300x400"))]) { row in
            let box = box(row)
            assertFrame(row.card, CGRect(x: box.midX - 150, y: box.midY - 200, width: 300, height: 400), "card")
            assertFrame(row.placement, box, "placement")
        }
        let chr08: [String: JSONValue] = [
            "cardWidth": "280px", "cardHeight": "300px", "cardPositionVertical": "bottom", "cardPositionHorizontal": "left",
            "cardOffsetHorizontal": "16px", "cardOffsetVertical": "24px", "cardBackgroundColor": "#ff00ff"
        ]
        try draw("CHR-08", [Self.banner("chr08", "popup", keys: chr08, design: Self.chromeDesign("CHR-08 bottom-left offset"))]) { row in
            let box = box(row)
            assertFrame(row.card, CGRect(x: 16, y: box.maxY - 324, width: 280, height: 300), "card")
        }
    }

    /// CHR-09: the content-sized card at the top-right of the box, its id's frame the drawn card.
    @MainActor
    func testCHR09PopupPositionedWithoutASize() throws {
        let keys: [String: JSONValue] = ["cardPositionVertical": "top", "cardPositionHorizontal": "right", "cardBackgroundColor": "#ff00ff"]
        try draw("CHR-09", [Self.banner("chr09", "popup", keys: keys, design: Self.chromeDesign("CHR-09 popup inert keys"))]) { row in
            let card = try XCTUnwrap(row.card)
            let box = box(row)
            XCTAssertEqual(card.minY, box.minY, accuracy: 0.5)
            XCTAssertEqual(card.maxX, box.maxX, accuracy: 0.5)
            XCTAssertEqual(card.width, min(600, box.width - 32), accuracy: 0.5)
            XCTAssertLessThan(card.height, box.height / 2)
            assertFrame(row.banner, card, "the id's frame is the drawn card")
        }
    }

    @MainActor
    func testCHR10And16And17PopupAlignmentAndRightEdge() throws {
        try draw("CHR-10", [Self.banner("chr10", "popup", keys: ["contentVerticalAlign": "bottom"], design: Self.chromeDesign("CHR-10 copy at the bottom", fg: "#111111"))]) { row in
            let card = try XCTUnwrap(row.card)
            let box = box(row)
            XCTAssertEqual(card.width, min(600, box.width - 32), accuracy: 0.5)
            XCTAssertEqual(card.midX, box.midX, accuracy: 0.5)
            XCTAssertEqual(card.midY, box.midY, accuracy: 0.5)
        }
        let chr16: [String: JSONValue] = ["cardWidth": "280px", "cardHeight": "360px", "contentVerticalAlign": "bottom", "cardBackgroundColor": "#ff00ff"]
        try draw("CHR-16", [Self.banner("chr16", "popup", keys: chr16, design: Self.chromeDesign("CHR-16 bottom in a sized card"))], copy: "CHR-16 bottom in a sized card") { row in
            let card = try XCTUnwrap(row.card)
            XCTAssertEqual(card.height, 360, accuracy: 0.5)
            let copy = try XCTUnwrap(row.copy)
            XCTAssertEqual(copy.maxY, card.maxY - 10, accuracy: 1, "against the bottom, inside its 10 pt padding")
        }
        let chr17: [String: JSONValue] = ["cardWidth": "260px", "cardHeight": "220px", "cardPositionHorizontal": "right", "cardBackgroundColor": "#ff00ff"]
        try draw("CHR-17", [Self.banner("chr17", "popup", keys: chr17, design: Self.chromeDesign("CHR-17 right edge"))]) { row in
            let box = box(row)
            assertFrame(row.card, CGRect(x: box.maxX - 260, y: box.midY - 110, width: 260, height: 220), "card")
        }
    }

    // MARK: - Flyouts (section Q: CHR-11..14)

    /// CHR-11: 80% wide, half the safe-area box tall, centred in it both ways, corners clipped to 24.
    @MainActor
    func testCHR11FlyoutCentredHalfHeightRounded() throws {
        let keys: [String: JSONValue] = [
            "cardPositionHorizontal": "center", "cardPositionVertical": "center", "cardHeight": "50%",
            "cardBorderRadius": "24", "cardBackgroundColor": "#ff00ff"
        ]
        try draw("CHR-11", [Self.banner("chr11", "flyout", position: "right", keys: keys, design: Self.chromeDesign("CHR-11 flyout centred"))]) { row in
            let box = box(row)
            let width = Self.windowSize.width * 0.8
            let card = try XCTUnwrap(row.card)
            assertFrame(card, CGRect(x: box.midX - width / 2, y: box.midY - box.height / 4, width: width, height: box.height / 2), "card")
            assertFrame(row.placement, box, "placement")
            assertFrame(row.banner, card, "id")
            XCTAssertTrue(row.color(at: CGPoint(x: card.midX, y: card.maxY - 2)).isClose(to: Self.magenta))
            XCTAssertFalse(row.color(at: CGPoint(x: card.minX + 1, y: card.maxY - 1)).isClose(to: Self.magenta, tolerance: 60), "corner clipped")
        }
    }

    /// CHR-12 and CHR-13: no size, so full-bleed top to bottom, 80% wide, on the side the key
    /// (CHR-12) or `displayPosition` (CHR-13) names; no placement box.
    @MainActor
    func testCHR12And13UnsizedFlyoutIsFullBleed() throws {
        try draw("CHR-12", [Self.banner("chr12", "flyout", position: "right", keys: ["cardPositionHorizontal": "left"], design: Self.chromeDesign("CHR-12 flyout key left", fg: "#111111"))]) { row in
            assertFrame(row.card, CGRect(x: 0, y: 0, width: Self.windowSize.width * 0.8, height: Self.windowSize.height), "card")
            XCTAssertNil(row.placement)
        }
        try draw("CHR-13", [Self.banner("chr13", "flyout", position: "right", keys: ["cardPositionVertical": "bottom", "cardBackgroundColor": "#ff00ff"], design: Self.chromeDesign("CHR-13 flyout inert vertical"))], copy: "CHR-13 flyout inert vertical") { row in
            let card = try XCTUnwrap(row.card)
            assertFrame(card, CGRect(x: Self.windowSize.width * 0.2, y: 0, width: Self.windowSize.width * 0.8, height: Self.windowSize.height), "card")
            XCTAssertTrue(row.color(at: CGPoint(x: card.midX, y: card.midY)).isClose(to: Self.magenta))
            let copy = try XCTUnwrap(row.copy)
            XCTAssertGreaterThanOrEqual(copy.minY, row.safeArea.top + 48, "the content is inset below the status bar and the close band")
        }
    }

    /// CHR-14: 300 pt tall, hanging off the bottom of the safe-area box, on the left.
    @MainActor
    func testCHR14SizedFlyoutHangsOffTheBottom() throws {
        try draw("CHR-14", [Self.banner("chr14", "flyout", position: "left", keys: ["cardHeight": "300px", "cardPositionVertical": "bottom"], design: Self.chromeDesign("CHR-14 flyout 300 bottom", fg: "#111111"))]) { row in
            let box = box(row)
            assertFrame(row.card, CGRect(x: 0, y: box.maxY - 300, width: Self.windowSize.width * 0.8, height: 300), "card")
            assertFrame(row.placement, box, "placement")
        }
    }

    // MARK: - Close control (section R: CLS-01..10)

    /// CLS-01..08: on a popup the visible button sits 8 in from the card's top-right corner, so the
    /// 44 pt tap target is `8 - ring` in; the design starts below the band.
    @MainActor
    func testCLS01To08PopupCloseControl() throws {
        struct Row {
            let name: String
            let keys: [String: JSONValue]
            let design: [String: JSONValue]
            init(_ name: String, _ keys: [String: JSONValue], _ design: [String: JSONValue]) {
                self.name = name
                self.keys = keys
                self.design = design
            }
        }
        let webOnlyKeys: [String: JSONValue] = [
            "closeButtonSymbol": "CLOSE", "closeButtonPadding": "20px 40px", "closeButtonFontWeight": "900",
            "closeButtonLineHeight": "40", "closeButtonTopPosition": "-40", "closeButtonRightPosition": "-40"
        ]
        var designWithCloseColours = Self.design("CLS-08 design override")
        var body = designWithCloseColours["body"]?.objectValue ?? [:]
        var values = body["values"]?.objectValue ?? [:]
        values["popupCloseButton_iconColor"] = "#ff00ff"
        values["popupCloseButton_backgroundColor"] = "#00ff00"
        body["values"] = .object(values)
        designWithCloseColours["body"] = .object(body)
        let rows: [Row] = [
            Row("CLS-01", [:], Self.design("CLS-01 defaults")),
            Row("CLS-02", ["closeButtonColor": "#f00", "closeButtonBackgroundColor": "#ff0"], Self.design("CLS-02 three-digit hex")),
            Row("CLS-03", ["closeButtonColor": "#ffff00ff", "closeButtonBackgroundColor": "#ff000080"], Self.design("CLS-03 alpha last")),
            Row("CLS-04", ["closeButtonBorder": "2px solid #e00000"], Self.design("CLS-04 border", bg: "#ffffff", fg: "#111111")),
            Row("CLS-05", ["closeFontSize": "24"], Self.design("CLS-05 font size 24")),
            Row("CLS-06", ["closeButtonBorderRadius": "0", "closeButtonColor": "rgba(255, 255, 255, 1)", "closeButtonBackgroundColor": "rgb(0, 160, 0)"], Self.design("CLS-06 square rgb")),
            Row("CLS-07", webOnlyKeys, Self.design("CLS-07 web-only keys")),
            Row("CLS-08", [:], designWithCloseColours)
        ]
        for spec in rows {
            let name = spec.name, keys = spec.keys
            // Every copy starts with its row id.
            try draw(name, [Self.banner(name.lowercased(), "popup", keys: keys, design: spec.design)], copy: name + " ") { row in
                let card = try XCTUnwrap(row.card, name)
                let style = BannerCloseButtonStyle(cssStyles: Self.cssStyles(keys))
                let ring = (style.hitSide - style.side) / 2
                assertFrame(row.close, CGRect(x: card.maxX - (8 - ring) - style.hitSide, y: card.minY + 8 - ring, width: style.hitSide, height: style.hitSide), "\(name) close")
                let copy = try XCTUnwrap(row.copy, "\(name) copy")
                XCTAssertGreaterThanOrEqual(copy.minY, card.minY + 8 + style.side + 8 - 0.5, "\(name): the copy starts below the band")
            }
        }
    }

    /// CLS-09: on a top bar the visible button sits 4 in from the content's top-right corner, below
    /// the status bar, so the tap target reaches 2 past the card's right edge.
    @MainActor
    func testCLS09BarCloseControl() throws {
        try draw("CLS-09", [Self.banner("cls09", "bar", position: "top", keys: ["closeButtonColor": "#fff", "closeButtonBackgroundColor": "#000"], design: Self.design("CLS-09 bar"))]) { row in
            let card = try XCTUnwrap(row.card)
            assertFrame(row.close, CGRect(x: card.maxX + 2 - 44, y: row.safeArea.top - 2, width: 44, height: 44), "close")
        }
    }

    /// CLS-10: on a right-hand flyout the control sits on the inner, left edge, below the status bar.
    @MainActor
    func testCLS10FlyoutCloseControlOnTheInnerEdge() throws {
        let keys: [String: JSONValue] = ["closeButtonColor": "#0a0", "closeButtonBackgroundColor": "#fff", "closeButtonBorder": "3px solid #0a0"]
        try draw("CLS-10", [Self.banner("cls10", "flyout", position: "right", keys: keys, design: Self.design("CLS-10 flyout"))]) { row in
            let card = try XCTUnwrap(row.card)
            assertFrame(row.close, CGRect(x: card.minX + 2, y: row.safeArea.top + 2, width: 44, height: 44), "close")
        }
    }
}
