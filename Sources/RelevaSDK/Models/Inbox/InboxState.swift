import Foundation

/// Immutable snapshot of the inbox UI state.
/// All mutations return a new copy via `copyWith()`.
public struct InboxState {

    // MARK: - Properties

    /// Currently loaded messages (newest first)
    public let messages: [InboxMessage]

    /// Current unread count (may differ from messages.filter(!isRead).count during optimistic updates)
    public let unreadCount: Int

    /// Opaque cursor for fetching the next page. `nil` means no more pages.
    public let nextCursor: String?

    /// Whether a network request is in flight
    public let isLoading: Bool

    /// Whether there are more pages to load
    public let hasMore: Bool

    /// Timestamp of the last successful fetch. `nil` means never fetched.
    public let lastFetchTime: Date?

    /// Last error encountered (non-blocking; cleared on next successful fetch)
    public let lastError: Error?

    // MARK: - Computed Properties

    /// Returns `true` if cache is stale (>5 minutes old or never fetched)
    public var isStale: Bool {
        guard let lastFetch = lastFetchTime else { return true }
        return Date().timeIntervalSince(lastFetch) > 300 // 5 minutes
    }

    // MARK: - Initializers

    public init(
        messages: [InboxMessage] = [],
        unreadCount: Int = 0,
        nextCursor: String? = nil,
        isLoading: Bool = false,
        hasMore: Bool = false,
        lastFetchTime: Date? = nil,
        lastError: Error? = nil
    ) {
        self.messages = messages
        self.unreadCount = unreadCount
        self.nextCursor = nextCursor
        self.isLoading = isLoading
        self.hasMore = hasMore
        self.lastFetchTime = lastFetchTime
        self.lastError = lastError
    }

    // MARK: - Copy With

    /// Returns a new state with the given fields overridden
    public func copyWith(
        messages: [InboxMessage]? = nil,
        unreadCount: Int? = nil,
        nextCursor: String?? = nil,
        isLoading: Bool? = nil,
        hasMore: Bool? = nil,
        lastFetchTime: Date?? = nil,
        lastError: Error?? = nil
    ) -> InboxState {
        return InboxState(
            messages: messages ?? self.messages,
            unreadCount: unreadCount ?? self.unreadCount,
            nextCursor: nextCursor ?? self.nextCursor,
            isLoading: isLoading ?? self.isLoading,
            hasMore: hasMore ?? self.hasMore,
            lastFetchTime: lastFetchTime ?? self.lastFetchTime,
            lastError: lastError ?? self.lastError
        )
    }

    // MARK: - Static

    /// Empty initial state
    public static let empty = InboxState()
}
