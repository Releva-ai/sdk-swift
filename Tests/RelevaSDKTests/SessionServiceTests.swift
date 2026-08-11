import XCTest
import UIKit
@testable import RelevaSDK

/// Tests for `SessionService` session debouncing and lifecycle behaviour.
///
/// Because `SessionService` is `@MainActor`, the entire test class is also
/// annotated `@MainActor` so every test function runs on the main thread —
/// matching the thread that UIApplication lifecycle notifications are delivered on.
@MainActor
final class SessionServiceTests: XCTestCase {
    private var storage: StorageService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Isolated UserDefaults suite per test — prevents cross-test pollution.
        let suiteName = "SessionServiceTests_\(UUID().uuidString)"
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: suiteName),
            "could not create an isolated defaults suite"
        )
        storage = StorageService(userDefaults: defaults)
        // Always start from a clean slate.
        SessionService.shared.dispose()
        // Restore the real threshold in case a previous test changed it.
        SessionService.debounceThresholdMs = 30_000
    }

    override func tearDown() {
        SessionService.shared.dispose()
        SessionService.debounceThresholdMs = 30_000
        super.tearDown()
    }

    // MARK: - Cold start

    func testColdStartIncrementsSessionCount() {
        SessionService.shared.initialize(storage: storage, npsManager: nil)
        XCTAssertEqual(storage.getDeviceSessionCount(), 1)
    }

    func testColdStartGeneratesSessionId() {
        SessionService.shared.initialize(storage: storage, npsManager: nil)
        XCTAssertNotNil(storage.getSession())
    }

    func testColdStartSetsFirstSeenAt() {
        XCTAssertNil(storage.getDeviceFirstSeenAt())
        SessionService.shared.initialize(storage: storage, npsManager: nil)
        XCTAssertNotNil(storage.getDeviceFirstSeenAt())
    }

    // MARK: - Session debouncing

    /// A quick app-switcher bounce (background duration < threshold) must NOT start a new session.
    func testShortBackgroundDoesNotCreateNewSession() {
        // Keep the default 30 s threshold — posting both notifications on the same
        // runloop iteration means 0 ms elapsed, which is well under the threshold.
        SessionService.shared.initialize(storage: storage, npsManager: nil)
        let sessionIdBefore = storage.getSession()?.sessionId
        let countBefore = storage.getDeviceSessionCount()

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        XCTAssertEqual(storage.getDeviceSessionCount(), countBefore, "Session count must not change after a short background")
        XCTAssertEqual(storage.getSession()?.sessionId, sessionIdBefore, "Session ID must not change after a short background")
    }

    /// A background longer than the threshold must start a new session.
    /// We set the threshold to -1 so that any positive elapsed time satisfies the condition,
    /// avoiding the need to actually sleep 30 seconds in the test.
    func testLongBackgroundCreatesNewSession() {
        // -1 ms threshold: even 0 ms elapsed satisfies `elapsed > -1`.
        SessionService.debounceThresholdMs = -1

        SessionService.shared.initialize(storage: storage, npsManager: nil)
        let sessionIdBefore = storage.getSession()?.sessionId
        let countBefore = storage.getDeviceSessionCount()

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        XCTAssertEqual(storage.getDeviceSessionCount(), countBefore + 1, "Session count must increment after a long background")
        XCTAssertNotEqual(storage.getSession()?.sessionId, sessionIdBefore, "Session ID must change after a long background")
    }

    /// Multiple foreground events after a single background must only create one new session.
    func testMultipleForegroundEventsAfterBackgroundCountOnce() {
        SessionService.debounceThresholdMs = -1

        SessionService.shared.initialize(storage: storage, npsManager: nil)
        let countBefore = storage.getDeviceSessionCount()

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        // First foreground: should start a new session and clear pausedAtMs.
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        // Second foreground without a preceding background: pausedAtMs is nil, no new session.
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        XCTAssertEqual(
            storage.getDeviceSessionCount(),
            countBefore + 1,
            "Only one new session must be counted for a single background/foreground cycle"
        )
    }

    /// `firstSeenAt` must be written on the first ever session and never overwritten.
    func testFirstSeenAtNotOverwrittenOnSubsequentSessions() {
        SessionService.debounceThresholdMs = -1

        SessionService.shared.initialize(storage: storage, npsManager: nil)
        let firstSeenAt = storage.getDeviceFirstSeenAt()
        XCTAssertNotNil(firstSeenAt)

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        XCTAssertEqual(storage.getDeviceFirstSeenAt(), firstSeenAt, "firstSeenAt must not change on subsequent sessions")
    }

    // MARK: - Pre-init getSessionId fallback

    /// Before `initialize()` is called, every call to `getSessionId()` must return the same UUID.
    func testGetSessionIdFallbackIsStable() {
        let id1 = SessionService.shared.getSessionId()
        let id2 = SessionService.shared.getSessionId()
        XCTAssertEqual(id1, id2, "Pre-init getSessionId() must return a stable fallback UUID")
    }

    /// After `initialize()`, the real storage-backed session ID replaces the fallback.
    func testGetSessionIdFallbackIsReplacedAfterInitialize() {
        let fallbackId = SessionService.shared.getSessionId()
        SessionService.shared.initialize(storage: storage, npsManager: nil)
        let realId = SessionService.shared.getSessionId()
        XCTAssertNotEqual(realId, fallbackId, "Post-init getSessionId() must return the real session ID, not the fallback")
        XCTAssertEqual(
            realId,
            storage.getSession()?.sessionId,
            "Post-init getSessionId() must return the storage-backed session ID"
        )
    }

    // MARK: - dispose / re-initialize lifecycle

    /// Double `initialize()` must be idempotent — a second call must not start a new session.
    func testDoubleInitializeIsIdempotent() {
        SessionService.shared.initialize(storage: storage, npsManager: nil)
        let countAfterFirst = storage.getDeviceSessionCount()
        let sessionIdAfterFirst = storage.getSession()?.sessionId

        SessionService.shared.initialize(storage: storage, npsManager: nil)

        XCTAssertEqual(storage.getDeviceSessionCount(), countAfterFirst, "Second initialize() must not increment session count")
        XCTAssertEqual(storage.getSession()?.sessionId, sessionIdAfterFirst, "Second initialize() must not change session ID")
    }

    /// After `dispose()`, `getSessionId()` must fall back to the stable pre-init path again.
    func testDisposeResetsToFallbackPath() {
        SessionService.shared.initialize(storage: storage, npsManager: nil)
        SessionService.shared.dispose()

        let id1 = SessionService.shared.getSessionId()
        let id2 = SessionService.shared.getSessionId()
        XCTAssertEqual(id1, id2, "After dispose(), getSessionId() must return a stable fallback UUID")
    }

    /// `dispose()` followed by `initialize()` must start a fresh session.
    func testDisposeAndReinitializeCreatesNewSession() {
        SessionService.shared.initialize(storage: storage, npsManager: nil)
        let firstSessionId = storage.getSession()?.sessionId

        SessionService.shared.dispose()
        SessionService.shared.initialize(storage: storage, npsManager: nil)

        XCTAssertNotEqual(storage.getSession()?.sessionId, firstSessionId, "Re-initialize after dispose must generate a new session ID")
        XCTAssertEqual(storage.getDeviceSessionCount(), 2, "Re-initialize after dispose must increment the session count to 2")
    }
}
