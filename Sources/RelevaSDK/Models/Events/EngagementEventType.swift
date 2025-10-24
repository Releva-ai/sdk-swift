import Foundation

/// Types of engagement events for push notifications
public enum EngagementEventType: String, CaseIterable, Codable {

    /// Notification was delivered to the device
    case delivered = "delivered"

    /// Notification was opened by the user
    case opened = "opened"

    /// Notification action button was clicked
    case clicked = "clicked"

    // MARK: - Properties

    /// Human-readable description of the event type
    public var description: String {
        switch self {
        case .delivered:
            return "Notification Delivered"
        case .opened:
            return "Notification Opened"
        case .clicked:
            return "Notification Action Clicked"
        }
    }

    /// Priority for event processing (higher = more important)
    public var priority: Int {
        switch self {
        case .clicked:
            return 3
        case .opened:
            return 2
        case .delivered:
            return 1
        }
    }
}