import Foundation

/// Represents the current state of the inbox
public struct InboxState {
    public var messages: [InboxMessage]
    public var unreadCount: Int
    public var nextCursor: String?
    public var isLoading: Bool
    public var hasMore: Bool
    public var lastFetchTime: Date?

    public init(
        messages: [InboxMessage] = [],
        unreadCount: Int = 0,
        nextCursor: String? = nil,
        isLoading: Bool = false,
        hasMore: Bool = false,
        lastFetchTime: Date? = nil
    ) {
        self.messages = messages
        self.unreadCount = unreadCount
        self.nextCursor = nextCursor
        self.isLoading = isLoading
        self.hasMore = hasMore
        self.lastFetchTime = lastFetchTime
    }

    /// Whether the cache is stale (older than 5 minutes)
    public var isStale: Bool {
        guard let lastFetch = lastFetchTime else { return true }
        return Date().timeIntervalSince(lastFetch) > 300
    }
}
