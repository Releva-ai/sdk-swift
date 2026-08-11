import XCTest
import Combine
@testable import RelevaSDK

final class NpsManagerServiceTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    /// Returns once anything the preceding calls set in motion has run to completion.
    ///
    /// A survey reaches `NpsDisplayController` along a fixed path: the manager's serial
    /// `queue`, then the main queue, then the `triggerDelaySeconds` timer, then that queue
    /// and the main queue again. Sending a marker down the same path afterwards puts it
    /// behind every stage — each one is FIFO, and the marker's timer is scheduled later
    /// than, so fires after, any timer the call under test scheduled with the same delay.
    /// When the marker lands, a survey that was going to be published already has been.
    ///
    /// This is what the "must not fire" tests below end with instead of a sub-second
    /// inverted expectation: an inverted wait only gets less reliable as the runner gets
    /// slower, whereas this gets no weaker, and it costs milliseconds rather than half a
    /// second each. What it cannot outrun is a trigger whose own delay is still counting
    /// down (`testDispose`) — neither could the wait it replaces.
    private func waitForPublishPath(of manager: NpsManagerService) {
        let landed = expectation(description: "the publish path drained")
        manager.queue.async {
            DispatchQueue.main.async {
                _ = Timer.scheduledTimer(withTimeInterval: 0, repeats: false) { _ in
                    manager.queue.async {
                        DispatchQueue.main.async { landed.fulfill() }
                    }
                }
            }
        }
        wait(for: [landed], timeout: 5)
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

        var receivedTokens: [String] = []
        NpsDisplayController.shared.npsPublisher
            .sink { receivedTokens.append($0.token) }
            .store(in: &cancellables)

        manager.initialize(config)
        waitForPublishPath(of: manager)

        XCTAssertTrue(receivedTokens.isEmpty, "a customEvent trigger must wait for its event")
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

        var receivedTokens: [String] = []
        NpsDisplayController.shared.npsPublisher
            .sink { receivedTokens.append($0.token) }
            .store(in: &cancellables)

        manager.initialize(config)
        manager.trackEvent("other_event")
        waitForPublishPath(of: manager)

        XCTAssertTrue(receivedTokens.isEmpty, "an unrelated event must not fire the survey")
    }

    func testCancelEventSuppresses() {
        let manager = NpsManagerService()
        let config = NpsConfig(
            token: "test",
            question: "Rate us?",
            triggers: [NpsTrigger(type: "customEvent", eventName: "checkout")],
            cancelOnEvents: ["checkout_started"]
        )

        var receivedTokens: [String] = []
        NpsDisplayController.shared.npsPublisher
            .sink { receivedTokens.append($0.token) }
            .store(in: &cancellables)

        manager.initialize(config)
        manager.trackEvent("checkout_started") // Should suppress
        manager.trackEvent("checkout") // Should not trigger after suppression
        waitForPublishPath(of: manager)

        XCTAssertTrue(receivedTokens.isEmpty, "the trigger event must not fire a suppressed survey")
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

        var receivedTokens: [String] = []
        NpsDisplayController.shared.npsPublisher
            .sink { receivedTokens.append($0.token) }
            .store(in: &cancellables)

        manager.initialize(nil)
        waitForPublishPath(of: manager)

        XCTAssertTrue(receivedTokens.isEmpty, "no config means nothing to show")
    }

    func testDispose() {
        let manager = NpsManagerService()
        let config = NpsConfig(
            token: "test",
            question: "Rate us?",
            triggers: [NpsTrigger(type: "appOpen")],
            triggerDelaySeconds: 60
        )

        var receivedTokens: [String] = []
        NpsDisplayController.shared.npsPublisher
            .sink { receivedTokens.append($0.token) }
            .store(in: &cancellables)

        manager.initialize(config)
        manager.dispose()
        // Drains the queue and main hops both calls made; the 60 s trigger itself is out of
        // reach of any wait, as it was of the 0.5 s inverted expectation this replaces.
        waitForPublishPath(of: manager)

        XCTAssertTrue(receivedTokens.isEmpty, "a disposed manager must not show its delayed survey")
    }
}
