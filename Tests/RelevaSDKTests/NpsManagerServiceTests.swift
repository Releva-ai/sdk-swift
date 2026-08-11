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
    /// second each.
    ///
    /// The "same delay" precondition above is load-bearing, so `delaySeconds` is a
    /// parameter rather than a hardcoded `0`: callers must pass the config's
    /// `triggerDelaySeconds` explicitly, so a future test with a nonzero delay can't
    /// silently inherit a marker that fires early and passes vacuously. `Timer` clamps
    /// a non-positive interval to `0.0001`s, so a `0` marker still schedules a real
    /// timer with its own later `now` — the ordering comes from run-loop fire-date
    /// comparison, not from insertion order.
    ///
    /// This cannot outrun a trigger whose own delay is still counting down
    /// (`testDispose`'s 60s case, which deliberately does not pass 60 here — see its
    /// call site).
    private func waitForPublishPath(of manager: NpsManagerService, delaySeconds: Int) {
        let landed = expectation(description: "the publish path drained")
        manager.drainPendingWork {
            DispatchQueue.main.async {
                _ = Timer.scheduledTimer(withTimeInterval: TimeInterval(delaySeconds), repeats: false) { _ in
                    manager.drainPendingWork {
                        DispatchQueue.main.async { landed.fulfill() }
                    }
                }
            }
        }
        // `+ 5` is slack for the queue/main hops on top of however long the marker's
        // own timer was asked to sleep for — matching `delaySeconds` here, not a fixed
        // budget, so a larger delay can't schedule a marker the wait can't reach.
        wait(for: [landed], timeout: TimeInterval(delaySeconds) + 5)
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
        waitForPublishPath(of: manager, delaySeconds: config.triggerDelaySeconds)

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
        waitForPublishPath(of: manager, delaySeconds: config.triggerDelaySeconds)

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
        waitForPublishPath(of: manager, delaySeconds: config.triggerDelaySeconds)

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
        // No config at all, so there is no `triggerDelaySeconds` to match — a `0`
        // marker delay is correct here, not a case the "same delay" precondition
        // applies to.
        waitForPublishPath(of: manager, delaySeconds: 0)

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
        // Deliberately delaySeconds: 0, not config.triggerDelaySeconds (60) — passing 60
        // would make this test actually wait 60 real seconds, which the "same delay"
        // precondition doesn't buy anything for here. Unlike the "must not fire" tests
        // above, this assertion never races a fire date against the survey's timer: it
        // relies on `dispose()`'s `queue.async` being enqueued strictly after
        // `initialize`'s (FIFO), so its `invalidate()` on the main queue is guaranteed to
        // run before the 60 s timer could ever fire, however long that timer's delay is.
        // Draining the queue and main hops both calls made is enough to observe that.
        // The 60 s timer's actual fire is out of reach of any wait here, as it was of the
        // 0.5 s inverted expectation this replaces.
        waitForPublishPath(of: manager, delaySeconds: 0)

        XCTAssertTrue(receivedTokens.isEmpty, "a disposed manager must not show its delayed survey")
    }
}
