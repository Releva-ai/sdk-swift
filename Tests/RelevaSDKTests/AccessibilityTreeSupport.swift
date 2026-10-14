import UIKit
import XCTest

/// One element of the accessibility tree UI automation sees, with its children.
///
/// Shared by the banner, story and NPS accessibility-identifier suites, which all assert on the
/// tree XCUITest reads.
struct AXNode {
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

/// Reads the accessibility tree. SwiftUI builds it only while accessibility is on, so a suite turns
/// on the automation mode XCUITest itself uses for each test, and turns it off afterwards.
enum AccessibilityTree {
    /// `_AXSSetAutomationEnabled`, which XCUITest calls to make an app build its accessibility tree.
    static func setAutomation(enabled: Bool) {
        guard let handle = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
              let symbol = dlsym(handle, "_AXSSetAutomationEnabled") else {
            return XCTFail("libAccessibility's _AXSSetAutomationEnabled is unavailable, so the accessibility tree cannot be read")
        }
        typealias SetEnabled = @convention(c) (Int32) -> Void
        unsafeBitCast(symbol, to: SetEnabled.self)(enabled ? 1 : 0)
    }

    static func tree(of object: NSObject) -> AXNode {
        AXNode(
            identifier: identifier(of: object),
            label: object.accessibilityLabel ?? "",
            frame: object.accessibilityFrame,
            isElement: object.isAccessibilityElement,
            traits: object.accessibilityTraits,
            children: children(of: object).map { tree(of: $0) }
        )
    }

    /// The accessibility object carrying `identifier`, for a test that has to act on it.
    static func object(_ identifier: String, in object: NSObject) -> NSObject? {
        if Self.identifier(of: object) == identifier { return object }
        for child in children(of: object) {
            if let match = Self.object(identifier, in: child) { return match }
        }
        return nil
    }

    private static func identifier(of object: NSObject) -> String {
        guard object.responds(to: NSSelectorFromString("accessibilityIdentifier")) else { return "" }
        return object.value(forKey: "accessibilityIdentifier") as? String ?? ""
    }

    private static func children(of object: NSObject) -> [NSObject] {
        let count = object.accessibilityElementCount()
        if let elements = object.accessibilityElements as? [NSObject] {
            return elements
        } else if count != NSNotFound, count > 0 {
            return (0..<count).compactMap { object.accessibilityElement(at: $0) as? NSObject }
        } else if let view = object as? UIView {
            return view.subviews
        }
        return []
    }

    static func describe(_ node: AXNode, depth: Int = 0) -> String {
        let line = "\(String(repeating: "  ", count: depth))id=\(node.identifier) label=\(node.label) frame=\(node.frame)"
        return ([line] + node.children.map { describe($0, depth: depth + 1) }).joined(separator: "\n")
    }
}

extension XCTestCase {
    /// Fails unless `frame` is `expected` to within half a point on every edge.
    func assertFrame(_ frame: CGRect, _ expected: CGRect, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let matches = abs(frame.minX - expected.minX) <= 0.5 && abs(frame.minY - expected.minY) <= 0.5
            && abs(frame.width - expected.width) <= 0.5 && abs(frame.height - expected.height) <= 0.5
        XCTAssertTrue(matches, "\(message): got \(frame), want \(expected)", file: file, line: line)
    }
}
