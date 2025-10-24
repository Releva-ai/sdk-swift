import Foundation

/// Service for managing persistent storage using UserDefaults
public class StorageService {

    // MARK: - Storage Keys

    enum StorageKey: String {
        // User data
        case deviceId = "rlv_device_id"
        case profileId = "rlv_profile_id"
        case sessionId = "rlv_session_id"
        case sessionTimestamp = "rlv_session_timestamp"

        // Cart and wishlist
        case cart = "rlv_cart"
        case wishlist = "rlv_wishlist"
        case cartInitialized = "rlv_cart_initialized"
        case wishlistInitialized = "rlv_wishlist_initialized"

        // Engagement events
        case pendingEngagementEvents = "rlv_pending_engagement_events"

        // Push notifications
        case pushToken = "rlv_push_token"
        case deviceType = "rlv_device_type"

        // Settings
        case sdkVersion = "rlv_sdk_version"
        case lastSyncTimestamp = "rlv_last_sync"

        // Profile merge
        case mergeProfileIds = "rlv_merge_profile_ids"
    }

    // MARK: - Properties

    /// UserDefaults instance to use
    private let userDefaults: UserDefaults

    /// SDK version for migration purposes
    private let sdkVersion = "1.0.0"

    // MARK: - Initializers

    /// Initialize with custom UserDefaults
    /// - Parameter userDefaults: UserDefaults instance (defaults to standard)
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        checkAndMigrateIfNeeded()
    }

    // MARK: - Device and Profile Management

    /// Save device ID
    public func saveDeviceId(_ deviceId: String) {
        userDefaults.set(deviceId, forKey: StorageKey.deviceId.rawValue)
    }

    /// Get device ID
    public func getDeviceId() -> String? {
        return userDefaults.string(forKey: StorageKey.deviceId.rawValue)
    }

    /// Save profile ID
    public func saveProfileId(_ profileId: String) {
        userDefaults.set(profileId, forKey: StorageKey.profileId.rawValue)
    }

    /// Get profile ID
    public func getProfileId() -> String? {
        return userDefaults.string(forKey: StorageKey.profileId.rawValue)
    }

    /// Clear user identifiers
    public func clearUserIdentifiers() {
        userDefaults.removeObject(forKey: StorageKey.deviceId.rawValue)
        userDefaults.removeObject(forKey: StorageKey.profileId.rawValue)
    }

    // MARK: - Session Management

    /// Save session
    public func saveSession(_ session: Session) {
        userDefaults.set(session.sessionId, forKey: StorageKey.sessionId.rawValue)
        userDefaults.set(session.timestamp.timeIntervalSince1970, forKey: StorageKey.sessionTimestamp.rawValue)
    }

    /// Get session
    public func getSession() -> Session? {
        guard let sessionId = userDefaults.string(forKey: StorageKey.sessionId.rawValue),
              let timestampInterval = userDefaults.object(forKey: StorageKey.sessionTimestamp.rawValue) as? TimeInterval else {
            return nil
        }

        let timestamp = Date(timeIntervalSince1970: timestampInterval)
        return Session(sessionId: sessionId, timestamp: timestamp)
    }

    /// Clear session
    public func clearSession() {
        userDefaults.removeObject(forKey: StorageKey.sessionId.rawValue)
        userDefaults.removeObject(forKey: StorageKey.sessionTimestamp.rawValue)
    }

    // MARK: - Cart Management

    /// Save cart
    public func saveCart(_ cart: Cart) {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(cart) {
            userDefaults.set(encoded, forKey: StorageKey.cart.rawValue)
        }
    }

    /// Get cart
    public func getCart() -> Cart? {
        guard let data = userDefaults.data(forKey: StorageKey.cart.rawValue) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(Cart.self, from: data)
    }

    /// Clear cart
    public func clearCart() {
        userDefaults.removeObject(forKey: StorageKey.cart.rawValue)
        userDefaults.set(false, forKey: StorageKey.cartInitialized.rawValue)
    }

    /// Check if cart was initialized
    public func isCartInitialized() -> Bool {
        return userDefaults.bool(forKey: StorageKey.cartInitialized.rawValue)
    }

    /// Mark cart as initialized
    public func markCartInitialized() {
        userDefaults.set(true, forKey: StorageKey.cartInitialized.rawValue)
    }

    // MARK: - Wishlist Management

    /// Save wishlist
    public func saveWishlist(_ wishlist: [WishlistProduct]) {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(wishlist) {
            userDefaults.set(encoded, forKey: StorageKey.wishlist.rawValue)
        }
    }

    /// Get wishlist
    public func getWishlist() -> [WishlistProduct]? {
        guard let data = userDefaults.data(forKey: StorageKey.wishlist.rawValue) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode([WishlistProduct].self, from: data)
    }

    /// Clear wishlist
    public func clearWishlist() {
        userDefaults.removeObject(forKey: StorageKey.wishlist.rawValue)
        userDefaults.set(false, forKey: StorageKey.wishlistInitialized.rawValue)
    }

    /// Check if wishlist was initialized
    public func isWishlistInitialized() -> Bool {
        return userDefaults.bool(forKey: StorageKey.wishlistInitialized.rawValue)
    }

    /// Mark wishlist as initialized
    public func markWishlistInitialized() {
        userDefaults.set(true, forKey: StorageKey.wishlistInitialized.rawValue)
    }

    // MARK: - Engagement Events Management

    /// Save pending engagement events
    public func savePendingEngagementEvents(_ events: [EngagementEvent]) {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(events) {
            userDefaults.set(encoded, forKey: StorageKey.pendingEngagementEvents.rawValue)
        }
    }

    /// Get pending engagement events
    public func getPendingEngagementEvents() -> [EngagementEvent] {
        guard let data = userDefaults.data(forKey: StorageKey.pendingEngagementEvents.rawValue) else { return [] }
        let decoder = JSONDecoder()
        return (try? decoder.decode([EngagementEvent].self, from: data)) ?? []
    }

    /// Add engagement event to pending
    public func addPendingEngagementEvent(_ event: EngagementEvent) {
        var events = getPendingEngagementEvents()
        events.append(event)
        savePendingEngagementEvents(events)
    }

    /// Clear pending engagement events
    public func clearPendingEngagementEvents() {
        userDefaults.removeObject(forKey: StorageKey.pendingEngagementEvents.rawValue)
    }

    /// Remove specific engagement events
    public func removePendingEngagementEvents(_ eventsToRemove: [EngagementEvent]) {
        var events = getPendingEngagementEvents()
        let idsToRemove = Set(eventsToRemove.compactMap { $0.notificationId })
        events.removeAll { event in
            if let id = event.notificationId {
                return idsToRemove.contains(id)
            }
            return false
        }
        savePendingEngagementEvents(events)
    }

    // MARK: - Push Notification Management

    /// Save push token
    public func savePushToken(_ token: String, deviceType: DeviceType) {
        userDefaults.set(token, forKey: StorageKey.pushToken.rawValue)
        userDefaults.set(deviceType.rawValue, forKey: StorageKey.deviceType.rawValue)
    }

    /// Get push token
    public func getPushToken() -> (token: String, deviceType: DeviceType)? {
        guard let token = userDefaults.string(forKey: StorageKey.pushToken.rawValue),
              let deviceTypeString = userDefaults.string(forKey: StorageKey.deviceType.rawValue),
              let deviceType = DeviceType(rawValue: deviceTypeString) else {
            return nil
        }
        return (token, deviceType)
    }

    /// Clear push token
    public func clearPushToken() {
        userDefaults.removeObject(forKey: StorageKey.pushToken.rawValue)
        userDefaults.removeObject(forKey: StorageKey.deviceType.rawValue)
    }

    // MARK: - Profile Merge Management

    /// Save merge profile IDs
    public func saveMergeProfileIds(_ ids: [String]) {
        userDefaults.set(ids, forKey: StorageKey.mergeProfileIds.rawValue)
    }

    /// Get merge profile IDs
    public func getMergeProfileIds() -> [String] {
        return userDefaults.stringArray(forKey: StorageKey.mergeProfileIds.rawValue) ?? []
    }

    /// Add merge profile ID
    public func addMergeProfileId(_ id: String) {
        var ids = getMergeProfileIds()
        if !ids.contains(id) {
            ids.append(id)
            saveMergeProfileIds(ids)
        }
    }

    /// Clear merge profile IDs
    public func clearMergeProfileIds() {
        userDefaults.removeObject(forKey: StorageKey.mergeProfileIds.rawValue)
    }

    // MARK: - Sync Management

    /// Save last sync timestamp
    public func saveLastSyncTimestamp(_ timestamp: Date) {
        userDefaults.set(timestamp.timeIntervalSince1970, forKey: StorageKey.lastSyncTimestamp.rawValue)
    }

    /// Get last sync timestamp
    public func getLastSyncTimestamp() -> Date? {
        guard let interval = userDefaults.object(forKey: StorageKey.lastSyncTimestamp.rawValue) as? TimeInterval else {
            return nil
        }
        return Date(timeIntervalSince1970: interval)
    }

    /// Check if sync is needed (older than specified interval)
    public func isSyncNeeded(interval: TimeInterval = 3600) -> Bool {
        guard let lastSync = getLastSyncTimestamp() else { return true }
        return Date().timeIntervalSince(lastSync) > interval
    }

    // MARK: - Clear All Data

    /// Clear all SDK data
    public func clearAllData() {
        let domain = Bundle.main.bundleIdentifier ?? ""
        userDefaults.removePersistentDomain(forName: domain)

        // Or clear specific keys
        StorageKey.allCases.forEach { key in
            userDefaults.removeObject(forKey: key.rawValue)
        }

        userDefaults.synchronize()
    }

    /// Clear user-specific data (keep device ID and settings)
    public func clearUserData() {
        clearSession()
        clearCart()
        clearWishlist()
        clearPendingEngagementEvents()
        clearMergeProfileIds()
        userDefaults.removeObject(forKey: StorageKey.profileId.rawValue)
    }

    // MARK: - Migration

    /// Check and migrate data if needed
    private func checkAndMigrateIfNeeded() {
        let savedVersion = userDefaults.string(forKey: StorageKey.sdkVersion.rawValue)

        if savedVersion != sdkVersion {
            // Perform migration if needed
            migrateData(from: savedVersion, to: sdkVersion)
            userDefaults.set(sdkVersion, forKey: StorageKey.sdkVersion.rawValue)
        }
    }

    /// Migrate data between versions
    private func migrateData(from oldVersion: String?, to newVersion: String) {
        // Add migration logic here when needed
        // For now, no migration needed for v1.0.0
    }
}

// MARK: - StorageKey CaseIterable

extension StorageService.StorageKey: CaseIterable {}

// MARK: - Storage Statistics

extension StorageService {

    /// Get storage statistics
    public func getStorageStats() -> [String: Any] {
        return [
            "hasDeviceId": getDeviceId() != nil,
            "hasProfileId": getProfileId() != nil,
            "hasSession": getSession() != nil,
            "hasCart": getCart() != nil,
            "cartItemCount": getCart()?.products.count ?? 0,
            "wishlistItemCount": getWishlist()?.count ?? 0,
            "pendingEventsCount": getPendingEngagementEvents().count,
            "hasPushToken": getPushToken() != nil,
            "mergeProfileCount": getMergeProfileIds().count,
            "sdkVersion": sdkVersion
        ]
    }

    /// Get storage size estimate in bytes
    public func getStorageSizeEstimate() -> Int {
        var totalSize = 0

        StorageKey.allCases.forEach { key in
            if let data = userDefaults.object(forKey: key.rawValue) as? Data {
                totalSize += data.count
            } else if let string = userDefaults.string(forKey: key.rawValue) {
                totalSize += string.utf8.count
            } else if let array = userDefaults.array(forKey: key.rawValue) {
                totalSize += "\(array)".utf8.count
            }
        }

        return totalSize
    }
}