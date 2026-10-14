import SwiftUI
import UIKit
import XCTest
@testable import RelevaSDK

/// The accessibility identifiers device QA reads on the NPS sheet, the testIDs
/// sdk-react-native's NpsOverlayWidget sets: `releva-nps-<token>` on the sheet,
/// `releva-nps-score-<n>` on each score button, `releva-nps-skip`, and on the follow-up step
/// `releva-nps-comment` and `releva-nps-submit`.
final class NpsAccessibilityIdentifierTests: XCTestCase {
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

    private func survey(skipLabel: String? = "Not now") -> NpsConfig {
        NpsConfig(
            token: "nps-1",
            question: "How likely are you to recommend us?",
            followUp: NpsFollowUp(promoter: "What did you like?", passive: "What could be better?", detractor: "What went wrong?"),
            submitLabel: "Send",
            skipLabel: skipLabel
        )
    }

    @MainActor
    private func showSurvey(_ config: NpsConfig) -> UIWindow {
        let submit: (String, Int, String?) -> Void = { _, _, _ in }
        let close: () -> Void = {}
        let view = NpsSurveyView(config: IdentifiableNpsConfig(config: config), onSubmit: submit, onSkip: nil, onClose: close)
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(origin: .zero, size: Self.windowSize))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        drainMainQueue(turns: 4)
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
    func testTheSheetTheScoresAndSkipCarryTheirIds() throws {
        let window = showSurvey(survey())
        defer { window.isHidden = true }
        let tree = AccessibilityTree.tree(of: window)

        let sheet = try only(NpsAccessibilityID.sheet("nps-1"), in: tree)
        XCTAssertFalse(sheet.isElement, "a container, so the controls inside stay reachable")

        var frames: [CGRect] = []
        for score in 0...10 {
            let button = try only(NpsAccessibilityID.score(score), in: sheet)
            XCTAssertTrue(button.isElement)
            XCTAssertEqual(button.label, "\(score)", "the label is the score")
            XCTAssertTrue(button.traits.contains(.button), "a score keeps the button trait")
            frames.append(button.frame)
        }
        for frame in frames {
            XCTAssertEqual(frame.width, frames[0].width, accuracy: 0.5, "every score button is the same size")
            XCTAssertEqual(frame.height, frames[0].height, accuracy: 0.5)
            XCTAssertEqual(frame.minY, frames[0].minY, accuracy: 0.5, "one row")
        }
        XCTAssertGreaterThan(frames[0].height, 0)
        XCTAssertEqual(frames.map(\.minX), frames.map(\.minX).sorted(), "0 to 10, left to right")
        XCTAssertTrue(zip(frames, frames.dropFirst()).allSatisfy { $0.maxX <= $1.minX + 0.5 }, "no two buttons overlap")

        let skip = try only(NpsAccessibilityID.skip, in: sheet)
        XCTAssertTrue(skip.isElement)
        XCTAssertEqual(skip.label, "Not now")
        XCTAssertTrue(skip.traits.contains(.button))

        XCTAssertTrue(tree.nodes(NpsAccessibilityID.comment).isEmpty, "the comment input belongs to the follow-up step")
        XCTAssertTrue(tree.nodes(NpsAccessibilityID.submit).isEmpty)
    }

    @MainActor
    func testWithoutASkipLabelThereIsNoSkipId() throws {
        let window = showSurvey(survey(skipLabel: nil))
        defer { window.isHidden = true }
        let tree = AccessibilityTree.tree(of: window)
        _ = try only(NpsAccessibilityID.sheet("nps-1"), in: tree)
        XCTAssertTrue(tree.nodes(NpsAccessibilityID.skip).isEmpty)
    }

    /// Activating a score's element selects that score: a promoter score opens the follow-up step,
    /// whose input and submit button carry their ids inside the same sheet.
    @MainActor
    func testTheFollowUpStepsCommentAndSubmitCarryTheirIds() throws {
        let window = showSurvey(survey())
        defer { window.isHidden = true }

        let nine = try XCTUnwrap(AccessibilityTree.object(NpsAccessibilityID.score(9), in: window))
        XCTAssertTrue(nine.accessibilityActivate())
        drainMainQueue(turns: 4)
        window.layoutIfNeeded()
        waitUntil("the follow-up step is shown") {
            !AccessibilityTree.tree(of: window).nodes(NpsAccessibilityID.submit).isEmpty
        }

        let tree = AccessibilityTree.tree(of: window)
        let sheet = try only(NpsAccessibilityID.sheet("nps-1"), in: tree)
        // The id is on a container around the text view, framed by the text view itself.
        let comment = try only(NpsAccessibilityID.comment, in: sheet)
        XCTAssertFalse(comment.isElement, "a container, so the text view inside stays reachable")
        XCTAssertEqual(comment.children.count, 1, "it holds the text view and nothing else")
        XCTAssertEqual(comment.frame.width, Self.windowSize.width - 56, accuracy: 0.5, "inside the sheet's 20 pt margins and the editor's 8 pt padding")
        XCTAssertEqual(comment.frame.height, 120, accuracy: 0.5, "the editor's height")
        let submit = try only(NpsAccessibilityID.submit, in: sheet)
        XCTAssertTrue(submit.isElement)
        XCTAssertEqual(submit.label, "Send")
        XCTAssertTrue(submit.traits.contains(.button))
        XCTAssertTrue(tree.nodes(NpsAccessibilityID.score(9)).isEmpty, "the scores belong to the first step")
    }
}
