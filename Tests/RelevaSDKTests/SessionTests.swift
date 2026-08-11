import XCTest
@testable import RelevaSDK

/// `Session` expiry arithmetic and `SessionManager` persistence.
///
/// `SessionServiceTests` covers `SessionService`, the app-lifecycle-driven session counter.
/// This suite covers the unrelated `Core/Session.swift` pair, which models the 24-hour
/// session window that gets persisted through `StorageService`.
///
/// Every session here is built with an explicit timestamp, so nothing depends on how long
/// the test itself takes; assertions on "now" are given hour-scale or 5-second tolerances.
final class SessionTests: XCTestCase {
    // MARK: - Fixtures

    private static let expirationInterval: TimeInterval = 24 * 60 * 60

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var storage: StorageService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "SessionTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName), "could not create an isolated defaults suite")
        storage = StorageService(userDefaults: defaults)
    }

    override func tearDown() {
        if let suiteName = suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        storage = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    /// A session whose timestamp is `age` seconds in the past.
    private func makeSession(age: TimeInterval, id: String = "fixed-session-id") -> Session {
        Session(sessionId: id, timestamp: Date().addingTimeInterval(-age))
    }

    // MARK: - New sessions

    func testANewSessionGetsALowercasedUuidAndStartsNow() {
        let session = Session()

        XCTAssertNotNil(UUID(uuidString: session.sessionId), "the session id is expected to be a UUID string")
        XCTAssertEqual(session.sessionId, session.sessionId.lowercased(), "session ids are lowercased")
        XCTAssertEqual(session.ageInSeconds(), 0, accuracy: 5, "a fresh session starts at approximately zero age")
        XCTAssertFalse(session.isExpired())
    }

    func testEachNewSessionGetsItsOwnId() {
        XCTAssertNotEqual(Session().sessionId, Session().sessionId)
    }

    // MARK: - Expiry

    func testASessionExpiresOnlyAfterTwentyFourHours() {
        XCTAssertFalse(makeSession(age: 23 * 3600).isExpired(), "a 23-hour-old session is still valid")
        XCTAssertTrue(makeSession(age: 25 * 3600).isExpired(), "a 25-hour-old session has expired")
    }

    func testRefreshIfNeededLeavesAFreshSessionAlone() {
        let session = makeSession(age: 3600)

        XCTAssertFalse(session.refreshIfNeeded(), "nothing to refresh")
        XCTAssertEqual(session.sessionId, "fixed-session-id")
        XCTAssertEqual(session.ageInSeconds(), 3600, accuracy: 5)
    }

    func testRefreshIfNeededReplacesAnExpiredSession() {
        let session = makeSession(age: 25 * 3600)

        XCTAssertTrue(session.refreshIfNeeded(), "an expired session must be rotated")
        XCTAssertNotEqual(session.sessionId, "fixed-session-id", "the id is regenerated, not reused")
        XCTAssertNotNil(UUID(uuidString: session.sessionId))
        XCTAssertEqual(session.ageInSeconds(), 0, accuracy: 5, "the clock restarts")
    }

    func testForceRefreshReplacesEvenAFreshSession() {
        let session = makeSession(age: 60)

        session.forceRefresh()

        XCTAssertNotEqual(session.sessionId, "fixed-session-id")
        XCTAssertEqual(session.ageInSeconds(), 0, accuracy: 5)
    }

    // MARK: - Age and remaining time

    func testAgeIsReportedInBothSecondsAndHours() {
        let session = makeSession(age: 2 * 3600)

        XCTAssertEqual(session.ageInSeconds(), 7200, accuracy: 5)
        XCTAssertEqual(session.ageInHours(), 2, accuracy: 0.01)
    }

    func testRemainingTimeCountsDownAndFloorsAtZero() {
        XCTAssertEqual(makeSession(age: 23 * 3600).remainingTime(), 3600, accuracy: 5)
        XCTAssertEqual(makeSession(age: 25 * 3600).remainingTime(), 0, "an expired session never reports negative time")
    }

    func testRemainingTimeStringFormatsHoursAndMinutes() {
        // Offsets are chosen 30 seconds clear of a minute boundary so the elapsed test time
        // cannot change the truncated minute count.
        let ninetyMinutesLeft = makeSession(age: SessionTests.expirationInterval - 5430)
        let tenMinutesLeft = makeSession(age: SessionTests.expirationInterval - 630)

        XCTAssertEqual(ninetyMinutesLeft.remainingTimeString(), "1h 30m")
        XCTAssertEqual(tenMinutesLeft.remainingTimeString(), "10m", "the hour component is dropped when it is zero")
        XCTAssertEqual(makeSession(age: 25 * 3600).remainingTimeString(), "Expired")
    }

    // MARK: - Identity and description

    func testSessionsAreEqualByIdAlone() {
        let early = Session(sessionId: "same", timestamp: Date(timeIntervalSince1970: 1_700_000_000))
        let late = Session(sessionId: "same", timestamp: Date(timeIntervalSince1970: 1_700_009_999))

        XCTAssertEqual(early, late, "the timestamp is not part of session identity")
        XCTAssertNotEqual(early, Session(sessionId: "other", timestamp: early.timestamp))
    }

    func testDescriptionNamesTheSessionAndItsExpiryState() {
        let text = makeSession(age: 25 * 3600, id: "abc").description

        XCTAssertTrue(text.contains("abc"), "unexpected description: \(text)")
        XCTAssertTrue(text.contains("expired: true"), "unexpected description: \(text)")
    }

    // MARK: - Dictionary form

    func testToDictWritesTheIdAndAnEpochTimestamp() {
        let session = Session(sessionId: "abc", timestamp: Date(timeIntervalSince1970: 1_700_000_000))

        let dict = session.toDict()

        XCTAssertEqual(dict.keys.sorted(), ["sessionId", "timestamp"])
        XCTAssertEqual(dict["sessionId"] as? String, "abc")
        XCTAssertEqual(dict["timestamp"] as? TimeInterval, 1_700_000_000)
    }

    func testADictionaryRoundTripPreservesTheSession() throws {
        let original = Session(sessionId: "abc", timestamp: Date(timeIntervalSince1970: 1_700_000_000))

        let restored = try XCTUnwrap(Session.from(dict: original.toDict()))

        XCTAssertEqual(restored.sessionId, "abc")
        XCTAssertEqual(restored.timestamp.timeIntervalSince1970, 1_700_000_000, accuracy: 0.001)
    }

    func testFromDictRejectsIncompleteData() {
        XCTAssertNil(Session.from(dict: [:]), "an empty dictionary is not a session")
        XCTAssertNil(Session.from(dict: ["timestamp": 1_700_000_000.0]), "a session without an id is unusable")
        XCTAssertNil(Session.from(dict: ["sessionId": "abc"]), "a session without a timestamp is unusable")
        XCTAssertNil(
            Session.from(dict: ["sessionId": "abc", "timestamp": "1700000000"]),
            "a stringified timestamp is rejected rather than parsed"
        )
    }

    // MARK: - createOrRestore

    func testCreateOrRestoreKeepsAFreshStoredSession() {
        storage.saveSession(makeSession(age: 3600, id: "stored"))

        let restored = Session.createOrRestore(from: storage)

        XCTAssertEqual(restored.sessionId, "stored")
        XCTAssertEqual(restored.ageInSeconds(), 3600, accuracy: 5, "the original start time is preserved")
    }

    func testCreateOrRestoreReplacesAndPersistsAnExpiredStoredSession() throws {
        storage.saveSession(makeSession(age: 25 * 3600, id: "stale"))

        let created = Session.createOrRestore(from: storage)

        XCTAssertNotEqual(created.sessionId, "stale")
        XCTAssertEqual(try XCTUnwrap(storage.getSession()).sessionId, created.sessionId, "the new session is persisted")
    }

    func testCreateOrRestorePersistsANewSessionWhenNothingIsStored() throws {
        XCTAssertNil(storage.getSession(), "precondition: the isolated suite starts empty")

        let created = Session.createOrRestore(from: storage)

        XCTAssertEqual(try XCTUnwrap(storage.getSession()).sessionId, created.sessionId)
    }

    // MARK: - SessionManager

    func testGetCurrentSessionCreatesPersistsAndNotifiesOnce() throws {
        let manager = SessionManager(storage: storage)
        var changes: [String] = []
        manager.onSessionChanged = { changes.append($0.sessionId) }

        let first = manager.getCurrentSession()
        let second = manager.getCurrentSession()

        XCTAssertEqual(first.sessionId, second.sessionId, "the manager caches the session")
        XCTAssertEqual(changes, [first.sessionId], "the callback fires only when the session actually changes")
        XCTAssertEqual(try XCTUnwrap(storage.getSession()).sessionId, first.sessionId)
    }

    func testGetCurrentSessionAdoptsAFreshStoredSession() {
        storage.saveSession(makeSession(age: 3600, id: "stored"))
        let manager = SessionManager(storage: storage)

        XCTAssertEqual(manager.getCurrentSession().sessionId, "stored")
    }

    func testRefreshIfNeededReportsNoRefreshBecauseGetCurrentSessionAlreadyRotated() throws {
        storage.saveSession(makeSession(age: 25 * 3600, id: "stale"))
        let manager = SessionManager(storage: storage)

        let refreshed = manager.refreshIfNeeded()

        // refreshIfNeeded() calls getCurrentSession() first, which already discards the expired
        // session via createOrRestore. The session it then inspects is always fresh, so the
        // return value is false even though the stored session was in fact replaced.
        XCTAssertFalse(refreshed, "the rotation happened inside getCurrentSession(), so nothing is left to refresh")
        XCTAssertNotEqual(try XCTUnwrap(storage.getSession()).sessionId, "stale", "the expired session is gone")
        XCTAssertFalse(manager.isSessionExpired())
    }

    func testForceRefreshReplacesPersistsAndNotifies() throws {
        let manager = SessionManager(storage: storage)
        let original = manager.getCurrentSession()
        var changes: [String] = []
        manager.onSessionChanged = { changes.append($0.sessionId) }

        manager.forceRefresh()

        let current = manager.getCurrentSession()
        XCTAssertNotEqual(current.sessionId, original.sessionId)
        XCTAssertEqual(changes, [current.sessionId], "forceRefresh notifies exactly once")
        XCTAssertEqual(try XCTUnwrap(storage.getSession()).sessionId, current.sessionId)
    }

    func testClearSessionDropsBothTheCachedAndTheStoredSession() {
        let manager = SessionManager(storage: storage)
        _ = manager.getCurrentSession()

        manager.clearSession()

        XCTAssertNil(storage.getSession())
        XCTAssertNil(manager.getSessionAge(), "there is no session to age")
        XCTAssertTrue(manager.isSessionExpired(), "no session counts as expired")
    }

    func testAgeAndExpiryBeforeAnySessionExists() {
        let manager = SessionManager(storage: storage)

        XCTAssertNil(manager.getSessionAge())
        XCTAssertTrue(manager.isSessionExpired(), "a manager that has never handed out a session reports expired")
    }

    func testGetSessionAgeReflectsTheAdoptedSession() throws {
        storage.saveSession(makeSession(age: 2 * 3600, id: "stored"))
        let manager = SessionManager(storage: storage)
        _ = manager.getCurrentSession()

        XCTAssertEqual(try XCTUnwrap(manager.getSessionAge()), 2, accuracy: 0.01)
    }
}
