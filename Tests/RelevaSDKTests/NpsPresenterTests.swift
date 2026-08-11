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
        // `close(animated:)` either drops `surveyController` (the sheet was already gone, or the
        // dismissal took effect at once) or keeps it until the dismiss completion runs, so that a
        // sheet UIKit declined to dismiss is not orphaned beyond reach — see `NpsPresenter.close`.
        // Which branch runs depends on a transition this test host never finishes (no
        // `UIWindowScene`; see `PresentationTestSupport.makeVisibleWindow`), and either is
        // correct. Asserting on one of them would pin the harness rather than the presenter; what
        // holds on both is that nothing *else* took the property over.
        XCTAssertTrue(
            presenter.surveyController == nil || presenter.surveyController === firstSurvey,
            "a stopped presenter must not leave a different survey behind"
        )

        NpsDisplayController.shared.showNps(NpsConfig(token: "nps-2", question: "And now?"))
        drainMainQueue()

        // Stopped: the cancellable is torn down, so `present` never runs for the later survey at
        // all and the property is left exactly as the assertion above found it. A subscription
        // that outlived `stop()` would show up here as a third value — neither `nil` nor the
        // first survey — though only on the branch where `close` had already released the
        // reference, since `present`'s own guard refuses a second sheet while the first still
        // reports a `presentingViewController`.
        XCTAssertTrue(
            presenter.surveyController == nil || presenter.surveyController === firstSurvey,
            "a stopped presenter must not show a survey"
        )
    }
}
