import XCTest
@testable import RelevaSDK

// A minimal mock of NetworkService that returns canned inbox responses.
fileprivate class MockNetworkService: NetworkService {
    var fetchMessagesResult: Result<InboxMessagesResponse, RelevaError> = .failure(.networkError("not set"))
    var unreadCountResult: Result<Int, RelevaError> = .failure(.networkError("not set"))
    var lastMarkReadId: String?
    var shouldFailMarkRead = false
    var lastDeleteId: String?
    var shouldFailDelete = false
    var trackActionIds: [String] = []

    override func inboxFetchMessages(userId: String, cursor: String?, limit: Int, accessToken: String, realm: String) async -> Result<InboxMessagesResponse, RelevaError> {
        return fetchMessagesResult
    }

    override func inboxFetchUnreadCount(userId: String, accessToken: String, realm: String) async -> Result<Int, RelevaError> {
        return unreadCountResult
    }

    override func inboxMarkAsRead(messageId: String, userId: String, accessToken: String, realm: String) async -> Result<Void, RelevaError> {
        lastMarkReadId = messageId
        return shouldFailMarkRead ? .failure(.networkError("fail")) : .success(())
    }

    override func inboxDeleteMessage(messageId: String, userId: String, accessToken: String, realm: String) async -> Result<Void, RelevaError> {
        lastDeleteId = messageId
        return shouldFailDelete ? .failure(.networkError("fail")) : .success(())
    }

    override func inboxTrackAction(messageId: String, userId: String, accessToken: String, realm: String) async -> Result<Void, RelevaError> {
        trackActionIds.append(messageId)
        return .success(())
    }
}

final class InboxServiceTests: XCTestCase {
    var service: InboxService!
    var mockNetwork: MockNetworkService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        // reset singleton
        service = InboxService.shared
        service.resetForTesting()
        mockNetwork = MockNetworkService(realm: "", accessToken: "", config: .full())
        // initialize with dummy data
        service.initialize(
            accessToken: "token",
            realm: "",
            userId: "user123",
            networkService: mockNetwork,
            config: .full()
        )
    }

    override func tearDownWithError() throws {
        service.resetForTesting()
        service = nil
        mockNetwork = nil
        try super.tearDownWithError()
    }

    func testRefreshSuccessCachesState() async throws {
        let msg = InboxMessage(id: "1", title: "Hi", inboxMessageId: "tmpl", createdAt: Date())
        let response = InboxMessagesResponse(messages: [msg], nextCursor: nil)
        mockNetwork.fetchMessagesResult = .success(response)
        mockNetwork.unreadCountResult = .success(5)

        await service.refresh()

        XCTAssertEqual(service.state.messages, [msg])
        XCTAssertEqual(service.state.unreadCount, 5)
        XCTAssertFalse(service.state.isLoading)
        XCTAssertNil(service.state.lastError)

        // verify persisted to UserDefaults
        let defaults = UserDefaults.standard
        XCTAssertNotNil(defaults.data(forKey: StorageService.StorageKey.inboxMessages.rawValue))
    }

    func testMarkAsReadOptimisticAndRevertOnFailure() async throws {
        let msg = InboxMessage(id: "1", title: "Hi", inboxMessageId: "tmpl", createdAt: Date())
        service.state = service.state.copyWith(messages: [msg], unreadCount: 1)

        mockNetwork.shouldFailMarkRead = true
        await service.markAsRead("1")
        // failure should revert state
        XCTAssertEqual(service.state.unreadCount, 1)
        XCTAssertFalse(service.state.messages[0].isRead)

        // now succeed
        mockNetwork.shouldFailMarkRead = false
        await service.markAsRead("1")
        XCTAssertEqual(service.state.unreadCount, 0)
        XCTAssertTrue(service.state.messages[0].isRead)
        XCTAssertEqual(mockNetwork.lastMarkReadId, "1")
    }

    func testMarkCacheStaleSetsUserDefault() {
        InboxService.markCacheStale()
        let value = UserDefaults.standard.double(forKey: StorageService.StorageKey.inboxLastFetch.rawValue)
        XCTAssertEqual(value, 0)
    }

    func testHandleSyncSignalTriggersRefresh() async throws {
        let msg = InboxMessage(id: "xyz", title: "hi", inboxMessageId: "tmpl", createdAt: Date())
        mockNetwork.fetchMessagesResult = .success(InboxMessagesResponse(messages: [msg], nextCursor: nil))
        mockNetwork.unreadCountResult = .success(0)

        await service.handleSyncSignal()
        XCTAssertEqual(service.state.messages.first?.id, "xyz")
    }

    func testHandleRemoteNotificationInboxSyncMarksStale() throws {
        // ensure last fetch is nonzero
        let defaults = UserDefaults.standard
        defaults.set(Date().timeIntervalSince1970 * 1000, forKey: StorageService.StorageKey.inboxLastFetch.rawValue)

        let userInfo: [AnyHashable: Any] = ["magellan_notification_type": "inbox_sync"]
        let client = RelevaClient.shared
        XCTAssertNotNil(client)
        client?.handleRemoteNotification(userInfo)

        let newVal = defaults.double(forKey: StorageService.StorageKey.inboxLastFetch.rawValue)
        XCTAssertEqual(newVal, 0, "inbox cache should be marked stale")
    }
}

