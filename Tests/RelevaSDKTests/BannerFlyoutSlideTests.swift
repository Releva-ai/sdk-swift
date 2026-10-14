import SwiftUI
import UIKit
import XCTest
@testable import RelevaSDK

/// A flyout and its dim slide up from the bottom of the window when the overlay opens with it and
/// back down when it closes, as sdk-react-native's `Modal animationType="slide"` does. A popup and
/// a flyout replacing each other swap in place, as the content of one Modal does.
///
/// The overlay is drawn over a white window, so a sample reads 255 where nothing is dimmed, 128
/// under the 50% dim, and 0 on the flyout, whose design is black.
final class BannerFlyoutSlideTests: XCTestCase {
    private static let windowSize = CGSize(width: 393, height: 852)
    /// Long enough for a frame or two of the slide, short of its end.
    private static let early: TimeInterval = 0.06
    private static let top = CGPoint(x: 10, y: 20)
    private static let bottom = CGPoint(x: 10, y: 840)

    @MainActor
    func testTheFlyoutSlidesUpFromTheBottomWhenItOpens() {
        let (window, viewModel) = overlayWindow()
        defer { takeDown(window, viewModel) }

        viewModel.flyoutBanner = flyout("fly-in")
        pump(for: Self.early)
        XCTAssertGreaterThan(sample(Self.top, in: window), 250, "the dim has not reached the top yet")
        XCTAssertEqual(sample(Self.bottom, in: window), 128, accuracy: 2, "the dim has come in from the bottom")

        pump(for: 1)
        XCTAssertEqual(sample(Self.top, in: window), 128, accuracy: 2, "the dim covers the screen once the slide has run")
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
        XCTAssertNotNil(BannerOverlayHost.shared.flyoutLeavesAt, "the window stays up while the flyout slides out")
        pump(for: Self.early)
        XCTAssertGreaterThan(sample(Self.top, in: window), 250, "the dim has left the top")
        XCTAssertEqual(sample(Self.bottom, in: window), 128, accuracy: 2, "the dim is still leaving at the bottom")

        pump(for: 1)
        XCTAssertGreaterThan(sample(Self.bottom, in: window), 250, "the flyout is gone")
        XCTAssertNil(BannerOverlayHost.shared.flyoutLeavesAt, "the window can go once the slide has run")
    }

    @MainActor
    func testAFlyoutReplacingAPopupIsInPlaceAtOnce() {
        let (window, viewModel) = overlayWindow()
        defer { takeDown(window, viewModel) }
        viewModel.popupBanner = popup("popup")
        pump(for: 1)

        viewModel.flyoutBanner = flyout("fly")
        viewModel.popupBanner = nil
        pump(for: Self.early)
        XCTAssertEqual(sample(CGPoint(x: 380, y: 20), in: window), 0, accuracy: 2, "the flyout is already at the top")
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
        XCTAssertNil(BannerOverlayHost.shared.flyoutLeavesAt, "nothing slides out")
        pump(for: Self.early)
        XCTAssertEqual(sample(CGPoint(x: 388, y: 840), in: window), 128, accuracy: 2, "the flyout is gone, the popup's dim is there")
    }

    /// A popup still appears at once, with its dim.
    @MainActor
    func testAPopupDoesNotSlide() {
        let (window, viewModel) = overlayWindow()
        defer { takeDown(window, viewModel) }

        viewModel.popupBanner = popup("popup")
        pump(for: Self.early)
        XCTAssertEqual(sample(Self.top, in: window), 128, accuracy: 2, "the popup's dim is in place at once")
    }

    // MARK: - Harness

    @MainActor
    private func overlayWindow() -> (UIWindow, BannerDisplayViewModel) {
        let viewModel = BannerDisplayViewModel()
        let host = BannerOverlayHost.shared
        host.attach(viewModel) { _ in }
        let controller = BannerOverlayHostingController(rootView: BannerOverlayRoot(host: host))
        controller.host = host
        controller.view.backgroundColor = .clear
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

    /// The red channel drawn at `point`, 0...255.
    @MainActor
    private func sample(_ point: CGPoint, in window: UIWindow) -> Int {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { context in
            window.layer.render(in: context.cgContext)
        }
        var pixel = [UInt8](repeating: 0, count: 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        if let cgImage = image.cgImage,
           let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) {
            context.draw(cgImage, in: CGRect(x: -point.x, y: point.y - CGFloat(cgImage.height) + 1, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
        }
        return Int(pixel[0])
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
