import Foundation

/// Represents a push notification engagement event
public struct EngagementEvent: Codable, Equatable {

    // MARK: - Properties

    /// The type of engagement event
    public let type: EngagementEventType

    /// The callback URL for tracking
    public let callbackUrl: String

    /// The notification ID
    public let notificationId: String?

    /// Timestamp when the event occurred
    public let timestamp: Date

    /// Additional metadata
    public let metadata: [String: String]

    // MARK: - Initializers

    /// Initialize an engagement event
    /// - Parameters:
    ///   - type: The type of engagement event
    ///   - callbackUrl: The callback URL for tracking
    ///   - notificationId: The notification ID (optional)
    ///   - timestamp: When the event occurred (defaults to now)
    ///   - metadata: Additional metadata (optional)
    public init(
        type: EngagementEventType,
        callbackUrl: String,
        notificationId: String? = nil,
        timestamp: Date = Date(),
        metadata: [String: String] = [:]
    ) {
        self.type = type
        self.callbackUrl = callbackUrl
        self.notificationId = notificationId
        self.timestamp = timestamp
        self.metadata = metadata
    }

    // MARK: - Serialization

    /// Convert to dictionary for API requests
    public func toDict() -> [String: Any] {
        var dict: [String: Any] = [
            "type": type.rawValue,
            "callbackUrl": callbackUrl,
            "timestamp": ISO8601DateFormatter().string(from: timestamp)
        ]

        if let notificationId = notificationId {
            dict["notificationId"] = notificationId
        }

        if !metadata.isEmpty {
            dict["metadata"] = metadata
        }

        return dict
    }

    // MARK: - Validation

    /// Validate the engagement event
    /// - Throws: RelevaError if validation fails
    public func validate() throws {
        if callbackUrl.isEmpty {
            throw RelevaError.missingRequiredField("Callback URL cannot be empty")
        }

        // Validate URL format
        guard URL(string: callbackUrl) != nil else {
            throw RelevaError.invalidConfiguration("Invalid callback URL format")
        }
    }

    // MARK: - Computed Properties

    /// Check if the event is expired (older than 7 days)
    public var isExpired: Bool {
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        return timestamp < sevenDaysAgo
    }

    /// Get the age of the event in seconds
    public var ageInSeconds: TimeInterval {
        return Date().timeIntervalSince(timestamp)
    }

    /// Check if the event should be sent immediately (high priority)
    public var shouldSendImmediately: Bool {
        return type == .clicked || type == .opened
    }
}

// MARK: - Batch Processing

extension EngagementEvent {

    /// Group events by callback URL for batch processing
    /// - Parameter events: Array of engagement events
    /// - Returns: Dictionary grouped by callback URL
    public static func groupByCallbackUrl(_ events: [EngagementEvent]) -> [String: [EngagementEvent]] {
        return Dictionary(grouping: events) { $0.callbackUrl }
    }

    /// Filter out expired events
    /// - Parameter events: Array of engagement events
    /// - Returns: Array of non-expired events
    public static func filterExpired(_ events: [EngagementEvent]) -> [EngagementEvent] {
        return events.filter { !$0.isExpired }
    }

    /// Sort events by priority and timestamp
    /// - Parameter events: Array of engagement events
    /// - Returns: Sorted array of events
    public static func sortByPriority(_ events: [EngagementEvent]) -> [EngagementEvent] {
        return events.sorted { lhs, rhs in
            // First sort by priority
            if lhs.type.priority != rhs.type.priority {
                return lhs.type.priority > rhs.type.priority
            }
            // Then by timestamp (older first)
            return lhs.timestamp < rhs.timestamp
        }
    }
}

// MARK: - Persistence

extension EngagementEvent {

    /// Create from notification payload
    /// - Parameter userInfo: The notification payload
    /// - Returns: An engagement event if the payload is valid
    public static func fromNotificationPayload(_ userInfo: [AnyHashable: Any]) -> EngagementEvent? {
        // Firebase iOS puts custom data at root level, not in "data" wrapper
        // Try to extract data from either format
        var data: [String: Any]? = nil

        // Check "data" wrapper first (cross-platform format)
        if let wrappedData = userInfo["data"] as? [String: Any] {
            data = wrappedData
        } else {
            // iOS format - convert root level to String dictionary
            var rootData: [String: Any] = [:]
            for (key, value) in userInfo {
                if let stringKey = key as? String, stringKey != "aps" {
                    rootData[stringKey] = value
                }
            }
            data = rootData.isEmpty ? nil : rootData
        }

        guard let data = data,
              let callbackUrl = data["callbackUrl"] as? String else {
            return nil
        }

        let notificationId = data["notificationId"] as? String

        // Extract any additional metadata
        var metadata: [String: String] = [:]
        if let target = data["target"] as? String {
            metadata["target"] = target
        }
        if let screen = data["navigate_to_screen"] as? String {
            metadata["screen"] = screen
        }
        if let url = data["navigate_to_url"] as? String {
            metadata["url"] = url
        }

        return EngagementEvent(
            type: .delivered,
            callbackUrl: callbackUrl,
            notificationId: notificationId,
            metadata: metadata
        )
    }
}