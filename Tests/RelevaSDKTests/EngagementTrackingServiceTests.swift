import XCTest
@testable import RelevaSDK

/// `EngagementTrackingService`'s two `async` reads (`getStatistics()`,
/// `getPendingEventCount()`) and the queue-confined state they report on: what
/// `trackEvent(_:)` does to the pending queue, and that both continuations resolve
/// under concurrent access rather than hanging.
///
/// Every test gets its own `UserDefaults` suite, matching `StorageServiceTests`, so
/// none of them shares `pendingEngagementEvents` with another test or a real run.
final class EngagementTrackingServiceTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var storage: StorageService!
    private var session: URLSession!
    private var networkService: NetworkService!
    private var service: EngagementTrackingService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "EngagementTrackingServiceTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        storage = StorageService(userDefaults: defaults)
        session = StubURLProtocol.makeSession()
        networkService = NetworkService(realm: "us", accessToken: "test-token", config: .full(), session: session)
        service = EngagementTrackingService(storage: storage, networkService: networkService, config: .full())
    }

    override func tearDown() {
        session?.invalidateAndCancel()
        session = nil
        networkService = nil
        service = nil
        if let suiteName = suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        storage = nil
        defaults = nil
        suiteName = nil
        StubURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Helpers

    /// A `.delivered` event never hits `shouldSendImmediately`, and one event is far
    /// under the default `engagementBatchSize` of 10 — so `trackEvent` queues it and
    /// nothing drains the queue out from under a test asserting on its count.
    private func makeQueueableEvent(notificationId: String = UUID().uuidString) -> EngagementEvent {
        EngagementEvent(type: .delivered, callbackUrl: "https://example.com/cb", notificationId: notificationId)
    }

    // MARK: - getPendingEventCount

    func testGetPendingEventCountStartsAtZero() async {
        let count = await service.getPendingEventCount()
        XCTAssertEqual(count, 0)
    }

    func testGetPendingEventCountReflectsTrackedEvents() async {
        service.trackEvent(makeQueueableEvent())
        service.trackEvent(makeQueueableEvent())

        // `trackEvent` and `getPendingEventCount` both hop onto the same serial queue;
        // the two `trackEvent` calls above are already enqueued ahead of this one, so
        // the count below is not a race with them.
        let count = await service.getPendingEventCount()

        XCTAssertEqual(count, 2)
    }

    func testInvalidEventIsNotQueued() async {
        // Empty callbackUrl fails `EngagementEvent.validate()`, so `trackEvent` drops
        // it before it ever reaches `pendingEvents`.
        service.trackEvent(EngagementEvent(type: .delivered, callbackUrl: ""))

        let count = await service.getPendingEventCount()

        XCTAssertEqual(count, 0)
    }

    func testClearPendingEventsEmptiesTheQueue() async {
        service.trackEvent(makeQueueableEvent())
        service.trackEvent(makeQueueableEvent())
        service.clearPendingEvents()

        let count = await service.getPendingEventCount()

        XCTAssertEqual(count, 0)
    }

    // MARK: - getStatistics

    func testGetStatisticsReportsConfigAndQueueState() async {
        service.trackEvent(makeQueueableEvent())

        let stats = await service.getStatistics()

        XCTAssertEqual(stats.pendingCount, 1)
        XCTAssertFalse(stats.isTracking, "startTracking() was never called")
        XCTAssertFalse(stats.isSending, "nothing triggers an immediate send for a .delivered event")
        XCTAssertEqual(stats.batchSize, RelevaConfig.full().engagementBatchSize)
        XCTAssertEqual(stats.batchInterval, RelevaConfig.full().engagementBatchInterval)
        XCTAssertEqual(stats.eventTypes, ["delivered": 1])
    }

    func testGetStatisticsGroupsEventTypesSeparately() async {
        service.trackEvent(makeQueueableEvent())
        service.trackEvent(makeQueueableEvent())
        service.trackEvent(EngagementEvent(type: .opened, callbackUrl: "https://example.com/cb"))

        let stats = await service.getStatistics()

        XCTAssertEqual(stats.pendingCount, 3)
        XCTAssertEqual(stats.eventTypes, ["delivered": 2, "opened": 1])
    }

    // `@MainActor` is not about the assertion — `batchTimer` is assigned synchronously by
    // `startTracking()`, so `isTracking` reads `true` whatever thread ran it. It is about
    // the `Timer` itself: scheduled on a cooperative-pool thread it is attached to a run
    // loop nothing ever runs, so it could never fire, and `stopTracking()` after the
    // `await` can land on a different thread than the one that installed it, which is not
    // where `invalidate()` is allowed to be called. Pinning the test to the main actor
    // keeps both on the main run loop, which is where a host app calls this API from.
    @MainActor
    func testStartTrackingIsReflectedInIsTracking() async {
        service.startTracking()
        defer { service.stopTracking() }

        let stats = await service.getStatistics()

        XCTAssertTrue(stats.isTracking)
    }

    func testEngagementStatisticsEqualityComparesAllFields() {
        let base = EngagementStatistics(
            pendingCount: 1,
            isTracking: false,
            isSending: false,
            batchSize: 10,
            batchInterval: 30,
            eventTypes: ["delivered": 1]
        )
        let same = base
        let differentCount = EngagementStatistics(
            pendingCount: 2,
            isTracking: false,
            isSending: false,
            batchSize: 10,
            batchInterval: 30,
            eventTypes: ["delivered": 1]
        )

        XCTAssertEqual(base, same)
        XCTAssertNotEqual(base, differentCount)
    }

    // MARK: - Concurrent reads

    /// Both `getStatistics()` and `getPendingEventCount()` bridge onto the serial queue
    /// with `withCheckedContinuation`. This pins that firing several of them at once
    /// resolves every one of them exactly once — the shape of bug a continuation
    /// resumed twice, or never, would break first.
    func testConcurrentStatisticsAndCountCallsAllResolve() async {
        service.trackEvent(makeQueueableEvent())

        async let stats1 = service.getStatistics()
        async let stats2 = service.getStatistics()
        async let count1 = service.getPendingEventCount()
        async let count2 = service.getPendingEventCount()

        let (s1, s2, c1, c2) = await (stats1, stats2, count1, count2)

        XCTAssertEqual(s1, s2)
        XCTAssertEqual(c1, 1)
        XCTAssertEqual(c2, 1)
    }

    // MARK: - Immediate send for high-priority events

    func testClickedEventSendsImmediatelyAndDrainsTheQueue() async throws {
        StubURLProtocol.stub { _ in .response(statusCode: 200, body: Data()) }

        service.trackEvent(EngagementEvent(type: .clicked, callbackUrl: "https://example.com/cb"))

        // `processBatch` bridges into an unstructured `Task` for the network call, which
        // `getPendingEventCount` cannot wait on directly, so poll rather than asserting on
        // the very next queue turn. The queue backing `processBatch` runs at `.background`
        // QoS (`EngagementTrackingService.queue`), which a loaded CI runner can starve for
        // well over a second behind higher-priority work; 5s gives that queue room to be
        // scheduled without weakening what's actually asserted below.
        let drained = try await pollUntil(timeout: 5.0) {
            await self.service.getPendingEventCount() == 0
        }

        XCTAssertTrue(drained, "a delivered .clicked event must be removed from the pending queue")
        XCTAssertEqual(StubURLProtocol.receivedRequests.first?.url?.absoluteString, "https://example.com/cb")
    }

    /// Polls `condition` until it is true or `timeout` elapses, without a fixed sleep
    /// in the common case where the condition is already true.
    private func pollUntil(
        timeout: TimeInterval,
        condition: @escaping () async -> Bool
    ) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return true }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        return await condition()
    }
}
