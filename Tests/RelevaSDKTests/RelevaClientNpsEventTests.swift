import Combine
import XCTest
@testable import RelevaSDK

/// The admin's Custom Event trigger and cancel list offer the event actions the app tracks, so
/// an action sent through `trackCustomEvent` must also drive the survey. Device run 50: a colour
/// pick tracked as `selectedColor` never opened a survey triggered on `selectedColor`; only the
/// explicit `trackEvent` call did.
@MainActor
final class RelevaClientNpsEventTests: XCTestCase {
    private var cancellables = Set<AnyCancellable>()
    private var savedShared: RelevaClient?

    override func setUp() {
        super.setUp()
        savedShared = RelevaClient.shared
        RelevaClient.shared = nil
    }

    override func tearDown() {
        cancellables.removeAll()
        RelevaClient.shared = savedShared
        super.tearDown()
    }

    private func makeClient() -> (RelevaClient, NpsManagerService) {
        // Tracking off: `push` returns an empty response without network I/O, so the only
        // observable effect of `trackCustomEvent` is what it hands to the NPS manager.
        let client = RelevaClient(
            realm: "test",
            accessToken: "test-token",
            config: RelevaConfig(enableTracking: false, enablePushNotifications: false)
        )
        let manager = NpsManagerService()
        client.npsManager = manager
        return (client, manager)
    }

    private func config(cancelOn: [String] = []) -> NpsConfig {
        NpsConfig(
            token: "nps-custom",
            question: "Rate us?",
            triggers: [NpsTrigger(type: "customEvent", eventName: "selectedColor")],
            triggerDelaySeconds: 0,
            cancelOnEvents: cancelOn
        )
    }

    func testATrackedCustomEventFiresTheSurveyTrigger() async throws {
        let (client, manager) = makeClient()
        manager.initialize(config())

        let shown = expectation(description: "survey published")
        NpsDisplayController.shared.npsPublisher
            .sink { published in
                if published.token == "nps-custom" { shown.fulfill() }
            }
            .store(in: &cancellables)

        _ = try await client.trackCustomEvent(CustomEvent(action: "selectedColor"))

        await fulfillment(of: [shown], timeout: 2)
    }

    func testATrackedCancelEventStopsAPendingSurvey() async throws {
        let (client, manager) = makeClient()
        manager.initialize(config(cancelOn: ["cartAdd"]))

        let shown = expectation(description: "survey published")
        shown.isInverted = true
        NpsDisplayController.shared.npsPublisher
            .sink { published in
                if published.token == "nps-custom" { shown.fulfill() }
            }
            .store(in: &cancellables)

        // The cancel event arrives first: the trigger that follows must be ignored for the
        // session, as it is for an explicit `trackEvent("cartAdd")`.
        _ = try await client.trackCustomEvent(CustomEvent(action: "cartAdd"))
        _ = try await client.trackCustomEvent(CustomEvent(action: "selectedColor"))

        await fulfillment(of: [shown], timeout: 1)
    }
}
