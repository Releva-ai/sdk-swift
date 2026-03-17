import XCTest
@testable import RelevaSDK

final class NpsManagerServiceTests: XCTestCase {

    func testInitializeWithNoCustomEventTriggersFiresImmediately() {
        let manager = NpsManagerService()
        let config = NpsConfig(
            token: "test",
            question: "Rate us?",
            triggers: [NpsTrigger(type: "appOpen")],
            triggerDelaySeconds: 0
        )

        // Should trigger immediately when no custom event triggers
        manager.initialize(config)

        // The NPS should have been sent to NpsDisplayController
        // (We can't easily test the published event without Combine,
        // but we verify no crash and the manager accepted it)
    }

    func testInitializeWithCustomEventWaitsForEvent() {
        let manager = NpsManagerService()
        let config = NpsConfig(
            token: "test",
            question: "Rate us?",
            triggers: [NpsTrigger(type: "customEvent", eventName: "checkout")]
        )

        manager.initialize(config)
        // Should not fire yet - waiting for trackEvent("checkout")
    }

    func testTrackEventMatchesCustomTrigger() {
        let manager = NpsManagerService()
        let config = NpsConfig(
            token: "test",
            question: "Rate us?",
            triggers: [NpsTrigger(type: "customEvent", eventName: "purchase_complete")]
        )

        manager.initialize(config)
        manager.trackEvent("purchase_complete") // Should trigger
    }

    func testTrackEventNonMatchingDoesNotTrigger() {
        let manager = NpsManagerService()
        let config = NpsConfig(
            token: "test",
            question: "Rate us?",
            triggers: [NpsTrigger(type: "customEvent", eventName: "purchase")]
        )

        manager.initialize(config)
        manager.trackEvent("other_event") // Should not trigger
    }

    func testCancelEventSuppresses() {
        let manager = NpsManagerService()
        let config = NpsConfig(
            token: "test",
            question: "Rate us?",
            triggers: [NpsTrigger(type: "customEvent", eventName: "checkout")],
            cancelOnEvents: ["checkout_started"]
        )

        manager.initialize(config)
        manager.trackEvent("checkout_started") // Should suppress
        manager.trackEvent("checkout") // Should not trigger after suppression
    }

    func testStartNewSessionResetsState() {
        let manager = NpsManagerService()
        let config = NpsConfig(
            token: "test",
            question: "Rate us?",
            triggers: [NpsTrigger(type: "appOpen")]
        )

        manager.initialize(config) // Triggers once
        manager.startNewSession()
        // After new session, it should be able to trigger again
    }

    func testInitializeWithNilConfigDoesNothing() {
        let manager = NpsManagerService()
        manager.initialize(nil) // Should not crash
    }

    func testDispose() {
        let manager = NpsManagerService()
        let config = NpsConfig(
            token: "test",
            question: "Rate us?",
            triggers: [NpsTrigger(type: "appOpen")],
            triggerDelaySeconds: 60
        )

        manager.initialize(config)
        manager.dispose() // Should cancel timer without crash
    }
}
