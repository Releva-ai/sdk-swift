import SwiftUI
import UIKit
import XCTest
@testable import RelevaSDK

/// Renders the overlay window's content for a popup and for top/bottom bars into PNG files so
/// the chrome can be inspected without a device. Skipped unless `RLV_SNAPSHOT_DIR` is set.
final class BannerOverlaySnapshotTests: XCTestCase {
    private var snapshotDir: String? { ProcessInfo.processInfo.environment["RLV_SNAPSHOT_DIR"] }

    @MainActor
    private func design(rowColor: String, extraBody: [String: JSONValue] = [:]) -> [String: JSONValue] {
        var bodyValues: [String: JSONValue] = [
            "popupWidth": "600px", "borderRadius": "10px", "popupBackgroundColor": "#FFFFFF",
            "popupOverlay_backgroundColor": "rgba(0, 0, 0, 0.5)", "contentWidth": "500px",
            "backgroundColor": "#F7F8F9", "textColor": "#FFFFFF",
            "popupCloseButton_backgroundColor": "#DDDDDD", "popupCloseButton_iconColor": "#000000",
        ]
        for (k, v) in extraBody { bodyValues[k] = v }
        return [
            "body": [
                "values": .object(bodyValues),
                "rows": [
                    [
                        "values": ["backgroundColor": .string(rowColor), "padding": "0px"],
                        "columns": [
                            [
                                "values": [:],
                                "contents": [
                                    ["type": "heading", "values": ["text": "🎉Нова зона🎉", "fontSize": "32px", "textAlign": "center", "containerPadding": "24px 10px 10px", "color": "#FFFFFF"]],
                                    ["type": "text", "values": ["text": "<p>Заповядайте в новата SPARK зона в West Mall в кв. \"Люлин\"</p>", "fontSize": "18px", "textAlign": "center", "containerPadding": "10px", "color": "#FFFFFF"]],
                                    ["type": "button", "values": ["text": "OK", "href": ["values": ["href": "https://spark.bg"]], "buttonColors": ["backgroundColor": "#FFFFFF", "color": "#000000"], "borderRadius": "30px", "containerPadding": "20px 10px 28px", "padding": "14px 40px", "textAlign": "center"]],
                                ],
                            ],
                        ],
                    ],
                ],
            ],
        ]
    }

    /// Lays the overlay out in an iPhone-sized window over a fake dark app, runs `check` on the
    /// resulting geometry, and — only when `RLV_SNAPSHOT_DIR` is set — writes a PNG for eyes.
    ///
    /// The geometry checks always run: each display type has its own layout contract, and a
    /// change to one (device run 21: the bar rework) must not be able to break another (the
    /// popup) without a test going red.
    @MainActor
    private func snapshot(
        named name: String,
        configure: (BannerDisplayViewModel) -> Void,
        check: (BannerOverlayHost, UIWindow) -> Void = { _, _ in }
    ) throws {
        let dir = snapshotDir

        let viewModel = BannerDisplayViewModel()
        configure(viewModel)
        let host = BannerOverlayHost.shared
        host.attach(viewModel, onLinkTap: { _ in })

        let controller = BannerOverlayHostingController(rootView: BannerOverlayRoot(host: host))
        controller.host = host
        controller.view.backgroundColor = .clear
        // iPhone-like insets: status bar and home indicator.
        controller.additionalSafeAreaInsets = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)

        // The app behind: a dark screen with a fake title and tab bar, so the layering is visible.
        let backdrop = UIHostingController(rootView: FakeApp())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = backdrop
        window.makeKeyAndVisible()
        backdrop.view.frame = window.bounds
        controller.view.frame = window.bounds
        window.addSubview(controller.view)
        backdrop.addChild(controller)
        window.layoutIfNeeded()
        drainMainQueue(turns: 6)
        window.layoutIfNeeded()

        check(host, window)

        if let dir = dir {
            let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
            // `drawHierarchy` needs the render server, which a scene-less test window has no
            // access to; rendering the layer tree works offscreen.
            let image = renderer.image { context in
                window.layer.render(in: context.cgContext)
            }
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
            try image.pngData()?.write(to: url)
        }
        host.detach(viewModel)
        window.isHidden = true
    }

    /// The window-space frame of the first view whose accessibility identifier is `id`.
    @MainActor
    private func frame(of id: String, in window: UIWindow) -> CGRect? {
        func search(_ view: UIView) -> UIView? {
            if view.accessibilityIdentifier == id { return view }
            for sub in view.subviews { if let hit = search(sub) { return hit } }
            return nil
        }
        guard let view = search(window) else { return nil }
        return view.convert(view.bounds, to: window)
    }

    /// Popup contract: a dim over the whole screen, and a card that is as tall as its design —
    /// a short design must not become a screen-high card — sitting inside the safe area.
    @MainActor
    func testPopupSnapshot() throws {
        try snapshot(named: "popup", configure: { vm in
            vm.popupBanner = BannerResponse(token: "popup", displayType: "popup", design: design(rowColor: "#3A3FE0"))
        }, check: { host, window in
            XCTAssertTrue(host.coversScreen, "a popup owns every touch")
            XCTAssertTrue(host.interactiveFrames.isEmpty, "a popup reports no pass-through frames")
        })
    }

    /// Bar contract: one full-width strip touching the screen edge it is pinned to, reported as
    /// the only touch-claiming frame so the rest of the app stays usable.
    @MainActor
    func testTopBarSnapshot() throws {
        try snapshot(named: "bar_top", configure: { vm in
            vm.barBanners = [BannerResponse(token: "bar", displayType: "bar", displayPosition: "top", design: design(rowColor: "#3A3FE0"))]
        }, check: { host, window in
            XCTAssertFalse(host.coversScreen)
            guard let bar = host.interactiveFrames.first, host.interactiveFrames.count == 1 else {
                return XCTFail("expected exactly one bar frame, got \(host.interactiveFrames)")
            }
            XCTAssertEqual(bar.minY, 0, accuracy: 0.5, "top bar touches the top edge")
            XCTAssertEqual(bar.width, window.bounds.width, accuracy: 0.5, "top bar spans the width")
            XCTAssertGreaterThan(bar.height, 59, "top bar pads for the status bar")
            XCTAssertLessThan(bar.height, window.bounds.height / 2, "a short design stays a strip")
        })
    }

    /// Flyout contract (web: fixed, bottom 0, left/right 20 px, width auto, no overlay): one
    /// content-sized panel at the bottom of the safe area, 20 pt in from its side, never the
    /// whole screen, and the rest of the screen passes touches through.
    @MainActor
    func testFlyoutRightSnapshot() throws {
        try snapshot(named: "flyout_right", configure: { vm in
            vm.flyoutBanner = BannerResponse(token: "fly", displayType: "flyout", displayPosition: "right", design: design(rowColor: "#3A3FE0"))
        }, check: { host, window in
            XCTAssertFalse(host.coversScreen, "a flyout has no overlay")
            guard let panel = host.interactiveFrames.first, host.interactiveFrames.count == 1 else {
                return XCTFail("expected exactly one flyout frame, got \(host.interactiveFrames)")
            }
            XCTAssertEqual(panel.maxX, window.bounds.width - 20, accuracy: 0.5, "20 pt from the right edge")
            XCTAssertLessThanOrEqual(panel.width, window.bounds.width * 0.72 + 0.5, "leaves the docking side visible")
            XCTAssertGreaterThan(panel.minX, window.bounds.width * 0.2, "clearly docked right, not centred")
            // The scene-less test window reports its own bottom inset (more than the 34 pt
            // requested); the contract is "flush with whatever the bottom safe-area edge is".
            XCTAssertGreaterThanOrEqual(host.safeAreaInsets.bottom, 34)
            XCTAssertEqual(panel.maxY, window.bounds.height - host.safeAreaInsets.bottom, accuracy: 0.5, "sits on the bottom safe-area edge")
            XCTAssertLessThan(panel.height, window.bounds.height / 2, "a short design stays a panel")
            XCTAssertGreaterThan(panel.minY, host.safeAreaInsets.top, "never under the status bar")
        })
    }

    @MainActor
    func testFlyoutLeftSnapshot() throws {
        try snapshot(named: "flyout_left", configure: { vm in
            vm.flyoutBanner = BannerResponse(token: "fly", displayType: "flyout", displayPosition: "left", design: design(rowColor: "#3A3FE0"))
        }, check: { host, window in
            guard let panel = host.interactiveFrames.first, host.interactiveFrames.count == 1 else {
                return XCTFail("expected exactly one flyout frame, got \(host.interactiveFrames)")
            }
            XCTAssertEqual(panel.minX, 20, accuracy: 0.5, "20 pt from the left edge")
            XCTAssertEqual(panel.maxY, window.bounds.height - host.safeAreaInsets.bottom, accuracy: 0.5)
        })
    }

    @MainActor
    func testBottomBarSnapshot() throws {
        try snapshot(named: "bar_bottom", configure: { vm in
            vm.barBanners = [BannerResponse(token: "bar", displayType: "bar", displayPosition: "bottom", design: design(rowColor: "#3A3FE0"))]
        }, check: { host, window in
            guard let bar = host.interactiveFrames.first, host.interactiveFrames.count == 1 else {
                return XCTFail("expected exactly one bar frame, got \(host.interactiveFrames)")
            }
            XCTAssertEqual(bar.maxY, window.bounds.height, accuracy: 0.5, "bottom bar touches the bottom edge")
            XCTAssertEqual(bar.width, window.bounds.width, accuracy: 0.5)
            XCTAssertLessThan(bar.height, window.bounds.height / 2)
        })
    }
}

private struct FakeApp: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Shop").font(.largeTitle.bold()); Spacer(); Image(systemName: "cart").font(.title) }
                .padding(.horizontal, 16).padding(.top, 70)
            Spacer()
            HStack { ForEach(["Home", "Inbox", "Cart", "Settings"], id: \.self) { Text($0).frame(maxWidth: .infinity) } }
                .padding(.bottom, 40).padding(.top, 12).background(Color(white: 0.1))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .foregroundColor(.white)
        .ignoresSafeArea()
    }
}
