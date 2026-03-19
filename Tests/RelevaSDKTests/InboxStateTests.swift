import XCTest
@testable import RelevaSDK

final class InboxStateTests: XCTestCase {

    func testIsStaleWhenNoLastFetch() {
        let state = InboxState()
        XCTAssertTrue(state.isStale)
    }

    func testIsStaleWhenRecent() {
        let state = InboxState(lastFetchTime: Date())
        XCTAssertFalse(state.isStale)
    }

    func testIsStaleWhenOld() {
        let oldDate = Date().addingTimeInterval(-400) // 6+ minutes ago
        let state = InboxState(lastFetchTime: oldDate)
        XCTAssertTrue(state.isStale)
    }

    func testIsStaleAt5MinBoundary() {
        // Exactly 5 minutes should NOT be stale (>300 required)
        let fiveMinAgo = Date().addingTimeInterval(-300)
        let state = InboxState(lastFetchTime: fiveMinAgo)
        XCTAssertFalse(state.isStale)
    }

    func testDefaultValues() {
        let state = InboxState()
        XCTAssertTrue(state.messages.isEmpty)
        XCTAssertEqual(state.unreadCount, 0)
        XCTAssertNil(state.nextCursor)
        XCTAssertFalse(state.isLoading)
        XCTAssertFalse(state.hasMore)
        XCTAssertNil(state.lastFetchTime)
    }
}
