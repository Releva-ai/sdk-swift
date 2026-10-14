import SwiftUI
import UIKit
import XCTest
@testable import RelevaSDK

/// The overlay window's popup and flyout come and go as sdk-react-native's Modal does: a flyout and
/// its dim slide up from the bottom of the window and back down (`animationType="slide"`), a popup
/// and its dim fade in and out (`animationType="fade"`). The way in is chosen when the overlay
/// opens and is the way out, so a popup and a flyout replacing each other swap in place, as the
/// content of one Modal does.
///
/// The overlay is drawn over a white window, so a sample reads 255 where nothing is dimmed, 128
/// under the 50% dim, and 0 on a card, whose design is black. Each test films every frame and
/// judges the order of what it saw, so a stall before the first frame changes nothing.
final class BannerFlyoutSlideTests: XCTestCase {
    private static let windowSize = CGSize(width: 393, height: 852)
    /// A column with only the dim on it: left of a right flyout and of a popup's card.
    private static let dimColumn = 10
    private static let top = 20
    private static let bottom = 840

    @MainActor
    func testTheFlyoutSlidesUpFromTheBottomWhenItOpens() {
        let (window, viewModel) = overlayWindow()
        defer { takeDown(window, viewModel) }

        viewModel.flyoutBanner = flyout("fly-in")
        let frames = film(window, for: 1) { $0.dimEdge == 0 }

        let edges = frames.map(\.dimEdge)
        XCTAssertTrue(edges.contains { $0 > 100 && $0 < 750 }, "the dim was seen on its way up, edges \(edges)")
        XCTAssertTrue(isMonotonic(edges, rising: false), "the dim only moves up, edges \(edges)")
        XCTAssertTrue(frames.allSatisfy(\.dimIsWholeOrNone), "the dim slides in, it does not fade")
        XCTAssertEqual(edges.last, 0, "the dim covers the screen once the slide has run")
    }

    @MainActor
    func testTheFlyoutSlidesDownWhenItCloses() {
        let (window, viewModel) = overlayWindow()
        defer { takeDown(window, viewModel) }
        let banner = flyout("fly-out")
        viewModel.flyoutBanner = banner
        pump(for: 1)

        viewModel.dismissFlyout(banner)
        drainMainQueue()
        XCTAssertNotNil(BannerOverlayHost.shared.overlayLeavesAt, "the window stays up while the flyout slides out")
        let frames = film(window, for: 1) { $0.dimEdge == Int(Self.windowSize.height) }

        assertSlidesOut(frames)
        XCTAssertNil(BannerOverlayHost.shared.overlayLeavesAt, "the window can go once the slide has run")
    }

    /// As UIKit's `.crossDissolve`: the whole dim fades in, then out, with the spring the flyout
    /// slides with.
    @MainActor
    func testAPopupFadesInAndOut() {
        let (window, viewModel) = overlayWindow()
        defer { takeDown(window, viewModel) }
        let banner = popup("popup")

        viewModel.popupBanner = banner
        let fadeIn = film(window, for: 1)
        let shades = fadeIn.map { $0.value(at: Self.top) }
        XCTAssertTrue(fadeIn.allSatisfy(\.dimIsEven), "the dim fades in evenly, it does not slide")
        XCTAssertTrue(shades.contains { $0 > 140 && $0 < 240 }, "the dim was seen part way in, shades \(shades)")
        XCTAssertTrue(isMonotonic(shades, rising: false), "the dim only darkens, shades \(shades)")
        if let start = fadeIn.first(where: { $0.value(at: Self.top) < 252 })?.time,
           let late = fadeIn.first(where: { $0.time >= start + 0.75 }) {
            XCTAssertEqual(late.value(at: Self.top), 128, accuracy: 3, "the fade has run within UIKit's half second")
        } else {
            XCTFail("the fade did not start, shades \(shades)")
        }
        XCTAssertEqual(shades.last ?? 0, 128, accuracy: 2, "the popup's dim is in place once the fade has run")

        viewModel.dismissPopup(banner)
        drainMainQueue()
        XCTAssertNotNil(BannerOverlayHost.shared.overlayLeavesAt, "the window stays up while the popup fades out")
        assertFadesOut(film(window, for: 1))
        XCTAssertNil(BannerOverlayHost.shared.overlayLeavesAt, "the window can go once the fade has run")
    }

    @MainActor
    func testAFlyoutReplacingAPopupIsInPlaceAtOnce() {
        let (window, viewModel) = overlayWindow()
        defer { takeDown(window, viewModel) }
        viewModel.popupBanner = popup("popup")
        pump(for: 1)

        viewModel.flyoutBanner = flyout("fly")
        viewModel.popupBanner = nil
        let frames = film(window, for: 0.3, at: [CGPoint(x: 380, y: 20)])
        XCTAssertTrue(frames.allSatisfy { abs($0.points[0]) <= 2 }, "the flyout is at the top in every frame")
    }

    @MainActor
    func testAPopupReplacingAFlyoutTakesItsPlaceAtOnce() {
        let (window, viewModel) = overlayWindow()
        defer { takeDown(window, viewModel) }
        viewModel.flyoutBanner = flyout("fly")
        pump(for: 1)

        viewModel.popupBanner = popup("popup")
        viewModel.flyoutBanner = nil
        drainMainQueue()
        XCTAssertNil(BannerOverlayHost.shared.overlayLeavesAt, "nothing leaves")
        let frames = film(window, for: 0.3, at: [CGPoint(x: 388, y: 840)])
        XCTAssertTrue(frames.allSatisfy { abs($0.points[0] - 128) <= 2 }, "the flyout is gone and the popup's dim is there in every frame")
    }

    /// A popup opened the overlay, so the flyout that replaced it fades out.
    @MainActor
    func testAFlyoutLeavesAsThePopupBeforeItCameIn() {
        let (window, viewModel) = overlayWindow()
        defer { takeDown(window, viewModel) }
        viewModel.popupBanner = popup("popup")
        pump(for: 1)
        let banner = flyout("fly")
        viewModel.flyoutBanner = banner
        viewModel.popupBanner = nil
        pump(for: 0.3)

        viewModel.dismissFlyout(banner)
        drainMainQueue()
        assertFadesOut(film(window, for: 1))
    }

    /// A flyout opened the overlay, so the popup that replaced it slides down with its dim, off the
    /// bottom of the window.
    @MainActor
    func testAPopupLeavesAsTheFlyoutBeforeItCameIn() {
        let (window, viewModel) = overlayWindow()
        defer { takeDown(window, viewModel) }
        viewModel.flyoutBanner = flyout("fly")
        pump(for: 1)
        let banner = popup("popup")
        viewModel.popupBanner = banner
        viewModel.flyoutBanner = nil
        pump(for: 0.3)

        viewModel.dismissPopup(banner)
        drainMainQueue()
        assertSlidesOut(film(window, for: 1) { $0.dimEdge == Int(Self.windowSize.height) })
    }

    // MARK: - Assertions

    @MainActor
    private func assertSlidesOut(_ frames: [Frame], file: StaticString = #filePath, line: UInt = #line) {
        let edges = frames.map(\.dimEdge)
        XCTAssertTrue(edges.contains { $0 > 100 && $0 < 750 }, "the dim was seen on its way down, edges \(edges)", file: file, line: line)
        XCTAssertTrue(isMonotonic(edges, rising: true), "the dim only moves down, edges \(edges)", file: file, line: line)
        XCTAssertTrue(frames.allSatisfy(\.dimIsWholeOrNone), "the dim slides out, it does not fade", file: file, line: line)
        // Edges only rise, so one equal to the edge seven frames on is a dim that stopped there.
        let onScreen = edges.filter { $0 > 0 && $0 < Int(Self.windowSize.height) }
        XCTAssertFalse(
            zip(onScreen, onScreen.dropFirst(7)).contains { $0 == $1 },
            "the dim slides off the window rather than stopping short of its bottom edge, edges \(onScreen)",
            file: file,
            line: line
        )
        XCTAssertEqual(edges.last, Int(Self.windowSize.height), "the dim is gone once the slide has run", file: file, line: line)
    }

    @MainActor
    private func assertFadesOut(_ frames: [Frame], file: StaticString = #filePath, line: UInt = #line) {
        let shades = frames.map { $0.value(at: Self.top) }
        XCTAssertTrue(frames.allSatisfy(\.dimIsEven), "the dim fades out evenly, it does not slide", file: file, line: line)
        XCTAssertTrue(shades.contains { $0 > 140 && $0 < 240 }, "the dim was seen part way out, shades \(shades)", file: file, line: line)
        XCTAssertTrue(isMonotonic(shades, rising: true), "the dim only lightens, shades \(shades)", file: file, line: line)
        XCTAssertGreaterThan(shades.last ?? 0, 250, "the dim is gone once the fade has run", file: file, line: line)
    }

    /// Whether `values` only ever move one way, give or take a rounding step.
    private func isMonotonic(_ values: [Int], rising: Bool) -> Bool {
        zip(values, values.dropFirst()).allSatisfy { rising ? $1 >= $0 - 1 : $1 <= $0 + 1 }
    }

    // MARK: - Harness

    /// One rendered frame: the red channel down `dimColumn`, one value per point from the top, and
    /// at any points asked for.
    private struct Frame {
        let time: TimeInterval
        let column: [Int]
        let points: [Int]

        func value(at y: Int) -> Int { column[y] }

        /// The first row from the top that is dimmed, or the window's height where none is.
        var dimEdge: Int { column.firstIndex { $0 < 250 } ?? column.count }

        /// Every row is either dimmed in full or not at all, as when a dim slides, but for the row
        /// its edge crosses.
        var dimIsWholeOrNone: Bool { column.filter { $0 < 250 && abs($0 - 128) > 3 }.count <= 2 }

        /// The top and the bottom of the column are equally dimmed, as when a dim fades.
        var dimIsEven: Bool { abs(value(at: BannerFlyoutSlideTests.top) - value(at: BannerFlyoutSlideTests.bottom)) <= 3 }
    }

    /// Renders `window` as it is on screen on every turn of the run loop for `seconds`, and on past
    /// that, up to five times as long, until `settled` holds of a frame: a loaded runner can take
    /// longer than a second to run a spring.
    @MainActor
    private func film(
        _ window: UIWindow,
        for seconds: TimeInterval,
        at points: [CGPoint] = [],
        until settled: ((Frame) -> Bool)? = nil
    ) -> [Frame] {
        let start = Date()
        var frames: [Frame] = []
        while true {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.005))
            let frame = render(window, at: points, time: Date().timeIntervalSince(start))
            frames.append(frame)
            let elapsed = Date().timeIntervalSince(start)
            if elapsed >= seconds * 5 { break }
            if elapsed >= seconds && (settled?(frame) ?? true) { break }
        }
        return frames
    }

    @MainActor
    private func render(_ window: UIWindow, at points: [CGPoint], time: TimeInterval) -> Frame {
        let width = Int(window.bounds.width)
        let height = Int(window.bounds.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            // SwiftUI fades through the presentation layers and leaves the model's opacity alone.
            (window.layer.presentation() ?? window.layer).render(in: context)
        }
        func red(_ x: Int, _ y: Int) -> Int { Int(pixels[(y * width + x) * 4]) }
        return Frame(
            time: time,
            column: (0..<height).map { red(Self.dimColumn, $0) },
            points: points.map { red(Int($0.x), Int($0.y)) }
        )
    }

    @MainActor
    private func overlayWindow() -> (UIWindow, BannerDisplayViewModel) {
        let viewModel = BannerDisplayViewModel()
        let host = BannerOverlayHost.shared
        host.attach(viewModel) { _ in }
        let controller = BannerOverlayHostingController(rootView: BannerOverlayRoot(host: host))
        controller.host = host
        controller.view.backgroundColor = .clear
        // iPhone-like insets: status bar and home indicator.
        controller.additionalSafeAreaInsets = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        let backdrop = UIViewController()
        backdrop.view.backgroundColor = .white
        let window = UIWindow(frame: CGRect(origin: .zero, size: Self.windowSize))
        window.rootViewController = backdrop
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        window.addSubview(controller.view)
        backdrop.addChild(controller)
        window.layoutIfNeeded()
        drainMainQueue(turns: 6)
        window.layoutIfNeeded()
        return (window, viewModel)
    }

    @MainActor
    private func takeDown(_ window: UIWindow, _ viewModel: BannerDisplayViewModel) {
        BannerOverlayHost.shared.detach(viewModel)
        window.isHidden = true
    }

    @MainActor
    private func pump(for seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.005)) }
    }

    private static let blackDesign: [String: JSONValue] = [
        "body": [
            "values": ["popupWidth": "200px"],
            "rows": [[
                "values": ["backgroundColor": "#000000", "padding": "0px"],
                "columns": [["values": [:], "contents": [["type": "text", "values": ["text": "x"]]]]]
            ]]
        ]
    ]

    private func flyout(_ token: String) -> BannerResponse {
        BannerResponse(token: token, displayType: "flyout", displayPosition: "right", design: Self.blackDesign)
    }

    private func popup(_ token: String) -> BannerResponse {
        BannerResponse(token: token, displayType: "popup", design: Self.blackDesign)
    }
}
