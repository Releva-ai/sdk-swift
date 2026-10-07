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
            "popupCloseButton_backgroundColor": "#DDDDDD", "popupCloseButton_iconColor": "#000000"
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
                                    ["type": "button", "values": ["text": "OK", "href": ["values": ["href": "https://spark.bg"]], "buttonColors": ["backgroundColor": "#FFFFFF", "color": "#000000"], "borderRadius": "30px", "containerPadding": "20px 10px 28px", "padding": "14px 40px", "textAlign": "center"]]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]
    }

    /// Lays the overlay out in an iPhone-sized window over a fake dark app, runs `check` on the
    /// resulting geometry, and — only when `RLV_SNAPSHOT_DIR` is set — writes a PNG for eyes.
    ///
    /// The geometry checks always run: each display type has its own layout contract, and a change
    /// to one must not break another without a test going red.
    @MainActor
    private func snapshot(
        named name: String,
        size: CGSize = CGSize(width: 393, height: 852),
        configure: (BannerDisplayViewModel) -> Void,
        check: (BannerOverlayHost, UIWindow) -> Void = { _, _ in }
    ) throws {
        let dir = snapshotDir

        let viewModel = BannerDisplayViewModel()
        configure(viewModel)
        let host = BannerOverlayHost.shared
        host.attach(viewModel) { _ in }

        let controller = BannerOverlayHostingController(rootView: BannerOverlayRoot(host: host))
        controller.host = host
        controller.view.backgroundColor = .clear
        // iPhone-like insets: status bar and home indicator.
        controller.additionalSafeAreaInsets = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)

        // The app behind: a dark screen with a fake title and tab bar, so the layering is visible.
        let backdrop = UIHostingController(rootView: FakeApp())
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
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

    // WHY THERE IS NO `frame(of: identifier:)` HELPER HERE, which this file carried unused
    // until 2026-10-04 and which does not work: it walked the window's `UIView` tree looking
    // for `accessibilityIdentifier`, and SwiftUI content does not put one there. A
    // `.accessibilityIdentifier` on a SwiftUI view sets an accessibility element's identifier,
    // not a backing view's, and a hosting controller renders most of a view tree into very few
    // `UIView`s. Adding the modifier to the close control and asking for its frame returned nil
    // on CI, twice.
    //
    // What IS observable is `host.interactiveFrames`, which the SDK itself publishes through
    // `reportBannerFrame()` for hit-testing — a production mechanism with a production purpose,
    // not a test hook. Anything a test wants to measure has to be something the SDK already
    // reports, or it has to be measured somewhere other than the rendered tree. See
    // `BannerChromeCloseControlTests` for the second of those.

    /// Popup contract: a dim over the whole screen, and a card that is as tall as its design —
    /// a short design must not become a screen-high card — sitting inside the safe area, sized
    /// and centred the way `BannerCardStyle.cardWidth` says: 600 pt capped to the window's own
    /// width minus 16 pt each side (here `min(600, 393 - 32) = 361`), not to `UIScreen`.
    @MainActor
    func testPopupSnapshot() throws {
        try snapshot(named: "popup") { vm in
            vm.popupBanner = BannerResponse(token: "popup", displayType: "popup", design: design(rowColor: "#3A3FE0"))
        } check: { host, window in
            XCTAssertTrue(host.coversScreen, "a popup owns every touch")
            // `coversScreen`, not this frame, is what gates touch pass-through for a popup; the
            // card still reports its own frame — the same mechanism a bar or a flyout uses — so
            // its geometry is observable here.
            guard let card = host.interactiveFrames.first, host.interactiveFrames.count == 1 else {
                return XCTFail("expected exactly one popup card frame, got \(host.interactiveFrames)")
            }
            XCTAssertEqual(card.width, min(600, window.bounds.width - 32), accuracy: 0.5)
            XCTAssertEqual(card.midX, window.bounds.width / 2, accuracy: 0.5, "centred with no position keys authored")
        }
    }

    /// Regression guard for the popup's own pre-existing `popupWidth`/`borderRadius`/
    /// `popupBackgroundColor` body-value reads: with none of the nine new `cssStyles` keys
    /// authored, a design whose body values differ from this SDK's own 600/10/white literals
    /// must still lay out off the body values, exactly as it did before this change. Width is
    /// the one of the three with a geometry consequence this harness can observe directly; the
    /// authored value must land strictly between `cardWidth`'s 120 pt floor and this window's
    /// `393 - 32 = 361` pt cap, or the cap would produce the same frame with or without the
    /// fallback and the assertion below would pass either way. `BannerCardStyleTests` covers the
    /// corner-radius branch of the same fallback at the unit level
    /// (`testTheDefaultBorderRadiusFallsBackToTheCallersLegacyDefaultNotItsOwnTenPoints`); the
    /// background-colour branch lives inline in `BannerChrome.popup`
    /// (`cardBackground = style.backgroundColor ?? DesignRenderer.parseColor(...) ?? .white`)
    /// rather than in `BannerCardStyle`, and has no coverage at either level today.
    @MainActor
    func testPopupWithNoChromeKeysStillFallsBackToTheDesignsBodyValues() throws {
        try snapshot(named: "popup_body_value_fallback") { vm in
            vm.popupBanner = BannerResponse(
                token: "popup",
                displayType: "popup",
                design: design(rowColor: "#3A3FE0", extraBody: ["popupWidth": "200px"])
            )
        } check: { host, _ in
            guard let card = host.interactiveFrames.first, host.interactiveFrames.count == 1 else {
                return XCTFail("expected exactly one popup card frame, got \(host.interactiveFrames)")
            }
            XCTAssertEqual(card.width, 200, accuracy: 0.5, "the design's own popupWidth, not the SDK's 600 pt literal")
        }
    }

    /// A design of `rows` identical single-text rows, so two designs that differ only in row
    /// count give a popup whose content height is exactly `rows * (one row's height)` — no
    /// heading, button or image whose own height would break that proportionality.
    @MainActor
    private func repeatedRowDesign(rows: Int) -> [String: JSONValue] {
        let row: JSONValue = [
            "values": ["backgroundColor": "#3A3FE0", "padding": "0px"],
            "columns": [
                [
                    "values": [:],
                    "contents": [
                        ["type": "text", "values": ["text": "<p>Row</p>", "fontSize": "18px", "textAlign": "center", "containerPadding": "20px 10px", "color": "#FFFFFF"]]
                    ]
                ]
            ]
        ]
        return [
            "body": [
                "values": [
                    "popupWidth": "600px", "borderRadius": "10px", "popupBackgroundColor": "#FFFFFF",
                    "popupOverlay_backgroundColor": "rgba(0, 0, 0, 0.5)"
                ],
                "rows": .array(Array(repeating: row, count: rows))
            ]
        ]
    }

    /// Observes the band actually reaching a layout call, rather than pinning its own
    /// declaration the way `BannerChromeCloseControlTests` does (and says why that is all it
    /// can do). `host.interactiveFrames` is the only frame this SDK publishes for a popup — see
    /// the note above on why there is no `frame(of:)` helper — so this derives the band from two
    /// cards whose designs differ only by a repeated, identical row, instead of asserting an
    /// absolute height.
    ///
    /// At `cardHeight == nil` (every banner in production today) the reported card height is
    /// `content height + closeControlBand`: `BannerChrome.popup` adds the band back as top
    /// padding (`BannerChrome.swift:82`), and `CappedHeightContent` only switches to a clipped
    /// `ScrollView` once the content is taller than its budget — two or three short text rows
    /// stay well under it regardless of whether that budget was reduced by the band
    /// (`:78`), so this test only guards the padding, not the budget reduction. So with
    /// `oneRow` and `twoRows` built from the identical row:
    ///   `oneRow  == rowHeight + band`
    ///   `twoRows == 2 * rowHeight + band`
    /// `twoRows - oneRow` cancels the band and leaves `rowHeight`; subtracting that back out of
    /// `oneRow` leaves the band. Remove the padding at `:82` and the derived band drops to 0
    /// here, while the three assertions in `BannerChromeCloseControlTests` stay green
    /// throughout, because they pin the constant against its own definition rather than its
    /// use.
    @MainActor
    func testTheBandIsReflectedInThePopupsReportedHeight() throws {
        var heights: [Int: CGFloat] = [:]
        for rowCount in [1, 2] {
            try snapshot(named: "popup_band_\(rowCount)_row") { vm in
                vm.popupBanner = BannerResponse(token: "popup", displayType: "popup", design: repeatedRowDesign(rows: rowCount))
            } check: { host, _ in
                guard let card = host.interactiveFrames.first, host.interactiveFrames.count == 1 else {
                    return XCTFail("expected exactly one popup card frame, got \(host.interactiveFrames)")
                }
                heights[rowCount] = card.height
            }
        }
        let oneRow = try XCTUnwrap(heights[1], "no frame recorded for the one-row popup")
        let twoRows = try XCTUnwrap(heights[2], "no frame recorded for the two-row popup")
        let rowHeight = twoRows - oneRow
        XCTAssertGreaterThan(rowHeight, 1, "the second row must add measurable height, or this derivation proves nothing")
        let derivedBand = oneRow - rowHeight
        XCTAssertEqual(
            derivedBand,
            BannerChrome.closeControlBand,
            accuracy: 1,
            "the band BannerChrome.popup reserves via its padding and height budget should show up in the reported frame"
        )
    }

    /// Bar contract: one full-width strip touching the screen edge it is pinned to, reported as
    /// the only touch-claiming frame so the rest of the app stays usable.
    @MainActor
    func testTopBarSnapshot() throws {
        try snapshot(named: "bar_top") { vm in
            vm.barBanners = [BannerResponse(token: "bar", displayType: "bar", displayPosition: "top", design: design(rowColor: "#3A3FE0"))]
        } check: { host, window in
            XCTAssertFalse(host.coversScreen)
            guard let bar = host.interactiveFrames.first, host.interactiveFrames.count == 1 else {
                return XCTFail("expected exactly one bar frame, got \(host.interactiveFrames)")
            }
            XCTAssertEqual(bar.minY, 0, accuracy: 0.5, "top bar touches the top edge")
            XCTAssertEqual(bar.width, window.bounds.width, accuracy: 0.5, "top bar spans the width")
            XCTAssertGreaterThan(bar.height, 59, "top bar pads for the status bar")
            XCTAssertLessThan(bar.height, window.bounds.height / 2, "a short design stays a strip")
        }
    }

    /// Flyout contract (mobile spec, deviating from the web's 20 px gap on purpose): one
    /// content-sized sheet flush with its screen edge at the bottom of the safe area, never the
    /// whole screen, and the rest of the screen passes touches through.
    @MainActor
    func testFlyoutRightSnapshot() throws {
        try snapshot(named: "flyout_right") { vm in
            vm.flyoutBanner = BannerResponse(token: "fly", displayType: "flyout", displayPosition: "right", design: design(rowColor: "#3A3FE0"))
        } check: { host, window in
            XCTAssertFalse(host.coversScreen, "a flyout has no overlay")
            guard let panel = host.interactiveFrames.first, host.interactiveFrames.count == 1 else {
                return XCTFail("expected exactly one flyout frame, got \(host.interactiveFrames)")
            }
            XCTAssertEqual(panel.maxX, window.bounds.width, accuracy: 0.5, "flush with the right edge")
            XCTAssertLessThanOrEqual(panel.width, window.bounds.width * 0.72 + 0.5, "leaves the docking side visible")
            XCTAssertGreaterThan(panel.minX, window.bounds.width * 0.2, "clearly docked right, not centred")
            // The scene-less test window reports its own bottom inset (more than the 34 pt
            // requested); the contract is "flush with whatever the bottom safe-area edge is".
            XCTAssertGreaterThanOrEqual(host.safeAreaInsets.bottom, 34)
            XCTAssertEqual(panel.maxY, window.bounds.height, accuracy: 0.5, "reaches the screen bottom")
            XCTAssertEqual(panel.minY, host.safeAreaInsets.top, accuracy: 1, "drawer fills to just under the status bar even for a short design")
        }
    }

    /// A design taller than the screen grows to just under the status bar and scrolls there.
    @MainActor
    func testFlyoutCapsTallDesign() throws {
        var tall = design(rowColor: "#3A3FE0")
        var body = try XCTUnwrap(tall["body"]?.objectValue)
        var rows = try XCTUnwrap(body["rows"]?.arrayValue)
        var row = try XCTUnwrap(rows[0].objectValue)
        var columns = try XCTUnwrap(row["columns"]?.arrayValue)
        var column = try XCTUnwrap(columns[0].objectValue)
        var contents = try XCTUnwrap(column["contents"]?.arrayValue)
        for i in 0..<14 {
            contents.append(["type": "text", "values": ["text": .string("<p>Line \(i) of a very long design</p>"), "fontSize": "18px", "containerPadding": "10px", "color": "#FFFFFF"]])
        }
        column["contents"] = .array(contents); columns[0] = .object(column)
        row["columns"] = .array(columns); rows[0] = .object(row)
        body["rows"] = .array(rows); tall["body"] = .object(body)

        try snapshot(named: "flyout_tall") { vm in
            vm.flyoutBanner = BannerResponse(token: "fly", displayType: "flyout", displayPosition: "left", design: tall)
        } check: { host, window in
            guard let panel = host.interactiveFrames.first else { return XCTFail("no flyout frame") }
            XCTAssertEqual(panel.minY, host.safeAreaInsets.top, accuracy: 1, "grows up to the status bar, never under it")
            XCTAssertEqual(panel.maxY, window.bounds.height, accuracy: 0.5, "reaches the screen bottom")
        }
    }

    /// An image-only design gets exactly its image width plus padding, no body colour around it.
    @MainActor
    func testFlyoutHugsAnImageOnlyDesign() throws {
        let imageDesign: [String: JSONValue] = [
            "body": [
                "values": ["contentWidth": "500px", "backgroundColor": "#F7F8F9", "popupWidth": "600px"],
                "rows": [[
                    "values": ["padding": "0px"],
                    "columns": [[
                        "values": ["padding": "0px"],
                        "contents": [[
                            "type": "image",
                            "values": ["containerPadding": "10px", "src": ["url": "https://example.invalid/x.jpg", "width": 200, "height": 600]]
                        ]]
                    ]]
                ]]
            ]
        ]
        try snapshot(named: "flyout_image") { vm in
            vm.flyoutBanner = BannerResponse(token: "fly", displayType: "flyout", displayPosition: "left", design: imageDesign)
        } check: { host, _ in
            guard let panel = host.interactiveFrames.first else { return XCTFail("no flyout frame") }
            XCTAssertEqual(panel.width, 220, accuracy: 0.5, "200 px image + 10 px padding each side")
            XCTAssertEqual(panel.minX, 0, accuracy: 0.5)
        }
    }

    /// The drawer fills the height on small and large phones alike.
    @MainActor
    func testFlyoutFillsOnDifferentScreens() throws {
        for (name, size) in [("se", CGSize(width: 375, height: 667)), ("promax", CGSize(width: 430, height: 932))] {
            try snapshot(named: "flyout_\(name)", size: size) { vm in
                vm.flyoutBanner = BannerResponse(token: "fly", displayType: "flyout", displayPosition: "right", design: design(rowColor: "#3A3FE0"))
            } check: { host, window in
                guard let panel = host.interactiveFrames.first else { return XCTFail("no flyout frame on \(name)") }
                XCTAssertEqual(panel.minY, host.safeAreaInsets.top, accuracy: 1, "\(name): top under the status bar")
                XCTAssertEqual(panel.maxY, window.bounds.height, accuracy: 0.5, "\(name): bottom at the screen edge")
                XCTAssertEqual(panel.maxX, window.bounds.width, accuracy: 0.5, "\(name): flush right")
                XCTAssertLessThanOrEqual(panel.width, window.bounds.width * 0.72 + 0.5)
            }
        }
    }

    @MainActor
    func testFlyoutLeftSnapshot() throws {
        try snapshot(named: "flyout_left") { vm in
            vm.flyoutBanner = BannerResponse(token: "fly", displayType: "flyout", displayPosition: "left", design: design(rowColor: "#3A3FE0"))
        } check: { host, window in
            guard let panel = host.interactiveFrames.first, host.interactiveFrames.count == 1 else {
                return XCTFail("expected exactly one flyout frame, got \(host.interactiveFrames)")
            }
            XCTAssertEqual(panel.minX, 0, accuracy: 0.5, "flush with the left edge")
            XCTAssertEqual(panel.maxY, window.bounds.height, accuracy: 0.5)
        }
    }

    @MainActor
    func testBottomBarSnapshot() throws {
        try snapshot(named: "bar_bottom") { vm in
            vm.barBanners = [BannerResponse(token: "bar", displayType: "bar", displayPosition: "bottom", design: design(rowColor: "#3A3FE0"))]
        } check: { host, window in
            guard let bar = host.interactiveFrames.first, host.interactiveFrames.count == 1 else {
                return XCTFail("expected exactly one bar frame, got \(host.interactiveFrames)")
            }
            XCTAssertEqual(bar.maxY, window.bounds.height, accuracy: 0.5, "bottom bar touches the bottom edge")
            XCTAssertEqual(bar.width, window.bounds.width, accuracy: 0.5)
            XCTAssertLessThan(bar.height, window.bounds.height / 2)
        }
    }

    // MARK: - Card chrome and position keys

    /// Every `cssStyles` chrome and position key written out at the value the API documents as
    /// its default. Shared with `BannerCardStyleTests` — see `documentedBannerCardStyleDefaults`.
    private let documentedDefaults = documentedBannerCardStyleDefaults

    /// The regression guard for the whole adoption: a banner carrying all nine keys at their
    /// documented defaults must lay out exactly like one carrying none — which is every banner
    /// in production today. Compared as laid-out geometry rather than as pixels, so the
    /// assertion says which number moved when it goes red. With `RLV_SNAPSHOT_DIR` set the two
    /// PNGs are written side by side for eyes as well.
    ///
    /// Both arms run on this code, so this cannot by itself catch a drift between master and
    /// this branch — only that the two arms agree with each other on whatever this branch does.
    /// What pins the actual numbers master drew (600, the 32 pt cap, the 10 pt radius) is
    /// `BannerCardStyleTests` and `testPopupSnapshot`'s width assertion.
    @MainActor
    func testDefaultedKeysLayOutExactlyLikeNoKeysAtAll() throws {
        for displayType in ["popup", "flyout", "bar"] {
            var laidOut: [[CGRect]] = []
            for (suffix, cssStyles) in [("no_keys", [:] as [String: JSONValue]), ("defaults", documentedDefaults)] {
                try snapshot(named: "\(displayType)_\(suffix)") { vm in
                    let banner = BannerResponse(token: displayType, displayType: displayType, cssStyles: cssStyles, design: design(rowColor: "#3A3FE0"))
                    switch displayType {
                    case "bar": vm.barBanners = [banner]
                    case "popup": vm.popupBanner = banner
                    default: vm.flyoutBanner = banner
                    }
                } check: { host, _ in
                    laidOut.append(host.interactiveFrames)
                }
            }
            XCTAssertFalse(laidOut[0].isEmpty, "\(displayType): nothing was laid out, so nothing is being compared")
            XCTAssertEqual(laidOut[0], laidOut[1], "\(displayType): the nine keys at their defaults moved something")
        }
    }

    /// A bar with no `displayPosition` has always gone to the top edge; an authored
    /// `cardPositionVertical` is what now decides it.
    @MainActor
    func testAnAuthoredVerticalPositionSendsABarToTheBottomEdge() throws {
        try snapshot(named: "bar_bottom_authored") { vm in
            vm.barBanners = [BannerResponse(token: "bar", displayType: "bar", cssStyles: ["cardPositionVertical": "bottom"], design: design(rowColor: "#3A3FE0"))]
        } check: { host, window in
            guard let bar = host.interactiveFrames.first, host.interactiveFrames.count == 1 else {
                return XCTFail("expected exactly one bar frame, got \(host.interactiveFrames)")
            }
            XCTAssertEqual(bar.maxY, window.bounds.height, accuracy: 0.5, "the authored key overrides the absent displayPosition")
            XCTAssertLessThan(bar.height, window.bounds.height / 2, "a short design stays a strip")
        }
    }

    /// The same for the axis a flyout docks to, plus the width key reaching the layout call.
    @MainActor
    func testAnAuthoredHorizontalPositionAndWidthMoveAndSizeAFlyout() throws {
        try snapshot(named: "flyout_left_authored") { vm in
            vm.flyoutBanner = BannerResponse(token: "fly", displayType: "flyout", cssStyles: ["cardPositionHorizontal": "left", "cardWidth": "200px"], design: design(rowColor: "#3A3FE0"))
        } check: { host, _ in
            guard let panel = host.interactiveFrames.first else { return XCTFail("no flyout frame") }
            XCTAssertEqual(panel.minX, 0, accuracy: 0.5, "the authored key overrides the absent displayPosition, which would dock right")
            XCTAssertEqual(panel.width, 200, accuracy: 0.5, "cardWidth sizes the drawer instead of the design's content width")
        }
    }

    /// The popup is where eight of the nine keys actually reach a layout call
    /// (`BannerChrome.popup`), but until now only the no-keys/defaults case was observed. An
    /// authored position must reach the card the same way it does for a bar or a flyout: a
    /// left/bottom card lands at the safe area's leading/bottom edge rather than at the 16 pt
    /// the centred default implies.
    @MainActor
    func testAnAuthoredPositionMovesAPopupToAnEdge() throws {
        try snapshot(named: "popup_left_bottom_authored") { vm in
            vm.popupBanner = BannerResponse(
                token: "popup",
                displayType: "popup",
                cssStyles: ["cardPositionHorizontal": "left", "cardPositionVertical": "bottom"],
                design: design(rowColor: "#3A3FE0")
            )
        } check: { host, window in
            guard let card = host.interactiveFrames.first, host.interactiveFrames.count == 1 else {
                return XCTFail("expected exactly one popup card frame, got \(host.interactiveFrames)")
            }
            XCTAssertEqual(card.minX, 0, accuracy: 0.5, "cardPositionHorizontal: left reaches the card, not just centring")
            XCTAssertEqual(
                card.maxY,
                window.bounds.height - host.safeAreaInsets.bottom,
                accuracy: 1,
                "cardPositionVertical: bottom reaches the card, not just centring"
            )
        }
    }

    /// `.offset(...)` is applied outside `.reportBannerFrame()`'s `GeometryReader` in the popup's
    /// modifier chain (`BannerChrome.swift`), which only reflects the offset if SwiftUI resolves
    /// the offset before laying out that background — this snapshot is the only thing that
    /// answers that question for this codebase rather than leaving it asserted by a comment.
    @MainActor
    func testAnAuthoredOffsetShiftsThePopupCardsReportedFrame() throws {
        try snapshot(named: "popup_offset_authored") { vm in
            vm.popupBanner = BannerResponse(
                token: "popup",
                displayType: "popup",
                cssStyles: ["cardOffsetHorizontal": "-20px"],
                design: design(rowColor: "#3A3FE0")
            )
        } check: { host, window in
            guard let card = host.interactiveFrames.first, host.interactiveFrames.count == 1 else {
                return XCTFail("expected exactly one popup card frame, got \(host.interactiveFrames)")
            }
            XCTAssertEqual(
                card.midX,
                window.bounds.width / 2 - 20,
                accuracy: 0.5,
                "the reported frame moves with the offset instead of staying at the pre-offset centre"
            )
        }
    }

    /// `.frame(height:alignment:)` with a `nil` height — every default banner's case — is the
    /// identity; an authored `cardHeight` is what exercises the non-`nil` branch that makes
    /// `contentVerticalAlign` mean anything at all.
    @MainActor
    func testAnAuthoredHeightFixesThePopupCardsSize() throws {
        try snapshot(named: "popup_height_authored") { vm in
            vm.popupBanner = BannerResponse(
                token: "popup",
                displayType: "popup",
                cssStyles: ["cardHeight": "300px", "contentVerticalAlign": "bottom"],
                design: design(rowColor: "#3A3FE0")
            )
        } check: { host, _ in
            guard let card = host.interactiveFrames.first, host.interactiveFrames.count == 1 else {
                return XCTFail("expected exactly one popup card frame, got \(host.interactiveFrames)")
            }
            XCTAssertEqual(card.height, 300, accuracy: 0.5, "cardHeight fixes the card instead of it hugging the (much shorter) design")
        }
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
