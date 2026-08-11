import Foundation

/// An inbox message from the Releva API
public struct InboxMessage: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let design: [String: JSONValue]
    public var read: Bool
    public let createdAt: Date
    public let inboxMessageId: Int

    public init(
        id: String,
        title: String,
        design: [String: JSONValue],
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

    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let fallbackDateFormatter = ISO8601DateFormatter()

    public static func from(dict: [String: Any]) -> InboxMessage? {
        guard let id = dict["id"] as? String else { return nil }

        let createdAt: Date
        if let dateString = dict["createdAt"] as? String {
            createdAt = dateFormatter.date(from: dateString)
                ?? fallbackDateFormatter.date(from: dateString)
                ?? Date()
        } else {
            createdAt = Date()
        }

        return InboxMessage(
            id: id,
            title: dict["title"] as? String ?? "",
            design: (dict["design"] as? [String: Any]).map { [String: JSONValue](any: $0) } ?? [:],
            read: dict["read"] as? Bool ?? false,
            createdAt: createdAt,
            inboxMessageId: (dict["inboxMessageId"] as? NSNumber)?.intValue ?? 0
        )
    }

    /// Serialize to dictionary for cache persistence
    public func toDict() -> [String: Any] {
        return [
            "id": id,
            "title": title,
            "design": design.anyValue,
            "read": read,
            "createdAt": InboxMessage.dateFormatter.string(from: createdAt),
            "inboxMessageId": inboxMessageId
        ]
    }
}
