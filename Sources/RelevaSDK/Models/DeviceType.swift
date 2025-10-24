import Foundation

/// Types of mobile devices for push notification registration
public enum DeviceType: String, CaseIterable, Codable {

    /// Android device
    case android = "android"

    /// iOS device
    case ios = "ios"

    /// Huawei device
    case huawei = "huawei"

    /// Other device type
    case other = "other"

    // MARK: - Properties

    /// Human-readable description
    public var description: String {
        switch self {
        case .android:
            return "Android Device"
        case .ios:
            return "iOS Device"
        case .huawei:
            return "Huawei Device"
        case .other:
            return "Other Device"
        }
    }

    /// Check if this is an Apple device
    public var isAppleDevice: Bool {
        return self == .ios
    }

    /// Check if this device type supports Firebase
    public var supportsFirebase: Bool {
        switch self {
        case .android, .ios:
            return true
        case .huawei, .other:
            return false
        }
    }

    /// Get the push notification service type
    public var pushService: String {
        switch self {
        case .android:
            return "FCM"
        case .ios:
            return "APNS"
        case .huawei:
            return "HMS"
        case .other:
            return "Unknown"
        }
    }

    // MARK: - Static Methods

    /// Get the current device type
    /// - Returns: The device type for the current platform
    public static var current: DeviceType {
        #if os(iOS)
        return .ios
        #elseif os(tvOS)
        return .ios
        #elseif os(watchOS)
        return .ios
        #else
        return .other
        #endif
    }

    /// Detect device type from user agent or platform string
    /// - Parameter platformString: The platform identifier string
    /// - Returns: The detected device type
    public static func from(platformString: String) -> DeviceType {
        let lowercased = platformString.lowercased()

        if lowercased.contains("ios") || lowercased.contains("iphone") || lowercased.contains("ipad") {
            return .ios
        } else if lowercased.contains("android") {
            return .android
        } else if lowercased.contains("huawei") || lowercased.contains("harmony") {
            return .huawei
        } else {
            return .other
        }
    }
}