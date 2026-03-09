import Foundation

/// Represents a single App Inbox message delivery record.
/// Each record is a fully-resolved snapshot — merge tags have already been applied server-side.
public struct InboxMessage: Codable, Identifiable, Equatable {

    // MARK: - Properties

    /// UUID of the delivery record (used for API operations like mark-read, delete)
    public let id: String

    /// Message title
    public let title: String

    /// Optional preview text / subtitle
    public let previewText: String?

    /// Optional image URL for the message thumbnail
    public let imageUrl: String?

    /// Whether the message has been read (mutable for optimistic updates)
    public var isRead: Bool

    /// Delivery timestamp
    public let createdAt: Date

    /// Source template ID (not the delivery UUID)
    public let inboxMessageId: String

    /// Optional HTML body content
    public let htmlBody: String?

    /// Optional action URL (deep link or external URL)
    public let actionUrl: String?

    /// Optional action label for CTA button
    public let actionLabel: String?

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case previewText
        case imageUrl
        case isRead = "read"
        case createdAt
        case inboxMessageId
        case htmlBody
        case actionUrl
        case actionLabel
    }

    // MARK: - Initializers

    public init(
        id: String,
        title: String,
        previewText: String? = nil,
        imageUrl: String? = nil,
        isRead: Bool = false,
        createdAt: Date = Date(),
        inboxMessageId: String,
        htmlBody: String? = nil,
        actionUrl: String? = nil,
        actionLabel: String? = nil
    ) {
        self.id = id
        self.title = title
        self.previewText = previewText
        self.imageUrl = imageUrl
        self.isRead = isRead
        self.createdAt = createdAt
        self.inboxMessageId = inboxMessageId
        self.htmlBody = htmlBody
        self.actionUrl = actionUrl
        self.actionLabel = actionLabel
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        previewText = try container.decodeIfPresent(String.self, forKey: .previewText)
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        isRead = try container.decodeIfPresent(Bool.self, forKey: .isRead) ?? false
        inboxMessageId = try container.decode(String.self, forKey: .inboxMessageId)
        htmlBody = try container.decodeIfPresent(String.self, forKey: .htmlBody)
        actionUrl = try container.decodeIfPresent(String.self, forKey: .actionUrl)
        actionLabel = try container.decodeIfPresent(String.self, forKey: .actionLabel)

        // Parse createdAt — accept ISO8601 string or epoch milliseconds
        if let dateString = try? container.decode(String.self, forKey: .createdAt) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) {
                createdAt = date
            } else {
                // Fallback: try without fractional seconds
                let fallback = ISO8601DateFormatter()
                createdAt = fallback.date(from: dateString) ?? Date()
            }
        } else if let epochMs = try? container.decode(Double.self, forKey: .createdAt) {
            createdAt = Date(timeIntervalSince1970: epochMs / 1000.0)
        } else {
            createdAt = Date()
        }
    }

    // MARK: - Equatable

    public static func == (lhs: InboxMessage, rhs: InboxMessage) -> Bool {
        return lhs.id == rhs.id &&
               lhs.isRead == rhs.isRead &&
               lhs.title == rhs.title
    }
}

// MARK: - List Response

/// Paginated response for inbox messages list
public struct InboxMessagesResponse: Codable {
    public let messages: [InboxMessage]
    public let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case messages
        case nextCursor
    }
}

/// Unread count response
public struct InboxUnreadCountResponse: Codable {
    public let count: Int
}
