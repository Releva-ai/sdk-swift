import UIKit
import XCTest
@testable import RelevaSDK

/// Stands in for `RelevaClient`, which builds its own `NetworkService` over `URLSession.shared`
/// and has no injection point — handing a real one to a view model or presenter would make a
/// test perform network I/O.
///
/// Shared by `BannerPresenterTests` and `BannerDisplayViewModelTests`, which were previously two
/// byte-for-byte copies of the same spy: both suites assert on the `"token:action"` format below,
/// so one copy keeps that format from drifting between them.
@MainActor
final class BannerTrackerSpy: BannerTracker {
    var impressions: [String] = []
    /// `token:action` pairs in call order, flattened to strings so a whole expected sequence
    /// can be compared in one assertion.
    var actions: [String] = []

    func bannerImpression(_ banner: BannerResponse) {
        impressions.append(banner.token)
    }

    func bannerAction(_ banner: BannerResponse, action: String) {
        actions.append("\(banner.token):\(action)")
    }
}

/// Shared by `BannerPresenterTests` and `NpsPresenterTests`: both drive a presenter through the
/// display-controller singleton it subscribes to, then look at what the host has on screen.
extension XCTestCase {

    /// A window holding `rootViewController`, made visible.
    ///
    /// Visible because a view controller in no on-screen hierarchy cannot reliably present.
    ///
    /// **What this window can and cannot do**, measured on CI rather than assumed — two runs on
    /// this branch established it. xcodebuild's generated SPM test host has no scene manifest, so
    /// `UIApplication.shared.connectedScenes` is empty and the window gets no `windowScene`.
    /// `present` still does its bookkeeping synchronously in that state — which controller is
    /// presented, its modal style, and the whole presentation chain are all observable — but the
    /// *transitions never complete*: the presented controller stays `isBeingPresented`, and UIKit
    /// then refuses both a `dismiss` of it and a `present` from it. So a test here may assert on
    /// what a presenter put on screen and what it reported, and must not wait for a presentation
    /// or a dismissal to have *finished*. Covering the latter needs a test host app owning a real
    /// `UIWindowScene`, which this package does not have.
    ///
    /// The caller must keep the returned window alive for the length of the test and hide it
    /// afterwards; a key window left behind is the next test's root.
    @MainActor
    func makeVisibleWindow(rootViewController: UIViewController) -> UIWindow {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        window.rootViewController = rootViewController
        window.makeKeyAndVisible()
        return window
    }

    /// Returns once the main-queue work the preceding calls set in motion has run.
    ///
    /// A display event reaches a presenter along a fixed path of `receive(on: DispatchQueue.main)`
    /// hops — one for the view model's subscription, one for the presenter's own. Each marker
    /// below is enqueued behind the work already on the queue, and the queue is FIFO, so once
    /// the last marker lands every stage has run. That makes the "must not happen" assertions in
    /// these tests exact, rather than a race against a sub-second inverted expectation that only
    /// gets less reliable the slower the runner is.
    ///
    /// The default is one turn more than the longest path either presenter has, because a marker
    /// costs microseconds.
    @MainActor
    func drainMainQueue(turns: Int = 3) {
        for turn in 0..<turns {
            let landed = expectation(description: "main queue turn \(turn)")
            DispatchQueue.main.async { landed.fulfill() }
            wait(for: [landed], timeout: 2)
        }
    }

    /// Returns as soon as `condition` holds, failing the test if it has not within `timeout`.
    ///
    /// For the UIKit side of a presentation, which no marker can be queued behind the way
    /// `drainMainQueue` queues behind a `DispatchQueue.main.async`. Pumping the run loop returns
    /// the moment the condition holds instead of sleeping out a budget. Only ever used for
    /// conditions that a presentation *reaches* — never for one having finished, which cannot
    /// happen here; see `makeVisibleWindow`.
    @MainActor
    func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: () -> Bool
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(condition(), "timed out waiting until \(description)", file: file, line: line)
    }
}
