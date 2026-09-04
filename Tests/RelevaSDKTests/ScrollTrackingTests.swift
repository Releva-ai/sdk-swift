import SwiftUI
import UIKit
import XCTest
@testable import RelevaSDK

/// `relevaScrollTracking` must turn a real scroll into 0–100 reports: the device run 34 log
/// showed scroll-triggered banners returned by the backend but no scroll ever reported.
final class ScrollTrackingTests: XCTestCase {
    private struct Host: View {
        let onChange: (Int) -> Void
        var body: some View {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(0..<40, id: \.self) { i in
                        Text("Row \(i)").frame(height: 50)
                    }
                }
                .relevaScrollTracking(onChange: onChange)
            }
        }
    }

    @MainActor
    func testScrollingReportsPercentage() {
        var reported: [Int] = []
        let controller = UIHostingController(rootView: Host { reported.append($0) })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        window.layoutIfNeeded()
        drainMainQueue(turns: 4)

        guard let scrollView = findScrollView(in: controller.view) else {
            return XCTFail("no UIScrollView under the hosting view")
        }
        // 40 rows × 50 pt = 2000 pt of content in an 852 pt viewport.
        let maxOffset = scrollView.contentSize.height - scrollView.bounds.height
        XCTAssertGreaterThan(maxOffset, 1000, "content taller than the viewport")

        scrollView.setContentOffset(CGPoint(x: 0, y: maxOffset / 2), animated: false)
        scrollView.layoutIfNeeded()
        drainMainQueue(turns: 4)
        XCTAssertEqual(reported.last ?? -1, 50, accuracy: 2, "half-way scroll reports ~50 %")

        scrollView.setContentOffset(CGPoint(x: 0, y: maxOffset), animated: false)
        scrollView.layoutIfNeeded()
        drainMainQueue(turns: 4)
        XCTAssertEqual(reported.last ?? -1, 100, accuracy: 2, "bottom reports 100 %")
        window.isHidden = true
    }

    private func findScrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        for sub in view.subviews { if let found = findScrollView(in: sub) { return found } }
        return nil
    }
}
