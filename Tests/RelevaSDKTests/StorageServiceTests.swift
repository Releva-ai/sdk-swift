import XCTest
@testable import RelevaSDK

/// Round-trip, default-value and clearing behaviour for `StorageService`.
///
/// Every test gets its own `UserDefaults` suite, removed again in `tearDown`, so nothing
/// touches `UserDefaults.standard` and no test depends on another's leftovers.
final class StorageServiceTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var storage: StorageService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "StorageServiceTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
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

    // MARK: - Device and profile identifiers

    func testDeviceIdRoundTripsAndOverwrites() {
        XCTAssertNil(storage.getDeviceId(), "no device ID before one is saved")

        storage.saveDeviceId("device-1")
        XCTAssertEqual(storage.getDeviceId(), "device-1")

        storage.saveDeviceId("device-2")
        XCTAssertEqual(storage.getDeviceId(), "device-2", "the newer value must win")
    }

    func testProfileIdRoundTrips() {
        XCTAssertNil(storage.getProfileId())

        storage.saveProfileId("user-1")
        XCTAssertEqual(storage.getProfileId(), "user-1")
    }

    func testClearUserIdentifiersRemovesBothIds() {
        storage.saveDeviceId("device-1")
        storage.saveProfileId("user-1")

        storage.clearUserIdentifiers()

        XCTAssertNil(storage.getDeviceId())
        XCTAssertNil(storage.getProfileId())
    }

    // MARK: - Session

    func testSessionRoundTripsIdAndTimestamp() throws {
        XCTAssertNil(storage.getSession(), "no session before one is saved")

        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        storage.saveSession(Session(sessionId: "session-1", timestamp: timestamp))

        let restored = try XCTUnwrap(storage.getSession())
        XCTAssertEqual(restored.sessionId, "session-1")
        XCTAssertEqual(restored.timestamp.timeIntervalSince1970, 1_700_000_000, accuracy: 0.001)
    }

    func testClearSessionRemovesIdAndTimestamp() {
        storage.saveSession(Session(sessionId: "session-1", timestamp: Date(timeIntervalSince1970: 1_700_000_000)))

        storage.clearSession()

        XCTAssertNil(storage.getSession())
    }

    // MARK: - Cart

    func testCartRoundTripsProductsPricesAndCustomFields() throws {
        XCTAssertNil(storage.getCart(), "no cart before one is saved")

        let cart = Cart.paid(
            [
                CartProduct(
                    id: "p1",
                    price: 19.5,
                    quantity: 2,
                    custom: CustomFields().withStringField(key: "size", values: ["XL"])
                ),
                CartProduct(id: "p2")
            ],
            orderId: "order-1"
        )
        storage.saveCart(cart)

        let restored = try XCTUnwrap(storage.getCart())
        XCTAssertEqual(restored, cart, "the cart must survive the JSON round trip unchanged")
        XCTAssertEqual(restored.orderId, "order-1")
        XCTAssertTrue(restored.cartPaid)
        XCTAssertEqual(restored.products.first?.price, 19.5)
        XCTAssertEqual(restored.products.first?.custom.string.first?.values, ["XL"])
        XCTAssertNil(restored.products.last?.price, "an absent price must stay absent")
    }

    func testCartOverwriteReplacesTheStoredCart() throws {
        storage.saveCart(Cart.active([CartProduct(id: "p1")]))
        storage.saveCart(Cart.active([CartProduct(id: "p2"), CartProduct(id: "p3")]))

        let restored = try XCTUnwrap(storage.getCart())
        XCTAssertEqual(restored.products.map { $0.id }, ["p2", "p3"])
    }

    func testCartInitialisedFlagDefaultsToFalseAndIsResetByClearCart() {
        XCTAssertFalse(storage.isCartInitialized(), "an untouched suite reports an uninitialised cart")

        storage.markCartInitialized()
        XCTAssertTrue(storage.isCartInitialized())

        storage.saveCart(Cart.active([CartProduct(id: "p1")]))
        storage.clearCart()

        XCTAssertNil(storage.getCart())
        XCTAssertFalse(storage.isCartInitialized(), "clearCart also resets the initialised flag")
    }

    // MARK: - Wishlist

    func testWishlistRoundTripsAndClears() throws {
        XCTAssertNil(storage.getWishlist())

        storage.saveWishlist([WishlistProduct(id: "w1"), WishlistProduct(id: "w2")])
        XCTAssertEqual(try XCTUnwrap(storage.getWishlist()).map { $0.id }, ["w1", "w2"])

        storage.markWishlistInitialized()
        XCTAssertTrue(storage.isWishlistInitialized())

        storage.clearWishlist()
        XCTAssertNil(storage.getWishlist())
        XCTAssertFalse(storage.isWishlistInitialized(), "clearWishlist also resets the initialised flag")
    }

    func testEmptyWishlistIsStoredAsAnEmptyListNotAsAbsent() throws {
        storage.saveWishlist([])

        let restored = try XCTUnwrap(storage.getWishlist(), "an empty wishlist is still a stored value")
        XCTAssertTrue(restored.isEmpty)
    }

    // MARK: - Pending engagement events

    func testPendingEngagementEventsDefaultToAnEmptyList() {
        XCTAssertTrue(storage.getPendingEngagementEvents().isEmpty)
    }

    func testAddingPendingEngagementEventsAppendsAndRoundTrips() throws {
        let first = EngagementEvent(
            type: .delivered,
            callbackUrl: "https://example.com/cb/1",
            notificationId: "n1",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            metadata: ["target": "inbox"]
        )
        let second = EngagementEvent(type: .clicked, callbackUrl: "https://example.com/cb/2", notificationId: "n2")

        storage.addPendingEngagementEvent(first)
        storage.addPendingEngagementEvent(second)

        let stored = storage.getPendingEngagementEvents()
        XCTAssertEqual(stored.count, 2)
        XCTAssertEqual(stored.first, first, "the whole event, metadata included, must survive storage")
        XCTAssertEqual(stored.map { $0.notificationId }, ["n1", "n2"], "insertion order is preserved")
    }

    func testRemovingPendingEventsMatchesOnNotificationId() {
        let keptWithId = EngagementEvent(type: .clicked, callbackUrl: "https://example.com/a", notificationId: "keep")
        let removed = EngagementEvent(type: .clicked, callbackUrl: "https://example.com/b", notificationId: "drop")
        let keptWithoutId = EngagementEvent(type: .opened, callbackUrl: "https://example.com/c")

        storage.savePendingEngagementEvents([keptWithId, removed, keptWithoutId])
        storage.removePendingEngagementEvents([removed])

        let remaining = storage.getPendingEngagementEvents()
        XCTAssertEqual(remaining.count, 2)
        XCTAssertEqual(remaining.map { $0.notificationId }, ["keep", nil], "events without an ID are never removed")
    }

    func testClearPendingEngagementEventsEmptiesTheList() {
        storage.addPendingEngagementEvent(
            EngagementEvent(type: .clicked, callbackUrl: "https://example.com/a", notificationId: "n1")
        )

        storage.clearPendingEngagementEvents()

        XCTAssertTrue(storage.getPendingEngagementEvents().isEmpty)
    }

    // MARK: - Push token

    func testPushTokenRoundTripsTokenAndDeviceType() throws {
        XCTAssertNil(storage.getPushToken())

        storage.savePushToken("fcm-token", deviceType: .ios)

        let stored = try XCTUnwrap(storage.getPushToken())
        XCTAssertEqual(stored.token, "fcm-token")
        XCTAssertEqual(stored.deviceType, .ios)
    }

    func testPushTokenUploadTimestampRoundTrips() throws {
        XCTAssertNil(storage.getPushTokenUploadedAt())

        storage.savePushTokenUploadedAt(Date(timeIntervalSince1970: 1_700_000_000))

        let stored = try XCTUnwrap(storage.getPushTokenUploadedAt())
        XCTAssertEqual(stored.timeIntervalSince1970, 1_700_000_000, accuracy: 0.001)
    }

    func testClearPushTokenAlsoClearsTheUploadTimestamp() {
        storage.savePushToken("fcm-token", deviceType: .ios)
        storage.savePushTokenUploadedAt(Date(timeIntervalSince1970: 1_700_000_000))

        storage.clearPushToken()

        XCTAssertNil(storage.getPushToken())
        XCTAssertNil(
            storage.getPushTokenUploadedAt(),
            "a stale upload timestamp would throttle the re-upload of the next token"
        )
    }

    // MARK: - Merge profile IDs

    func testMergeProfileIdsDefaultToAnEmptyListAndDeduplicate() {
        XCTAssertTrue(storage.getMergeProfileIds().isEmpty)

        storage.addMergeProfileId("a")
        storage.addMergeProfileId("b")
        storage.addMergeProfileId("a")

        XCTAssertEqual(storage.getMergeProfileIds(), ["a", "b"], "adding an existing ID is a no-op")
    }

    func testMergeProfileIdsCanBeReplacedAndCleared() {
        storage.saveMergeProfileIds(["a", "b"])
        XCTAssertEqual(storage.getMergeProfileIds(), ["a", "b"])

        storage.saveMergeProfileIds(["c"])
        XCTAssertEqual(storage.getMergeProfileIds(), ["c"])

        storage.clearMergeProfileIds()
        XCTAssertTrue(storage.getMergeProfileIds().isEmpty)
    }

    // MARK: - Inbox

    func testInboxValuesRoundTrip() throws {
        XCTAssertNil(storage.getInboxMessages())
        XCTAssertEqual(storage.getInboxUnreadCount(), 0, "an absent unread count reads as zero")
        XCTAssertNil(storage.getInboxNextCursor())
        XCTAssertNil(storage.getInboxLastFetch())

        storage.saveInboxMessages(#"[{"id":"m1"}]"#)
        storage.saveInboxUnreadCount(3)
        storage.saveInboxNextCursor("cursor-1")
        storage.saveInboxLastFetch(1_700_000_000)

        XCTAssertEqual(storage.getInboxMessages(), #"[{"id":"m1"}]"#)
        XCTAssertEqual(storage.getInboxUnreadCount(), 3)
        XCTAssertEqual(storage.getInboxNextCursor(), "cursor-1")
        XCTAssertEqual(try XCTUnwrap(storage.getInboxLastFetch()), 1_700_000_000, accuracy: 0.001)
    }

    func testSavingANilCursorRemovesTheStoredCursor() {
        storage.saveInboxNextCursor("cursor-1")

        storage.saveInboxNextCursor(nil)

        XCTAssertNil(storage.getInboxNextCursor(), "nil means 'no more pages', not the string \"nil\"")
    }

    func testAZeroLastFetchReadsAsNoFetchYet() {
        storage.saveInboxLastFetch(0)

        XCTAssertNil(storage.getInboxLastFetch())
    }

    func testClearInboxDataRemovesEveryInboxKey() {
        storage.saveInboxMessages(#"[{"id":"m1"}]"#)
        storage.saveInboxUnreadCount(3)
        storage.saveInboxNextCursor("cursor-1")
        storage.saveInboxLastFetch(1_700_000_000)

        storage.clearInboxData()

        XCTAssertNil(storage.getInboxMessages())
        XCTAssertEqual(storage.getInboxUnreadCount(), 0)
        XCTAssertNil(storage.getInboxNextCursor())
        XCTAssertNil(storage.getInboxLastFetch())
    }

    // MARK: - Device analytics

    func testDeviceCountersDefaultToZeroAndRoundTrip() {
        XCTAssertEqual(storage.getDeviceSessionCount(), 0)
        XCTAssertEqual(storage.getDeviceViewsCount(), 0)
        XCTAssertNil(storage.getDeviceFirstSeenAt())

        storage.saveDeviceSessionCount(4)
        storage.saveDeviceViewsCount(11)
        storage.saveDeviceFirstSeenAt("2024-01-01T00:00:00Z")

        XCTAssertEqual(storage.getDeviceSessionCount(), 4)
        XCTAssertEqual(storage.getDeviceViewsCount(), 11)
        XCTAssertEqual(storage.getDeviceFirstSeenAt(), "2024-01-01T00:00:00Z")
    }

    func testDeviceLastSessionTimestampDistinguishesAbsentFromZero() {
        XCTAssertNil(storage.getDeviceLastSessionTimestamp(), "absent means the device has had no session yet")

        storage.saveDeviceLastSessionTimestamp(0)
        XCTAssertEqual(storage.getDeviceLastSessionTimestamp(), 0, "a stored zero is a real value, not absence")

        storage.saveDeviceLastSessionTimestamp(1_700_000_000_000)
        XCTAssertEqual(storage.getDeviceLastSessionTimestamp(), 1_700_000_000_000)
    }

    // MARK: - Sync

    func testLastSyncTimestampRoundTripsAndDrivesIsSyncNeeded() throws {
        XCTAssertNil(storage.getLastSyncTimestamp())
        XCTAssertTrue(storage.isSyncNeeded(), "with no recorded sync, a sync is always needed")

        storage.saveLastSyncTimestamp(Date())
        XCTAssertFalse(storage.isSyncNeeded(interval: 3600), "a sync just now is inside the interval")

        let old = Date(timeIntervalSinceNow: -7200)
        storage.saveLastSyncTimestamp(old)
        XCTAssertEqual(try XCTUnwrap(storage.getLastSyncTimestamp()).timeIntervalSince1970,
                       old.timeIntervalSince1970,
                       accuracy: 0.001)
        XCTAssertTrue(storage.isSyncNeeded(interval: 3600), "a two-hour-old sync is outside a one-hour interval")
    }

    // MARK: - Clearing user data

    func testClearUserDataRemovesUserStateButKeepsDeviceState() {
        storage.saveDeviceId("device-1")
        storage.saveProfileId("user-1")
        storage.saveSession(Session(sessionId: "session-1", timestamp: Date(timeIntervalSince1970: 1_700_000_000)))
        storage.saveCart(Cart.active([CartProduct(id: "p1")]))
        storage.saveWishlist([WishlistProduct(id: "w1")])
        storage.addPendingEngagementEvent(
            EngagementEvent(type: .clicked, callbackUrl: "https://example.com/a", notificationId: "n1")
        )
        storage.saveMergeProfileIds(["a"])
        storage.saveDeviceSessionCount(4)
        storage.saveDeviceViewsCount(11)
        storage.saveDeviceFirstSeenAt("2024-01-01T00:00:00Z")
        storage.saveDeviceLastSessionTimestamp(1_700_000_000_000)
        storage.savePushToken("fcm-token", deviceType: .ios)

        storage.clearUserData()

        XCTAssertNil(storage.getProfileId())
        XCTAssertNil(storage.getSession())
        XCTAssertNil(storage.getCart())
        XCTAssertNil(storage.getWishlist())
        XCTAssertTrue(storage.getPendingEngagementEvents().isEmpty)
        XCTAssertTrue(storage.getMergeProfileIds().isEmpty)

        XCTAssertEqual(storage.getDeviceId(), "device-1", "the device ID identifies the install, not the user")
        XCTAssertEqual(storage.getDeviceSessionCount(), 4, "device analytics are device-level, not user-level")
        XCTAssertEqual(storage.getDeviceViewsCount(), 11)
        XCTAssertEqual(storage.getDeviceFirstSeenAt(), "2024-01-01T00:00:00Z")
        XCTAssertEqual(storage.getDeviceLastSessionTimestamp(), 1_700_000_000_000)
        XCTAssertNotNil(storage.getPushToken(), "the push token belongs to the device")
    }

    // MARK: - Statistics

    func testStorageStatsReflectWhatIsStored() throws {
        storage.saveDeviceId("device-1")
        storage.saveCart(Cart.active([CartProduct(id: "p1"), CartProduct(id: "p2")]))
        storage.saveWishlist([WishlistProduct(id: "w1")])
        storage.saveMergeProfileIds(["a", "b"])

        let stats = storage.getStorageStats()

        XCTAssertEqual(stats["hasDeviceId"] as? Bool, true)
        XCTAssertEqual(stats["hasProfileId"] as? Bool, false)
        XCTAssertEqual(stats["hasSession"] as? Bool, false)
        XCTAssertEqual(stats["hasCart"] as? Bool, true)
        XCTAssertEqual(stats["cartItemCount"] as? Int, 2)
        XCTAssertEqual(stats["wishlistItemCount"] as? Int, 1)
        XCTAssertEqual(stats["pendingEventsCount"] as? Int, 0)
        XCTAssertEqual(stats["hasPushToken"] as? Bool, false)
        XCTAssertEqual(stats["mergeProfileCount"] as? Int, 2)
    }

    func testStorageSizeEstimateGrowsWithStoredData() {
        let empty = storage.getStorageSizeEstimate()

        storage.saveInboxMessages(String(repeating: "x", count: 1000))

        XCTAssertGreaterThan(storage.getStorageSizeEstimate(), empty + 900)
    }
}
