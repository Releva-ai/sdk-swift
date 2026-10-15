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
/// under the 50% dim, and 0 on a card, whose design is black.
///
/// SwiftUI runs these transitions on the hosting controller's own clock and sets each frame on the
/// layers itself. Core Animation does not run them, so a frozen layer clock does not hold them. The
/// tests hold the hosting controller's clock instead: the run loop does not turn while a test
/// films, so the display link draws nothing, and `_render(seconds:)` moves the clock on by one
/// frame and draws that frame. Each frame shows the same moment of the transition on any machine.
final class BannerFlyoutSlideTests: XCTestCase {
    private static let windowSize = CGSize(width: 393, height: 852)
    /// A column with only the dim on it: left of a right flyout and of a popup's card.
    private static let dimColumn = 10
    private static let top = 20
    private static let bottom = 840

    @MainActor
    func testTheFlyoutSlidesUpFromTheBottomWhenItOpens() {
        let stage = overlayStage()
        defer { takeDown(stage) }

        stage.viewModel.flyoutBanner = flyout("fly-in")
        assertSlidesIn(film(stage))
    }

    @MainActor
    func testTheFlyoutSlidesDownWhenItCloses() {
        let stage = overlayStage()
        defer { takeDown(stage) }
        let banner = flyout("fly-out")
        stage.viewModel.flyoutBanner = banner
        settle(stage)

        stage.viewModel.dismissFlyout(banner)
        assertSlidesOut(film(stage))
        drainMainQueue()
        XCTAssertNotNil(BannerOverlayHost.shared.overlayLeavesAt, "the window stays up while the flyout slides out")
        waitUntil("the window can go once the slide has run") { BannerOverlayHost.shared.overlayLeavesAt == nil }
    }

    /// As UIKit's `.crossDissolve`: the whole dim fades in, then out, with the spring the flyout
    /// slides with.
    @MainActor
    func testAPopupFadesInAndOut() {
        let stage = overlayStage()
        defer { takeDown(stage) }
        let banner = popup("popup")

        stage.viewModel.popupBanner = banner
        assertFades(film(stage), from: Self.clear, to: Self.dimmed)
        drainMainQueue()

        stage.viewModel.dismissPopup(banner)
        assertFades(film(stage), from: Self.dimmed, to: Self.clear)
        drainMainQueue()
        XCTAssertNotNil(BannerOverlayHost.shared.overlayLeavesAt, "the window stays up while the popup fades out")
        waitUntil("the window can go once the fade has run") { BannerOverlayHost.shared.overlayLeavesAt == nil }
    }

    @MainActor
    func testAFlyoutReplacingAPopupIsInPlaceAtOnce() {
        let stage = overlayStage()
        defer { takeDown(stage) }
        stage.viewModel.popupBanner = popup("popup")
        settle(stage)

        stage.viewModel.flyoutBanner = flyout("fly")
        stage.viewModel.popupBanner = nil
        let frames = film(stage, at: [CGPoint(x: 380, y: 20)])
        XCTAssertTrue(
            frames.allSatisfy { abs($0.points[0]) <= 2 },
            "the flyout is at the top in every frame, samples \(frames.map { $0.points[0] })"
        )
    }

    @MainActor
    func testAPopupReplacingAFlyoutTakesItsPlaceAtOnce() {
        let stage = overlayStage()
        defer { takeDown(stage) }
        stage.viewModel.flyoutBanner = flyout("fly")
        settle(stage)

        stage.viewModel.popupBanner = popup("popup")
        stage.viewModel.flyoutBanner = nil
        let frames = film(stage, at: [CGPoint(x: 388, y: 840)])
        XCTAssertTrue(
            frames.allSatisfy { abs($0.points[0] - 128) <= 2 },
            "the flyout is gone and the popup's dim is there in every frame, samples \(frames.map { $0.points[0] })"
        )
        drainMainQueue()
        XCTAssertNil(BannerOverlayHost.shared.overlayLeavesAt, "nothing leaves")
    }

    /// A popup opened the overlay, so the flyout that replaced it fades out.
    @MainActor
    func testAFlyoutLeavesAsThePopupBeforeItCameIn() {
        let stage = overlayStage()
        defer { takeDown(stage) }
        stage.viewModel.popupBanner = popup("popup")
        settle(stage)
        let banner = flyout("fly")
        stage.viewModel.flyoutBanner = banner
        stage.viewModel.popupBanner = nil
        settle(stage)

        stage.viewModel.dismissFlyout(banner)
        assertFades(film(stage), from: Self.dimmed, to: Self.clear)
    }

    /// A flyout opened the overlay, so the popup that replaced it slides down with its dim, off the
    /// bottom of the window.
    @MainActor
    func testAPopupLeavesAsTheFlyoutBeforeItCameIn() {
        let stage = overlayStage()
        defer { takeDown(stage) }
        stage.viewModel.flyoutBanner = flyout("fly")
        settle(stage)
        let banner = popup("popup")
        stage.viewModel.popupBanner = banner
        stage.viewModel.flyoutBanner = nil
        settle(stage)

        stage.viewModel.dismissPopup(banner)
        assertSlidesOut(film(stage))
    }

    // MARK: - Assertions

    private static let clear = 255.0
    private static let dimmed = 127.5
    private static let frameInterval: TimeInterval = 1.0 / 60
    /// Frames in UIKit's half second.
    private static let transitionFrames = Int((BannerChrome.modalTransitionDuration / frameInterval).rounded())
    /// Frames SwiftUI may take to start moving a change it has drawn.
    private static let startFrames = 4

    /// How far along UIKit's modal spring is `t` seconds after it starts: mass 3, stiffness 1000,
    /// critically damped.
    private static func springProgress(_ t: TimeInterval) -> Double {
        let omega = (1000.0 / 3).squareRoot()
        return 1 - (1 + omega * t) * exp(-omega * t)
    }

    @MainActor
    private func assertSlidesIn(_ frames: [Frame], file: StaticString = #filePath, line: UInt = #line) {
        let edges = frames.map(\.dimEdge)
        XCTAssertTrue(frames.allSatisfy(\.dimIsWholeOrNone), "the dim slides in, it does not fade", file: file, line: line)
        XCTAssertTrue(isMonotonic(edges, rising: false), "the dim only moves up, edges \(edges)", file: file, line: line)
        guard let shown = frames.firstIndex(where: \.showsDim) else {
            return XCTFail("the dim was not drawn, edges \(edges)", file: file, line: line)
        }
        let start = Double(edges[shown])
        XCTAssertGreaterThanOrEqual(start, Self.windowSize.height, "the dim comes in from below the window, edges \(edges)", file: file, line: line)
        assertFollowsTheSpring(edges.map(Double.init)[shown...], from: start, to: 0, tolerance: 3, file: file, line: line)
        XCTAssertEqual(edges.last, 0, "the dim covers the window once the slide has run", file: file, line: line)
    }

    @MainActor
    private func assertSlidesOut(_ frames: [Frame], file: StaticString = #filePath, line: UInt = #line) {
        let edges = frames.map(\.dimEdge)
        XCTAssertTrue(frames.allSatisfy(\.dimIsWholeOrNone), "the dim slides out, it does not fade", file: file, line: line)
        XCTAssertTrue(isMonotonic(edges, rising: true), "the dim only moves down, edges \(edges)", file: file, line: line)
        XCTAssertEqual(edges.first, 0, "the dim covers the window as it starts to leave", file: file, line: line)
        // The lowest the dim was drawn before it went.
        guard let end = frames.filter(\.showsDim).map(\.dimEdge).max() else {
            return XCTFail("the dim was not drawn, edges \(edges)", file: file, line: line)
        }
        XCTAssertGreaterThanOrEqual(
            CGFloat(end),
            Self.windowSize.height,
            "the dim slides off the window rather than stopping short of its bottom edge, edges \(edges)",
            file: file,
            line: line
        )
        assertFollowsTheSpring(edges.map(Double.init)[...], from: 0, to: Double(end), tolerance: 3, file: file, line: line)
        XCTAssertFalse(frames.last?.showsDim ?? true, "the dim is gone once the slide has run", file: file, line: line)
    }

    @MainActor
    private func assertFades(_ frames: [Frame], from: Double, to: Double, file: StaticString = #filePath, line: UInt = #line) {
        let shades = frames.map { $0.value(at: Self.top) }
        let darkens = to < from
        XCTAssertTrue(frames.allSatisfy(\.dimIsEven), "the dim fades evenly, it does not slide, shades \(shades)", file: file, line: line)
        XCTAssertTrue(
            isMonotonic(shades, rising: !darkens),
            "the dim only \(darkens ? "darkens" : "lightens"), shades \(shades)",
            file: file,
            line: line
        )
        assertFollowsTheSpring(shades.map(Double.init)[...], from: from, to: to, tolerance: 2, file: file, line: line)
        XCTAssertEqual(
            Double(shades.last ?? 0),
            to,
            accuracy: 2,
            "the dim is \(darkens ? "in place" : "gone") once the fade has run",
            file: file,
            line: line
        )
    }

    /// `values`, one a frame, hold at `from`, start moving within `startFrames` of the change being
    /// drawn, then follow UIKit's modal spring to `to` in every frame, there by the end of UIKit's
    /// half second. Indices count frames from the change being drawn.
    private func assertFollowsTheSpring(
        _ values: ArraySlice<Double>,
        from: Double,
        to: Double,
        tolerance: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let all = values.map { Int($0) }
        let held = values.prefix { abs($0 - from) <= tolerance }
        guard let start = held.indices.last else {
            return XCTFail("the transition does not start at \(from), values \(all)", file: file, line: line)
        }
        XCTAssertLessThanOrEqual(start, Self.startFrames, "the transition starts as soon as it is drawn, values \(all)", file: file, line: line)
        guard start + Self.transitionFrames < values.endIndex else {
            return XCTFail("no transition from \(from) was filmed whole, values \(all)", file: file, line: line)
        }
        let misses = (0...Self.transitionFrames).compactMap { frame -> String? in
            let expected = from + (to - from) * Self.springProgress(Double(frame) * Self.frameInterval)
            let actual = values[start + frame]
            return abs(actual - expected) <= tolerance ? nil : "frame \(frame): \(Int(actual)), not \(Int(expected.rounded()))"
        }
        XCTAssertTrue(misses.isEmpty, "the transition follows UIKit's modal spring, \(misses), values \(all)", file: file, line: line)
    }

    /// Whether `values` only ever move one way, give or take a rounding step.
    private func isMonotonic(_ values: [Int], rising: Bool) -> Bool {
        zip(values, values.dropFirst()).allSatisfy { rising ? $1 >= $0 - 1 : $1 <= $0 + 1 }
    }

    // MARK: - Harness

    /// The overlay under test: its window, the view model it draws, and the hosting controller
    /// whose clock the tests run.
    private struct Stage {
        let window: UIWindow
        let viewModel: BannerDisplayViewModel
        let controller: BannerOverlayHostingController
    }

    /// One drawn frame: the red channel down `dimColumn`, one value per point from the top of the
    /// window to a window's height below it, and at any points asked for.
    private struct Frame {
        let column: [Int]
        let points: [Int]

        func value(at y: Int) -> Int { column[y] }

        /// The first row from the top that is dimmed, or the column's length where none is. Rows
        /// below the window show a dim sliding in or out.
        var dimEdge: Int { column.firstIndex { $0 < 250 } ?? column.count }

        var showsDim: Bool { dimEdge < column.count }

        /// Every row is either dimmed in full or not at all, as when a dim slides, but for the row
        /// its edge crosses.
        var dimIsWholeOrNone: Bool { column.filter { $0 < 250 && abs($0 - 128) > 3 }.count <= 2 }

        /// The top and the bottom of the window are equally dimmed, as when a dim fades.
        var dimIsEven: Bool { abs(value(at: BannerFlyoutSlideTests.top) - value(at: BannerFlyoutSlideTests.bottom)) <= 3 }
    }

    /// Draws the change just made, then `count` frames more, a frame apart on the hosting
    /// controller's clock.
    @MainActor
    private func film(_ stage: Stage, frames count: Int = 60, at points: [CGPoint] = []) -> [Frame] {
        stage.controller._render(seconds: 0)
        var frames = [frame(of: stage.window, at: points)]
        for _ in 0..<count {
            stage.controller._render(seconds: Self.frameInterval)
            frames.append(frame(of: stage.window, at: points))
        }
        return frames
    }

    /// Runs the hosting controller's clock on by a second, a frame at a time, then lets the main
    /// queue catch up.
    @MainActor
    private func settle(_ stage: Stage) {
        for _ in 0..<Int(1 / Self.frameInterval) {
            stage.controller._render(seconds: Self.frameInterval)
        }
        drainMainQueue()
    }

    @MainActor
    private func frame(of window: UIWindow, at points: [CGPoint]) -> Frame {
        let height = Int(window.bounds.height)
        return Frame(
            column: reds(of: window, x: Self.dimColumn, y: 0, count: height * 2),
            points: points.map { reds(of: window, x: Int($0.x), y: Int($0.y), count: 1)[0] }
        )
    }

    /// The red channel of the `count` pixels down column `x` from row `y`, drawn over white. The
    /// model layers are drawn: `_render(seconds:)` sets each frame on them, and the presentation
    /// layers keep the last frame committed.
    @MainActor
    private func reds(of window: UIWindow, x: Int, y: Int, count: Int) -> [Int] {
        var bytes = [UInt8](repeating: 0, count: count * 4)
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: count,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 1, height: count))
            context.translateBy(x: CGFloat(-x), y: CGFloat(count + y))
            context.scaleBy(x: 1, y: -1)
            window.layer.render(in: context)
        }
        return (0..<count).map { Int(bytes[$0 * 4]) }
    }

    @MainActor
    private func overlayStage() -> Stage {
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
        return Stage(window: window, viewModel: viewModel, controller: controller)
    }

    @MainActor
    private func takeDown(_ stage: Stage) {
        BannerOverlayHost.shared.detach(stage.viewModel)
        stage.window.isHidden = true
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
