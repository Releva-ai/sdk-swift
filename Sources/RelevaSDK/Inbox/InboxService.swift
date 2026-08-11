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

    // Every mutating method below runs its whole body in a `Task { @MainActor ... }`. That
    // replaces the `if Thread.isMainThread { work() } else { DispatchQueue.main.async(...) }`
    // hop each one used to open with, and the `DispatchQueue.main.async` each network callback
    // used to close with: `state` is `@Published` and read by SwiftUI, so it may only be
    // touched on the main actor, and now the compiler is the thing enforcing that.
    //
    // One behaviour change falls out of it: when called *from* the main thread the optimistic
    // update used to apply synchronously, before the call returned. It now lands on the next
    // main-actor turn instead. Nothing in the SDK reads `state` synchronously after calling
    // these, and SwiftUI observers see the same values either way.

    /// Fetch first page of messages + unread count in parallel.
    public func refresh() {
        Task { @MainActor [weak self] in
            guard let self = self, self.initialized,
                  let userId = self.profileId,
                  let network = self.networkService else { return }

            self.state.isLoading = true

            // `async let` keeps the two requests in flight together, as the `DispatchGroup` did.
            async let messagesJson = network.fetchInboxMessages(userId: userId)
            async let unreadCount = network.fetchInboxUnreadCount(userId: userId)

            let json = try? await messagesJson
            let unread = try? await unreadCount

            if let json = json {
                let messagesArray = (json["messages"] as? [[String: Any]]) ?? []
                let nextCursor = json["nextCursor"] as? String
                self.state.messages = messagesArray.compactMap { InboxMessage.from(dict: $0) }
                self.state.nextCursor = nextCursor
                self.state.hasMore = nextCursor != nil
                self.state.lastFetchTime = Date()
            }
            if let unread = unread {
                self.state.unreadCount = unread
            }
            self.state.isLoading = false
            self.persistState()
        }
    }

    /// Fetch next page using nextCursor and append to list.
    public func loadMore() {
        Task { @MainActor [weak self] in
            guard let self = self, self.initialized, !self.state.isLoading, self.state.hasMore,
                  let userId = self.profileId,
                  let network = self.networkService else { return }

            self.state.isLoading = true

            guard let json = try? await network.fetchInboxMessages(
                userId: userId,
                cursor: self.state.nextCursor
            ) else {
                self.state.isLoading = false
                return
            }

            let messagesArray = (json["messages"] as? [[String: Any]]) ?? []
            let newMessages = messagesArray.compactMap { InboxMessage.from(dict: $0) }
            let nextCursor = json["nextCursor"] as? String

            self.state.messages.append(contentsOf: newMessages)
            self.state.nextCursor = nextCursor
            self.state.hasMore = nextCursor != nil
            self.state.lastFetchTime = Date()
            self.state.isLoading = false
            self.persistState()
        }
    }

    /// Mark single message as read (optimistic update).
    public func markAsRead(_ messageId: String) {
        Task { @MainActor [weak self] in
            guard let self = self, self.initialized,
                  let userId = self.profileId,
                  let network = self.networkService else { return }

            guard let index = self.state.messages.firstIndex(where: { $0.id == messageId }) else { return }
            if self.state.messages[index].read { return }

            // Snapshot for rollback
            let originalRead = self.state.messages[index].read
            let originalCount = self.state.unreadCount

            // Optimistic update
            self.state.messages[index].read = true
            self.state.unreadCount = max(0, self.state.unreadCount - 1)

            do {
                try await network.inboxMarkAsRead(messageId: messageId, userId: userId)
                self.persistState()
            } catch {
                if let idx = self.state.messages.firstIndex(where: { $0.id == messageId }) {
                    self.state.messages[idx].read = originalRead
                }
                self.state.unreadCount = originalCount
            }
        }
    }

    /// Mark all messages as read (optimistic update).
    public func markAllAsRead() {
        Task { @MainActor [weak self] in
            guard let self = self, self.initialized,
                  let userId = self.profileId,
                  let network = self.networkService else { return }

            // Snapshot for rollback
            let originalReadStates = self.state.messages.map { ($0.id, $0.read) }
            let originalCount = self.state.unreadCount

            // Optimistic update
            for i in self.state.messages.indices {
                self.state.messages[i].read = true
            }
            self.state.unreadCount = 0

            do {
                try await network.inboxMarkAllAsRead(userId: userId)
                self.persistState()
            } catch {
                for (id, wasRead) in originalReadStates {
                    if let idx = self.state.messages.firstIndex(where: { $0.id == id }) {
                        self.state.messages[idx].read = wasRead
                    }
                }
                self.state.unreadCount = originalCount
            }
        }
    }

    /// Delete a message (optimistic update).
    public func deleteMessage(_ messageId: String) {
        Task { @MainActor [weak self] in
            guard let self = self, self.initialized,
                  let userId = self.profileId,
                  let network = self.networkService else { return }

            guard let index = self.state.messages.firstIndex(where: { $0.id == messageId }) else { return }

            let removedMessage = self.state.messages[index]
            let originalMessages = self.state.messages
            let originalCount = self.state.unreadCount

            // Optimistic update
            self.state.messages.remove(at: index)
            if !removedMessage.read {
                self.state.unreadCount = max(0, self.state.unreadCount - 1)
            }

            do {
                try await network.inboxDeleteMessage(messageId: messageId, userId: userId)
                self.persistState()
            } catch {
                self.state.messages = originalMessages
                self.state.unreadCount = originalCount
            }
        }
    }

    /// Track message action (tap/click). Fire-and-forget.
    public func trackAction(_ messageId: String) {
        Task { @MainActor [weak self] in
            guard let self = self, self.initialized,
                  let userId = self.profileId,
                  let network = self.networkService else { return }
            try? await network.inboxTrackAction(messageId: messageId, userId: userId)
        }
    }

    /// Look up an inbox message by its `inboxMessageId`.
    public func getMessageById(_ inboxMessageId: Int) -> InboxMessage? {
        state.messages.first { $0.inboxMessageId == inboxMessageId }
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
