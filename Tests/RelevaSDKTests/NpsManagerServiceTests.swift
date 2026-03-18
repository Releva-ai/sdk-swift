import XCTest
import Combine
@testable import RelevaSDK

final class NpsManagerServiceTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func testInitializeWithNoCustomEventTriggersFiresImmediately() {
        let manager = NpsManagerService()
        let config = NpsConfig(
            token: "test",
            question: "Rate us?",
            triggers: [NpsTrigger(type: "appOpen")],
            triggerDelaySeconds: 0
        )

        let expectation = expectation(description: "NPS published")
        NpsDisplayController.shared.npsPublisher
            .sink { received in
                XCTAssertEqual(received.token, "test")
                expectation.fulfill()
            }
            .store(in: &cancellables)

        manager.initialize(config)

        waitForExpectations(timeout: 2)
    }

    func testInitializeWithCustomEventWaitsForEvent() {
        let manager = NpsManagerService()
        let config = NpsConfig(
            token: "test",
            question: "Rate us?",
            triggers: [NpsTrigger(type: "customEvent", eventName: "checkout")]
        )

        let expectation = expectation(description: "NPS should not fire")
        expectation.isInverted = true
        NpsDisplayController.shared.npsPublisher
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        manager.initialize(config)

        waitForExpectations(timeout: 0.5)
    }

    func testTrackEventMatchesCustomTrigger() {
        let manager = NpsManagerService()
        let config = NpsConfig(
            token: "test-purchase",
            question: "Rate us?",
            triggers: [NpsTrigger(type: "customEvent", eventName: "purchase_complete")]
        )

        let expectation = expectation(description: "NPS published after matching event")
        NpsDisplayController.shared.npsPublisher
            .sink { received in
                XCTAssertEqual(received.token, "test-purchase")
                expectation.fulfill()
            }
            .store(in: &cancellables)

        manager.initialize(config)
        manager.trackEvent("purchase_complete")

        waitForExpectations(timeout: 2)
    }

    func testTrackEventNonMatchingDoesNotTrigger() {
        let manager = NpsManagerService()
        let config = NpsConfig(
            token: "test",
            question: "Rate us?",
            triggers: [NpsTrigger(type: "customEvent", eventName: "purchase")]
        )

        let expectation = expectation(description: "NPS should not fire")
        expectation.isInverted = true
        NpsDisplayController.shared.npsPublisher
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        manager.initialize(config)
        manager.trackEvent("other_event")

        waitForExpectations(timeout: 0.5)
    }

    func testCancelEventSuppresses() {
        let manager = NpsManagerService()
        let config = NpsConfig(
            token: "test",
            question: "Rate us?",
            triggers: [NpsTrigger(type: "customEvent", eventName: "checkout")],
            cancelOnEvents: ["checkout_started"]
        )

        let expectation = expectation(description: "NPS should not fire after cancel")
        expectation.isInverted = true
        NpsDisplayController.shared.npsPublisher
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        manager.initialize(config)
        manager.trackEvent("checkout_started") // Should suppress
        manager.trackEvent("checkout") // Should not trigger after suppression

        waitForExpectations(timeout: 0.5)
    }

    func testStartNewSessionResetsState() {
        let manager = NpsManagerService()
        let config = NpsConfig(
            token: "test",
            question: "Rate us?",
            triggers: [NpsTrigger(type: "appOpen")],
            triggerDelaySeconds: 0
        )

        // First trigger
        let firstExpectation = expectation(description: "First NPS")
        NpsDisplayController.shared.npsPublisher
            .first()
            .sink { _ in firstExpectation.fulfill() }
            .store(in: &cancellables)

        manager.initialize(config)
        waitForExpectations(timeout: 2)

        // Reset and re-trigger
        manager.startNewSession()

        let secondExpectation = expectation(description: "Second NPS after session reset")
        NpsDisplayController.shared.npsPublisher
            .first()
            .sink { _ in secondExpectation.fulfill() }
            .store(in: &cancellables)

        manager.initialize(config)
        waitForExpectations(timeout: 2)
    }

    func testInitializeWithNilConfigDoesNothing() {
        let manager = NpsManagerService()

        let expectation = expectation(description: "NPS should not fire")
        expectation.isInverted = true
        NpsDisplayController.shared.npsPublisher
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        manager.initialize(nil)

        waitForExpectations(timeout: 0.5)
    }

    func testDispose() {
        let manager = NpsManagerService()
        let config = NpsConfig(
            token: "test",
            question: "Rate us?",
            triggers: [NpsTrigger(type: "appOpen")],
            triggerDelaySeconds: 60
        )

        let expectation = expectation(description: "NPS should not fire after dispose")
        expectation.isInverted = true
        NpsDisplayController.shared.npsPublisher
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        manager.initialize(config)
        manager.dispose()

        waitForExpectations(timeout: 0.5)
    }
}
