import Foundation

/// An inbox message from the Releva API
public struct InboxMessage: Identifiable {
    public let id: String
    public let title: String
    public let design: [String: Any]
    public var read: Bool
    public let createdAt: Date
    public let inboxMessageId: Int

    public init(
        id: String,
        title: String,
        design: [String: Any],
        read: Bool,
        createdAt: Date,
        inboxMessageId: Int
    ) {
        self.id = id
        self.title = title
        self.design = design
        self.read = read
        self.createdAt = createdAt
        self.inboxMessageId = inboxMessageId
    }

    public static func from(dict: [String: Any]) -> InboxMessage? {
        guard let id = dict["id"] as? String else { return nil }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let createdAt: Date
        if let dateString = dict["createdAt"] as? String {
            createdAt = dateFormatter.date(from: dateString)
                ?? ISO8601DateFormatter().date(from: dateString)
                ?? Date()
        } else {
            createdAt = Date()
        }

        return InboxMessage(
            id: id,
            title: dict["title"] as? String ?? "",
            design: dict["design"] as? [String: Any] ?? [:],
            read: dict["read"] as? Bool ?? false,
            createdAt: createdAt,
            inboxMessageId: (dict["inboxMessageId"] as? NSNumber)?.intValue ?? 0
        )
    }

    /// Serialize to dictionary for cache persistence
    public func toDict() -> [String: Any] {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return [
            "id": id,
            "title": title,
            "design": design,
            "read": read,
            "createdAt": dateFormatter.string(from: createdAt),
            "inboxMessageId": inboxMessageId
        ]
    }
}
