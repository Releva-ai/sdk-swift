import Foundation

/// Manages user session with 24-hour expiration
public class Session {

    // MARK: - Properties

    /// Session ID
    public private(set) var sessionId: String

    /// Session creation timestamp
    public private(set) var timestamp: Date

    /// Session expiration duration (24 hours)
    private static let expirationInterval: TimeInterval = 24 * 60 * 60

    // MARK: - Initializers

    /// Initialize a new session
    public init() {
        self.sessionId = Session.generateSessionId()
        self.timestamp = Date()
    }

    /// Initialize with existing session data
    /// - Parameters:
    ///   - sessionId: Existing session ID
    ///   - timestamp: Session creation timestamp
    public init(sessionId: String, timestamp: Date) {
        self.sessionId = sessionId
        self.timestamp = timestamp
    }

    // MARK: - Public Methods

    /// Check if the session is expired
    /// - Returns: True if session is older than 24 hours
    public func isExpired() -> Bool {
        let age = Date().timeIntervalSince(timestamp)
        return age > Session.expirationInterval
    }

    /// Refresh the session if expired
    /// - Returns: True if session was refreshed
    @discardableResult
    public func refreshIfNeeded() -> Bool {
        if isExpired() {
            sessionId = Session.generateSessionId()
            timestamp = Date()
            return true
        }
        return false
    }

    /// Force refresh the session
    public func forceRefresh() {
        sessionId = Session.generateSessionId()
        timestamp = Date()
    }

    /// Get the age of the session in seconds
    /// - Returns: Session age in seconds
    public func ageInSeconds() -> TimeInterval {
        return Date().timeIntervalSince(timestamp)
    }

    /// Get the age of the session in hours
    /// - Returns: Session age in hours
    public func ageInHours() -> Double {
        return ageInSeconds() / 3600
    }

    /// Get remaining time until expiration
    /// - Returns: Remaining time in seconds, or 0 if expired
    public func remainingTime() -> TimeInterval {
        let age = ageInSeconds()
        let remaining = Session.expirationInterval - age
        return max(0, remaining)
    }

    /// Get remaining time as a readable string
    /// - Returns: Human-readable remaining time
    public func remainingTimeString() -> String {
        let remaining = remainingTime()
        if remaining <= 0 {
            return "Expired"
        }

        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    // MARK: - Static Methods

    /// Generate a new session ID
    /// - Returns: UUID-based session ID
    private static func generateSessionId() -> String {
        return UUID().uuidString.lowercased()
    }

    /// Create or restore a session from storage
    /// - Parameter storage: Storage service to use
    /// - Returns: Session instance (new or restored)
    public static func createOrRestore(from storage: StorageService) -> Session {
        if let storedSession = storage.getSession() {
            if !storedSession.isExpired() {
                return storedSession
            }
        }

        // Create new session if none exists or expired
        let newSession = Session()
        storage.saveSession(newSession)
        return newSession
    }

    // MARK: - Codable

    /// Convert to dictionary for storage
    public func toDict() -> [String: Any] {
        return [
            "sessionId": sessionId,
            "timestamp": timestamp.timeIntervalSince1970
        ]
    }

    /// Create from dictionary
    /// - Parameter dict: Dictionary containing session data
    /// - Returns: Session instance or nil if invalid
    public static func from(dict: [String: Any]) -> Session? {
        guard let sessionId = dict["sessionId"] as? String,
              let timestampInterval = dict["timestamp"] as? TimeInterval else {
            return nil
        }

        let timestamp = Date(timeIntervalSince1970: timestampInterval)
        return Session(sessionId: sessionId, timestamp: timestamp)
    }
}

// MARK: - Equatable

extension Session: Equatable {
    public static func == (lhs: Session, rhs: Session) -> Bool {
        return lhs.sessionId == rhs.sessionId
    }
}

// MARK: - CustomStringConvertible

extension Session: CustomStringConvertible {
    public var description: String {
        return "Session(id: \(sessionId), age: \(ageInHours())h, expired: \(isExpired()))"
    }
}

// MARK: - Session Manager

/// Manages session lifecycle and persistence
public class SessionManager {

    // MARK: - Properties

    /// Current session
    private var currentSession: Session?

    /// Storage service
    private let storage: StorageService

    /// Session change callback
    public var onSessionChanged: ((Session) -> Void)?

    // MARK: - Initializers

    /// Initialize with storage service
    /// - Parameter storage: Storage service for persistence
    public init(storage: StorageService) {
        self.storage = storage
    }

    // MARK: - Public Methods

    /// Get or create the current session
    /// - Returns: Current session (creates new if needed)
    public func getCurrentSession() -> Session {
        if let session = currentSession {
            if !session.isExpired() {
                return session
            }
        }

        // Create or restore session
        let session = Session.createOrRestore(from: storage)
        currentSession = session
        onSessionChanged?(session)
        return session
    }

    /// Refresh session if needed
    /// - Returns: True if session was refreshed
    @discardableResult
    public func refreshIfNeeded() -> Bool {
        let session = getCurrentSession()
        if session.refreshIfNeeded() {
            storage.saveSession(session)
            onSessionChanged?(session)
            return true
        }
        return false
    }

    /// Force refresh the session
    public func forceRefresh() {
        let session = Session()
        currentSession = session
        storage.saveSession(session)
        onSessionChanged?(session)
    }

    /// Clear the session
    public func clearSession() {
        currentSession = nil
        storage.clearSession()
    }

    /// Get session age in hours
    /// - Returns: Session age or nil if no session
    public func getSessionAge() -> Double? {
        return currentSession?.ageInHours()
    }

    /// Check if session is expired
    /// - Returns: True if expired or no session exists
    public func isSessionExpired() -> Bool {
        return currentSession?.isExpired() ?? true
    }
}