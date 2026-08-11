import XCTest
@testable import RelevaSDK

final class InboxMessageTests: XCTestCase {
    func testInboxMessageFromDict() {
        let dict: [String: Any] = [
            "id": "msg-123",
            "title": "Welcome!",
            "design": ["body": ["rows": []]],
            "read": false,
            "createdAt": "2026-03-15T10:30:00.000Z",
            "inboxMessageId": 42
        ]

        let message = InboxMessage.from(dict: dict)

        XCTAssertNotNil(message)
        XCTAssertEqual(message?.id, "msg-123")
        XCTAssertEqual(message?.title, "Welcome!")
        XCTAssertFalse(message?.read ?? true)
        XCTAssertEqual(message?.inboxMessageId, 42)
        XCTAssertNotNil(message?.design["body"])
    }

    func testInboxMessageFromDictMissingId() {
        let dict: [String: Any] = ["title": "No ID"]
        XCTAssertNil(InboxMessage.from(dict: dict))
    }

    func testInboxMessageToDict() {
        let message = InboxMessage(
            id: "msg-456",
            title: "Test",
            design: ["body": ["rows": []]],
            read: true,
            createdAt: Date(timeIntervalSince1970: 1710000000),
            inboxMessageId: 99
        )

        let dict = message.toDict()

        XCTAssertEqual(dict["id"] as? String, "msg-456")
        XCTAssertEqual(dict["title"] as? String, "Test")
        XCTAssertEqual(dict["read"] as? Bool, true)
        XCTAssertEqual(dict["inboxMessageId"] as? Int, 99)
        XCTAssertNotNil(dict["createdAt"])
    }

    func testInboxMessageRoundTrip() {
        let original = InboxMessage(
            id: "roundtrip",
            title: "Round Trip Test",
            design: ["body": ["values": ["backgroundColor": "#FFFFFF"]]],
            read: false,
            createdAt: Date(),
            inboxMessageId: 7
        )

        let dict = original.toDict()
        let restored = InboxMessage.from(dict: dict)

        XCTAssertNotNil(restored)
        XCTAssertEqual(restored?.id, original.id)
        XCTAssertEqual(restored?.title, original.title)
        XCTAssertEqual(restored?.read, original.read)
        XCTAssertEqual(restored?.inboxMessageId, original.inboxMessageId)
        // Verify createdAt survives round-trip (within 1 second tolerance for formatting precision)
        if let restoredDate = restored?.createdAt {
            XCTAssertEqual(restoredDate.timeIntervalSince1970, original.createdAt.timeIntervalSince1970, accuracy: 1.0)
        } else {
            XCTFail("createdAt should not be nil after round-trip")
        }
    }
}
