import SwiftUI
import UIKit
import XCTest
@testable import RelevaSDK

/// `NpsPresenter` hosts the same `NpsSurveyView` the SwiftUI modifier shows in a `.sheet`, and
/// reporting the response is the app's job on both paths, so what is left to cover is the
/// presentation: which surveys reach the screen, and that a stopped presenter leaves nothing
/// behind. Driven through `NpsDisplayController.shared`, the singleton `NpsManagerService`
/// publishes to in production.
///
/// As in `BannerPresenterTests`, the assertions are on what the presenter did, not on UIKit
/// having finished a transition — see `PresentationTestSupport.makeVisibleWindow`.
final class NpsPresenterTests: XCTestCase {
    @MainActor
    func testSurveyIsPresentedAsASheet() {
        let host = UIViewController()
        let window = makeVisibleWindow(rootViewController: host)
        let presenter = NpsPresenter(host: host) { _, _, _ in }
        defer {
            presenter.stop()
            window.isHidden = true
        }

        presenter.start()
        NpsDisplayController.shared.showNps(NpsConfig(token: "nps-1", question: "Rate us?"))
        drainMainQueue()

        waitUntil("the survey is presented") { host.presentedViewController != nil }
        XCTAssertTrue(
            host.presentedViewController is UIHostingController<NpsSurveyView>,
            "expected the hosted survey, got \(String(describing: host.presentedViewController))"
        )
        XCTAssertEqual(host.presentedViewController?.modalPresentationStyle, .pageSheet)
    }

    @MainActor
    func testSecondSurveyIsIgnoredWhileOneIsOnScreen() {
        let host = UIViewController()
        let window = makeVisibleWindow(rootViewController: host)
        let presenter = NpsPresenter(host: host) { _, _, _ in }
        defer {
            presenter.stop()
            window.isHidden = true
        }

        presenter.start()
        NpsDisplayController.shared.showNps(NpsConfig(token: "nps-1", question: "Rate us?"))
        drainMainQueue()
        waitUntil("the survey is presented") { host.presentedViewController != nil }
        let firstSurvey = host.presentedViewController

        NpsDisplayController.shared.showNps(NpsConfig(token: "nps-2", question: "And now?"))
        drainMainQueue()

        // Stacking a second survey on the first would bury it, and neither is answerable.
        XCTAssertTrue(host.presentedViewController === firstSurvey)
        XCTAssertNil(firstSurvey?.presentedViewController)
    }

    @MainActor
    func testStopTakesTheSurveyDownAndIgnoresLaterOnes() {
        let host = UIViewController()
        let window = makeVisibleWindow(rootViewController: host)
        let presenter = NpsPresenter(host: host) { _, _, _ in }
        defer {
            presenter.stop()
            window.isHidden = true
        }

        presenter.start()
        NpsDisplayController.shared.showNps(NpsConfig(token: "nps-1", question: "Rate us?"))
        drainMainQueue()
        waitUntil("the survey is presented") { host.presentedViewController != nil }

        let firstSurvey = presenter.surveyController
        presenter.stop()
        // `close(animated:)` only clears `surveyController` from the dismiss completion, so a
        // sheet UIKit declines to dismiss (still `isBeingPresented`) is not orphaned — see
        // `NpsPresenter.close`. That completion needs the transition to actually finish, which
        // this test host's windows (no `UIWindowScene`) never do, so it stays set here rather
        // than going to `nil`; see `PresentationTestSupport.makeVisibleWindow`.
        XCTAssertNotNil(
            presenter.surveyController,
            "the presenter must not let go of the survey until UIKit confirms the dismissal"
        )

        NpsDisplayController.shared.showNps(NpsConfig(token: "nps-2", question: "And now?"))
        drainMainQueue()

        // Stopped: the cancellable is torn down, so `present` never runs for the later survey at
        // all — `surveyController` is exactly what it was left holding above, not a new sheet.
        XCTAssertTrue(presenter.surveyController === firstSurvey, "a stopped presenter must not show a survey")
    }
}
