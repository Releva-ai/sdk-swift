import Foundation

/// Configuration options for the Releva SDK
public struct RelevaConfig {

    // MARK: - Properties

    /// Enable tracking of user interactions and events
    public let enableTracking: Bool

    /// Enable automatic screen view tracking
    public let enableScreenTracking: Bool

    /// Enable push notification handling
    public let enablePushNotifications: Bool

    /// Enable analytics data collection
    public let enableAnalytics: Bool

    /// Enable debug logging
    public let enableDebugLogging: Bool

    /// Custom API endpoint (optional, defaults to realm-based URL)
    public let customEndpoint: String?

    /// Request timeout interval in seconds
    public let requestTimeoutInterval: TimeInterval

    /// Maximum number of retry attempts for failed requests
    public let maxRetryAttempts: Int

    /// Batch size for engagement events
    public let engagementBatchSize: Int

    /// Batch interval for engagement events in seconds
    public let engagementBatchInterval: TimeInterval

    // MARK: - Initializers

    /// Initialize with custom configuration
    public init(
        enableTracking: Bool = true,
        enableScreenTracking: Bool = true,
        enablePushNotifications: Bool = true,
        enableAnalytics: Bool = true,
        enableDebugLogging: Bool = false,
        customEndpoint: String? = nil,
        requestTimeoutInterval: TimeInterval = 30.0,
        maxRetryAttempts: Int = 3,
        engagementBatchSize: Int = 10,
        engagementBatchInterval: TimeInterval = 30.0
    ) {
        self.enableTracking = enableTracking
        self.enableScreenTracking = enableScreenTracking
        self.enablePushNotifications = enablePushNotifications
        self.enableAnalytics = enableAnalytics
        self.enableDebugLogging = enableDebugLogging
        self.customEndpoint = customEndpoint
        self.requestTimeoutInterval = requestTimeoutInterval
        self.maxRetryAttempts = maxRetryAttempts
        self.engagementBatchSize = engagementBatchSize
        self.engagementBatchInterval = engagementBatchInterval
    }

    // MARK: - Preset Configurations

    /// Full configuration with all features enabled (default)
    public static func full() -> RelevaConfig {
        return RelevaConfig(
            enableTracking: true,
            enableScreenTracking: true,
            enablePushNotifications: true,
            enableAnalytics: true
        )
    }

    /// Configuration for tracking only (no push notifications)
    public static func trackingOnly() -> RelevaConfig {
        return RelevaConfig(
            enableTracking: true,
            enableScreenTracking: true,
            enablePushNotifications: false,
            enableAnalytics: true
        )
    }

    /// Configuration for push notifications only (no tracking)
    public static func pushOnly() -> RelevaConfig {
        return RelevaConfig(
            enableTracking: false,
            enableScreenTracking: false,
            enablePushNotifications: true,
            enableAnalytics: false
        )
    }

    /// Minimal configuration with only essential features
    public static func minimal() -> RelevaConfig {
        return RelevaConfig(
            enableTracking: true,
            enableScreenTracking: false,
            enablePushNotifications: true,
            enableAnalytics: false
        )
    }

    /// Debug configuration with logging enabled
    public static func debug() -> RelevaConfig {
        return RelevaConfig(
            enableTracking: true,
            enableScreenTracking: true,
            enablePushNotifications: true,
            enableAnalytics: true,
            enableDebugLogging: true
        )
    }
}

// MARK: - Configuration Validation

extension RelevaConfig {

    /// Validate the configuration
    func validate() throws {
        if requestTimeoutInterval <= 0 {
            throw RelevaError.invalidConfiguration("Request timeout interval must be greater than 0")
        }

        if maxRetryAttempts < 0 {
            throw RelevaError.invalidConfiguration("Max retry attempts cannot be negative")
        }

        if engagementBatchSize <= 0 {
            throw RelevaError.invalidConfiguration("Engagement batch size must be greater than 0")
        }

        if engagementBatchInterval <= 0 {
            throw RelevaError.invalidConfiguration("Engagement batch interval must be greater than 0")
        }
    }
}

// MARK: - Error Types

public enum RelevaError: LocalizedError {
    case invalidConfiguration(String)
    case networkError(String)
    case invalidResponse(String)
    case missingRequiredField(String)
    case unauthorized
    case serverError(Int, String?)
    case unknown(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .invalidResponse(let message):
            return "Invalid response: \(message)"
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
        case .unauthorized:
            return "Unauthorized: Invalid or missing access token"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message ?? "Unknown error")"
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
}