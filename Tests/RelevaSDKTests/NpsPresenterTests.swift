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

        presenter.stop()
        XCTAssertNil(
            presenter.surveyController,
            "stop() must let go of the survey it asked UIKit to take down"
        )

        NpsDisplayController.shared.showNps(NpsConfig(token: "nps-2", question: "And now?"))
        drainMainQueue()

        XCTAssertNil(presenter.surveyController, "a stopped presenter must not show a survey")
    }
}
