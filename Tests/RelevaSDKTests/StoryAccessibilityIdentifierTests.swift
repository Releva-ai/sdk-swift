import SwiftUI
import UIKit
import XCTest
@testable import RelevaSDK

/// The accessibility identifiers device QA reads on the story viewer, the testIDs
/// sdk-react-native's StoryViewerWidget sets: `releva-story-<token>` on the viewer,
/// `releva-story-close` on the close control's tap target, `releva-story-slide-<i>` on the slide
/// surface, named by the slide on screen, and `releva-story-action` on the action button.
final class StoryAccessibilityIdentifierTests: XCTestCase {
    private static let windowSize = CGSize(width: 393, height: 852)

    override func setUp() {
        super.setUp()
        AccessibilityTree.setAutomation(enabled: true)
    }

    override func tearDown() {
        AccessibilityTree.setAutomation(enabled: false)
        super.tearDown()
    }

    // MARK: - Harness

    /// A client that cannot reach a server: the viewer reports slide views as it plays.
    @MainActor
    private func offlineClient() -> RelevaClient {
        let saved = RelevaClient.shared
        defer { RelevaClient.shared = saved }
        return RelevaClient(
            realm: "test",
            accessToken: "test-token",
            config: RelevaConfig(enableTracking: false, enablePushNotifications: false, customEndpoint: "http://127.0.0.1:9")
        )
    }

    private func slideDesign() -> [String: JSONValue] {
        [
            "body": [
                "values": ["backgroundColor": "#202020"],
                "rows": [[
                    "values": ["padding": "0px"],
                    "columns": [[
                        "values": [:],
                        "contents": [
                            ["type": "text", "values": ["text": "<p>Hello from the story</p>", "fontSize": "18px", "color": "#FFFFFF"]]
                        ]
                    ]]
                ]]
            ]
        ]
    }

    private func story(firstSlideSeconds: Int = 30) -> StoryResponse {
        StoryResponse(
            token: "story-1",
            slides: [
                StorySlideResponse(id: "s1", design: slideDesign(), durationSeconds: firstSlideSeconds, actionType: "link", actionUrl: "https://example.com", actionLabel: "Shop now"),
                StorySlideResponse(id: "s2", design: slideDesign(), durationSeconds: 30)
            ]
        )
    }

    /// Lays the viewer out in an iPhone-sized window with a status bar and a home indicator.
    @MainActor
    private func showViewer(_ story: StoryResponse, onClose: @escaping () -> Void = {}) -> UIWindow {
        let viewer = StoryViewerView(story: story, client: offlineClient(), onLinkTap: { _ in }, onClose: onClose)
        let controller = UIHostingController(rootView: viewer)
        controller.additionalSafeAreaInsets = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        let window = UIWindow(frame: CGRect(origin: .zero, size: Self.windowSize))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        drainMainQueue(turns: 6)
        window.layoutIfNeeded()
        return window
    }

    private func only(_ identifier: String, in tree: AXNode, file: StaticString = #filePath, line: UInt = #line) throws -> AXNode {
        let matches = tree.nodes(identifier)
        XCTAssertEqual(matches.count, 1, "\(identifier) on exactly one element\n\(AccessibilityTree.describe(tree))", file: file, line: line)
        return try XCTUnwrap(matches.first, "no element carries \(identifier)", file: file, line: line)
    }

    // MARK: - Tests

    @MainActor
    func testTheViewerItsControlsAndTheSlideCarryTheirIds() throws {
        let window = showViewer(story())
        defer { window.isHidden = true }
        let tree = AccessibilityTree.tree(of: window)

        let viewer = try only(StoryAccessibilityID.story("story-1"), in: tree)
        XCTAssertFalse(viewer.isElement, "a container, so the controls inside stay reachable")

        let close = try only(StoryAccessibilityID.close, in: viewer)
        XCTAssertTrue(close.isElement)
        XCTAssertEqual(close.label, "Close", "the label is unchanged")
        XCTAssertTrue(close.traits.contains(.button), "the close control keeps the button trait")
        XCTAssertEqual(close.frame.width, 28, accuracy: 0.5, "the frame is the 28 pt tap target")
        XCTAssertEqual(close.frame.height, 28, accuracy: 0.5)
        XCTAssertEqual(close.frame.maxX, Self.windowSize.width - 8, accuracy: 0.5, "8 in from the trailing edge")

        let action = try only(StoryAccessibilityID.action, in: viewer)
        XCTAssertTrue(action.isElement)
        XCTAssertEqual(action.label, "Shop now", "the label is the slide's action label")
        XCTAssertTrue(action.traits.contains(.button))
        XCTAssertEqual(action.frame.width, Self.windowSize.width - 48, accuracy: 0.5, "the button inside its 24 pt margins")

        let slide = try only(StoryAccessibilityID.slide(0), in: viewer)
        XCTAssertEqual(slide.frame.width, Self.windowSize.width, accuracy: 0.5, "the slide surface spans the width")
        XCTAssertGreaterThanOrEqual(slide.frame.minY, close.frame.maxY - 0.5, "below the progress row")
        XCTAssertLessThanOrEqual(slide.frame.maxY, action.frame.minY + 0.5, "above the action button")
        XCTAssertTrue(tree.nodes(StoryAccessibilityID.slide(1)).isEmpty, "only the slide on screen is named")
    }

    /// The slide id names the slide on screen, so it changes when the viewer advances.
    @MainActor
    func testTheSlideIdFollowsTheSlideOnScreen() throws {
        let window = showViewer(story(firstSlideSeconds: 1))
        defer { window.isHidden = true }

        waitUntil("the viewer advances to the second slide") {
            !AccessibilityTree.tree(of: window).nodes(StoryAccessibilityID.slide(1)).isEmpty
        }
        let tree = AccessibilityTree.tree(of: window)
        _ = try only(StoryAccessibilityID.slide(1), in: tree)
        XCTAssertTrue(tree.nodes(StoryAccessibilityID.slide(0)).isEmpty)
        XCTAssertTrue(tree.nodes(StoryAccessibilityID.action).isEmpty, "the second slide has no action button")
        _ = try only(StoryAccessibilityID.close, in: tree)
    }

    /// The element carrying `releva-story-close` is the control: activating it closes the viewer.
    @MainActor
    func testActivatingTheCloseIdClosesTheViewer() throws {
        final class Closed { var value = false }
        let closed = Closed()
        let window = showViewer(story()) { closed.value = true }
        defer { window.isHidden = true }

        let close = try XCTUnwrap(AccessibilityTree.object(StoryAccessibilityID.close, in: window))
        XCTAssertTrue(close.accessibilityActivate())
        drainMainQueue()
        XCTAssertTrue(closed.value)
    }
}
