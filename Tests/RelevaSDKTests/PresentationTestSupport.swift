import UIKit
import XCTest

/// Shared by `BannerPresenterTests` and `NpsPresenterTests`: both drive a presenter through the
/// display-controller singleton it subscribes to, then look at what the host has on screen.
extension XCTestCase {

    /// A window holding `rootViewController`, made visible.
    ///
    /// Visible because a view controller in no on-screen hierarchy cannot reliably present. The
    /// runner has a scene, and a window belonging to none of them is not part of a hierarchy
    /// that is on screen, so the window is attached to it.
    ///
    /// The caller must keep the returned window alive for the length of the test and hide it
    /// afterwards; a key window left behind is the next test's root.
    @MainActor
    func makeVisibleWindow(rootViewController: UIViewController) -> UIWindow {
        let window = UIWindow(frame: UIScreen.main.bounds)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            window.windowScene = scene
        }
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
    /// Presentation and dismissal are animated, so they finish over several turns of the run loop
    /// rather than on the one that asked for them, and no marker can be queued behind an
    /// animation the way `drainMainQueue` queues behind a `DispatchQueue.main.async`. Pumping the
    /// run loop returns the moment the condition holds instead of sleeping out a budget.
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
