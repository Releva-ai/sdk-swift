import Foundation
import UIKit

/// Delegate protocol for inbox state changes.
/// Use this when you can't use `@Published` / Combine (e.g. UIKit).
public protocol InboxServiceDelegate: AnyObject {
    func inboxServiceDidUpdateState(_ service: InboxService, state: InboxState)
}

/// Observable singleton service that manages all App Inbox operations.
/// Conforms to `ObservableObject` so SwiftUI views can subscribe directly.
@MainActor
public final class InboxService: ObservableObject {

    // MARK: - Singleton

    public static let shared = InboxService()

    // MARK: - Published State

    @Published public private(set) var state: InboxState = .empty

    // MARK: - Delegate

    public weak var delegate: InboxServiceDelegate?

    // MARK: - Private Properties

    private var accessToken: String = ""
    private var realm: String = ""
    private var userId: String = ""
    private var networkService: NetworkService?
    private var config: RelevaConfig = .full()

    private var isInitialized = false

    #if DEBUG
    /// Exposed for unit tests so we can verify initialization state.
    internal var _isInitialized: Bool { isInitialized }
    #endif

    /// Background task identifier for deferred work
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid

    // MARK: - Lifecycle Observer

    private var lifecycleObserver: NSObjectProtocol?

    // MARK: - Init

    private init() {}

    deinit {
        if let observer = lifecycleObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Setup

    /// Initialize the inbox service. Call from `RelevaClient.initializeInbox()`.
    /// - Parameters:
    ///   - accessToken: Releva access token
    ///   - realm: Releva realm
    ///   - userId: Current user's profile ID
    ///   - networkService: Shared network service
    ///   - config: SDK configuration
    public func initialize(
        accessToken: String,
        realm: String,
        userId: String,
        networkService: NetworkService,
        config: RelevaConfig
    ) {
        self.accessToken = accessToken
        self.realm = realm
        self.userId = userId
        self.networkService = networkService
        self.config = config
        self.isInitialized = true

        // Restore cached state
        restoreCachedState()

        // Register for app lifecycle to refresh when returning to foreground
        lifecycleObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }

        if config.enableDebugLogging {
            print("RelevaSDK Inbox: Initialized for userId=\(userId)")
        }

        // Initial fetch
        Task {
            await refresh()
        }
    }

    /// Update the userId (e.g. after login)
    public func updateUserId(_ userId: String) {
        self.userId = userId
        Task {
            await refresh()
        }
    }

    // MARK: - Public API

    /// Fetch first page + unread count. Replaces existing message list.
    public func refresh() async {
        guard isInitialized, !userId.isEmpty else { return }

        updateState(state.copyWith(isLoading: true, lastError: .some(nil)))

        async let messagesResult = fetchMessages(cursor: nil)
        async let unreadResult = fetchUnreadCount()

        let (msgRes, unreadRes) = await (messagesResult, unreadResult)

        switch msgRes {
        case .success(let response):
            let hasMore = response.nextCursor != nil
            let unread: Int
            if case .success(let uc) = unreadRes {
                unread = uc
            } else {
                unread = response.messages.filter { !$0.isRead }.count
            }

            let newState = state.copyWith(
                messages: response.messages,
                unreadCount: unread,
                nextCursor: .some(response.nextCursor),
                isLoading: false,
                hasMore: hasMore,
                lastFetchTime: .some(Date()),
                lastError: .some(nil)
            )
            updateState(newState)
            persistState(newState)

        case .failure(let error):
            updateState(state.copyWith(isLoading: false, lastError: .some(error)))
            if config.enableDebugLogging {
                print("RelevaSDK Inbox: refresh failed - \(error)")
            }
        }
    }

    /// Refresh only if state is stale (>5 min since last fetch)
    public func refreshIfStale() async {
        guard state.isStale else { return }
        await refresh()
    }

    /// Load the next page of messages and append them
    public func loadMore() async {
        guard isInitialized, !userId.isEmpty,
              state.hasMore,
              let cursor = state.nextCursor,
              !state.isLoading else { return }

        updateState(state.copyWith(isLoading: true))

        switch await fetchMessages(cursor: cursor) {
        case .success(let response):
            let combined = state.messages + response.messages
            let hasMore = response.nextCursor != nil
            let newState = state.copyWith(
                messages: combined,
                nextCursor: .some(response.nextCursor),
                isLoading: false,
                hasMore: hasMore,
                lastFetchTime: .some(Date()),
                lastError: .some(nil)
            )
            updateState(newState)
            persistState(newState)

        case .failure(let error):
            updateState(state.copyWith(isLoading: false, lastError: .some(error)))
            if config.enableDebugLogging {
                print("RelevaSDK Inbox: loadMore failed - \(error)")
            }
        }
    }

    /// Mark a single message as read (optimistic update)
    public func markAsRead(_ messageId: String) async {
        guard isInitialized, !userId.isEmpty else { return }

        let snapshot = state
        let updatedMessages = state.messages.map { msg -> InboxMessage in
            if msg.id == messageId && !msg.isRead {
                var updated = msg
                updated.isRead = true
                return updated
            }
            return msg
        }
        let wasUnread = state.messages.first(where: { $0.id == messageId })?.isRead == false
        let newUnread = max(0, state.unreadCount - (wasUnread ? 1 : 0))

        updateState(state.copyWith(messages: updatedMessages, unreadCount: newUnread))

        guard let net = networkService else { return }
        switch await net.inboxMarkAsRead(messageId: messageId, userId: userId, accessToken: accessToken, realm: realm) {
        case .success:
            if config.enableDebugLogging {
                print("RelevaSDK Inbox: markAsRead succeeded for \(messageId)")
            }
        case .failure(let error):
            // Revert on failure
            updateState(snapshot)
            if config.enableDebugLogging {
                print("RelevaSDK Inbox: markAsRead failed, reverting - \(error)")
            }
        }
    }

    /// Mark all messages as read (optimistic update)
    public func markAllAsRead() async {
        guard isInitialized, !userId.isEmpty else { return }

        let snapshot = state
        let updatedMessages = state.messages.map { msg -> InboxMessage in
            var updated = msg
            updated.isRead = true
            return updated
        }
        updateState(state.copyWith(messages: updatedMessages, unreadCount: 0))

        guard let net = networkService else { return }
        switch await net.inboxMarkAllAsRead(userId: userId, accessToken: accessToken, realm: realm) {
        case .success:
            if config.enableDebugLogging {
                print("RelevaSDK Inbox: markAllAsRead succeeded")
            }
        case .failure(let error):
            updateState(snapshot)
            if config.enableDebugLogging {
                print("RelevaSDK Inbox: markAllAsRead failed, reverting - \(error)")
            }
        }
    }

    /// Delete a message (optimistic update)
    public func deleteMessage(_ messageId: String) async {
        guard isInitialized, !userId.isEmpty else { return }

        let snapshot = state
        let wasUnread = state.messages.first(where: { $0.id == messageId })?.isRead == false
        let filteredMessages = state.messages.filter { $0.id != messageId }
        let newUnread = max(0, state.unreadCount - (wasUnread ? 1 : 0))

        updateState(state.copyWith(messages: filteredMessages, unreadCount: newUnread))

        guard let net = networkService else { return }
        switch await net.inboxDeleteMessage(messageId: messageId, userId: userId, accessToken: accessToken, realm: realm) {
        case .success:
            persistState(state)
            if config.enableDebugLogging {
                print("RelevaSDK Inbox: deleteMessage succeeded for \(messageId)")
            }
        case .failure(let error):
            updateState(snapshot)
            if config.enableDebugLogging {
                print("RelevaSDK Inbox: deleteMessage failed, reverting - \(error)")
            }
        }
    }

    /// Track a tap/click action on a message (fires `inboxMessageClick` server-side)
    public func trackAction(messageId: String) async {
        guard isInitialized, !userId.isEmpty, let net = networkService else { return }

        let result = await net.inboxTrackAction(
            messageId: messageId,
            userId: userId,
            accessToken: accessToken,
            realm: realm
        )

        if config.enableDebugLogging {
            switch result {
            case .success:
                print("RelevaSDK Inbox: trackAction succeeded for \(messageId)")
            case .failure(let error):
                print("RelevaSDK Inbox: trackAction failed - \(error)")
            }
        }
    }

    /// Handle a silent push `inbox_sync` signal (called from push handler)
    public func handleSyncSignal() {
        Task {
            await refresh()
        }
    }

    /// Mark cache as stale (called from background push handler when InboxService may not be initialized)
    public static func markCacheStale() {
        let defaults = UserDefaults.standard
        defaults.set(0, forKey: StorageService.StorageKey.inboxLastFetch.rawValue)
    }

    // MARK: - Private Helpers

    private func updateState(_ newState: InboxState) {
        state = newState
        delegate?.inboxServiceDidUpdateState(self, state: newState)
    }

    private func fetchMessages(cursor: String?) async -> Result<InboxMessagesResponse, RelevaError> {
        guard let net = networkService else {
            return .failure(.invalidConfiguration("NetworkService not initialized"))
        }
        return await net.inboxFetchMessages(
            userId: userId,
            cursor: cursor,
            limit: 20,
            accessToken: accessToken,
            realm: realm
        )
    }

    private func fetchUnreadCount() async -> Result<Int, RelevaError> {
        guard let net = networkService else {
            return .failure(.invalidConfiguration("NetworkService not initialized"))
        }
        return await net.inboxFetchUnreadCount(userId: userId, accessToken: accessToken, realm: realm)
    }

    // MARK: - Persistence

    private func persistState(_ state: InboxState) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let defaults = UserDefaults.standard

        if let data = try? encoder.encode(state.messages) {
            defaults.set(data, forKey: StorageService.StorageKey.inboxMessages.rawValue)
        }
        defaults.set(state.unreadCount, forKey: StorageService.StorageKey.inboxUnreadCount.rawValue)
        defaults.set(state.nextCursor, forKey: StorageService.StorageKey.inboxNextCursor.rawValue)
        if let fetchTime = state.lastFetchTime {
            defaults.set(fetchTime.timeIntervalSince1970 * 1000, forKey: StorageService.StorageKey.inboxLastFetch.rawValue)
        }
    }

    private func restoreCachedState() {
        let defaults = UserDefaults.standard
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        var messages: [InboxMessage] = []
        if let data = defaults.data(forKey: StorageService.StorageKey.inboxMessages.rawValue),
           let decoded = try? decoder.decode([InboxMessage].self, from: data) {
            messages = decoded
        }

        let unreadCount = defaults.integer(forKey: StorageService.StorageKey.inboxUnreadCount.rawValue)
        let nextCursor = defaults.string(forKey: StorageService.StorageKey.inboxNextCursor.rawValue)
        let lastFetchMs = defaults.double(forKey: StorageService.StorageKey.inboxLastFetch.rawValue)
        let lastFetchTime = lastFetchMs > 0 ? Date(timeIntervalSince1970: lastFetchMs / 1000.0) : nil

        if !messages.isEmpty {
            updateState(InboxState(
                messages: messages,
                unreadCount: unreadCount,
                nextCursor: nextCursor,
                isLoading: false,
                hasMore: nextCursor != nil,
                lastFetchTime: lastFetchTime
            ))
        }

        if config.enableDebugLogging {
            print("RelevaSDK Inbox: Restored \(messages.count) cached messages")
        }
    }

    #if DEBUG
    /// Reset the singleton to a clean state.  Used by unit tests.
    internal func resetForTesting() {
        accessToken = ""
        realm = ""
        userId = ""
        networkService = nil
        config = .full()
        isInitialized = false
        state = .empty

        if let observer = lifecycleObserver {
            NotificationCenter.default.removeObserver(observer)
            lifecycleObserver = nil
        }
    }
    #endif
}
