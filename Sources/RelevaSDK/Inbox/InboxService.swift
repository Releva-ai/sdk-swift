import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

/// Manages inbox state, API calls, caching, and optimistic updates.
///
/// Observe `state` (via Combine) for reactive UI updates.
/// Use `InboxService.shared` singleton after calling `initialize()`.
public class InboxService: ObservableObject {

    /// Shared singleton instance
    public static let shared = InboxService()

    /// Current inbox state
    @Published public private(set) var state = InboxState()

    private var networkService: NetworkService?
    private var storage: StorageService?
    private var accessToken: String?
    private var profileId: String?
    private var initialized = false
    private var foregroundObserver: NSObjectProtocol?

    private init() {}

    /// Initialize with network and storage services. Call after setProfileId().
    public func initialize(
        networkService: NetworkService,
        accessToken: String,
        profileId: String?,
        storage: StorageService
    ) {
        let profileChanged = self.profileId != profileId

        self.networkService = networkService
        self.accessToken = accessToken
        self.profileId = profileId
        self.storage = storage

        if initialized {
            if profileChanged {
                restoreCachedState()
            }
            return
        }
        initialized = true

        // Register for foreground notifications to refresh on app resume
        #if canImport(UIKit)
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshIfStale()
        }
        #endif

        restoreCachedState()
    }

    /// Update the profile ID (e.g. after login/logout)
    public func updateProfileId(_ profileId: String?) {
        self.profileId = profileId
    }

    /// Fetch first page of messages + unread count in parallel.
    public func refresh() {
        let work = { [weak self] in
            guard let self = self, self.initialized, let userId = self.profileId else { return }

            self.state.isLoading = true

            let group = DispatchGroup()
            var fetchedMessages: [InboxMessage]?
            var fetchedCursor: String?
            var fetchedUnread: Int?

            group.enter()
            self.networkService?.fetchInboxMessages(userId: userId) { result in
                if case .success(let json) = result {
                    let messagesArray = (json["messages"] as? [[String: Any]]) ?? []
                    fetchedMessages = messagesArray.compactMap { InboxMessage.from(dict: $0) }
                    fetchedCursor = json["nextCursor"] as? String
                }
                group.leave()
            }

            group.enter()
            self.networkService?.fetchInboxUnreadCount(userId: userId) { result in
                if case .success(let count) = result {
                    fetchedUnread = count
                }
                group.leave()
            }

            group.notify(queue: .main) { [weak self] in
                guard let self = self else { return }

                if let messages = fetchedMessages {
                    self.state.messages = messages
                    self.state.nextCursor = fetchedCursor
                    self.state.hasMore = fetchedCursor != nil
                    self.state.lastFetchTime = Date()
                }
                if let unread = fetchedUnread {
                    self.state.unreadCount = unread
                }
                self.state.isLoading = false
                self.persistState()
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    /// Fetch next page using nextCursor and append to list.
    public func loadMore() {
        let work = { [weak self] in
            guard let self = self, self.initialized, !self.state.isLoading, self.state.hasMore,
                  let userId = self.profileId else { return }

            self.state.isLoading = true

            self.networkService?.fetchInboxMessages(userId: userId, cursor: self.state.nextCursor) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self = self else { return }

                    switch result {
                    case .success(let json):
                        let messagesArray = (json["messages"] as? [[String: Any]]) ?? []
                        let newMessages = messagesArray.compactMap { InboxMessage.from(dict: $0) }
                        let nextCursor = json["nextCursor"] as? String

                        self.state.messages.append(contentsOf: newMessages)
                        self.state.nextCursor = nextCursor
                        self.state.hasMore = nextCursor != nil
                        self.state.lastFetchTime = Date()
                        self.state.isLoading = false
                        self.persistState()

                    case .failure:
                        self.state.isLoading = false
                    }
                }
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    /// Mark single message as read (optimistic update).
    public func markAsRead(_ messageId: String) {
        let work = { [weak self] in
            guard let self = self, self.initialized, let userId = self.profileId else { return }

            guard let index = self.state.messages.firstIndex(where: { $0.id == messageId }) else { return }
            if self.state.messages[index].read { return }

            // Snapshot for rollback
            let originalRead = self.state.messages[index].read
            let originalCount = self.state.unreadCount

            // Optimistic update
            self.state.messages[index].read = true
            self.state.unreadCount = max(0, self.state.unreadCount - 1)

            self.networkService?.inboxMarkAsRead(messageId: messageId, userId: userId) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if case .failure = result {
                        if let idx = self.state.messages.firstIndex(where: { $0.id == messageId }) {
                            self.state.messages[idx].read = originalRead
                        }
                        self.state.unreadCount = originalCount
                    } else {
                        self.persistState()
                    }
                }
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    /// Mark all messages as read (optimistic update).
    public func markAllAsRead() {
        let work = { [weak self] in
            guard let self = self, self.initialized, let userId = self.profileId else { return }

            // Snapshot for rollback
            let originalReadStates = self.state.messages.map { ($0.id, $0.read) }
            let originalCount = self.state.unreadCount

            // Optimistic update
            for i in self.state.messages.indices {
                self.state.messages[i].read = true
            }
            self.state.unreadCount = 0

            self.networkService?.inboxMarkAllAsRead(userId: userId) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if case .failure = result {
                        for (id, wasRead) in originalReadStates {
                            if let idx = self.state.messages.firstIndex(where: { $0.id == id }) {
                                self.state.messages[idx].read = wasRead
                            }
                        }
                        self.state.unreadCount = originalCount
                    } else {
                        self.persistState()
                    }
                }
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    /// Delete a message (optimistic update).
    public func deleteMessage(_ messageId: String) {
        let work = { [weak self] in
            guard let self = self, self.initialized, let userId = self.profileId else { return }

            guard let index = self.state.messages.firstIndex(where: { $0.id == messageId }) else { return }

            let removedMessage = self.state.messages[index]
            let originalMessages = self.state.messages
            let originalCount = self.state.unreadCount

            // Optimistic update
            self.state.messages.remove(at: index)
            if !removedMessage.read {
                self.state.unreadCount = max(0, self.state.unreadCount - 1)
            }

            self.networkService?.inboxDeleteMessage(messageId: messageId, userId: userId) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if case .failure = result {
                        self.state.messages = originalMessages
                        self.state.unreadCount = originalCount
                    } else {
                        self.persistState()
                    }
                }
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    /// Track message action (tap/click). Fire-and-forget.
    public func trackAction(_ messageId: String) {
        guard initialized, let userId = profileId else { return }
        networkService?.inboxTrackAction(messageId: messageId, userId: userId) { _ in }
    }

    /// Look up an inbox message by its `inboxMessageId`.
    public func getMessageById(_ inboxMessageId: Int) -> InboxMessage? {
        return state.messages.first { $0.inboxMessageId == inboxMessageId }
    }

    /// Handle silent push sync signal - re-fetch first page + unread count.
    public func handleSyncSignal() {
        guard initialized else { return }
        refresh()
    }

    /// Refresh if cache is stale (> 5 min).
    public func refreshIfStale() {
        if state.isStale {
            refresh()
        }
    }

    // MARK: - Private

    private func persistState() {
        guard let storage = storage else { return }

        // Serialize messages to JSON
        let messageDicts = state.messages.map { $0.toDict() }
        if let data = try? JSONSerialization.data(withJSONObject: messageDicts),
           let jsonString = String(data: data, encoding: .utf8) {
            storage.saveInboxMessages(jsonString)
        }

        storage.saveInboxUnreadCount(state.unreadCount)
        storage.saveInboxNextCursor(state.nextCursor)
        if let lastFetch = state.lastFetchTime {
            storage.saveInboxLastFetch(lastFetch.timeIntervalSince1970)
        }
    }

    private func restoreCachedState() {
        guard let storage = storage else { return }

        guard let messagesJson = storage.getInboxMessages(),
              let data = messagesJson.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }

        let messages = array.compactMap { InboxMessage.from(dict: $0) }
        let unreadCount = storage.getInboxUnreadCount()
        let nextCursor = storage.getInboxNextCursor()
        let lastFetchTs = storage.getInboxLastFetch()

        state = InboxState(
            messages: messages,
            unreadCount: unreadCount,
            nextCursor: nextCursor,
            hasMore: nextCursor != nil,
            lastFetchTime: lastFetchTs.map { Date(timeIntervalSince1970: $0) }
        )
    }

    deinit {
        if let observer = foregroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
