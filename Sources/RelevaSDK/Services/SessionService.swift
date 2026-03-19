import Foundation
import UIKit

/// Tracks device sessions based on app lifecycle events.
///
/// A new session is counted when the app returns to the foreground after being
/// in the background for longer than `debounceThresholdMs` (or on first-ever
/// cold start). Each new session generates a fresh sessionId (UUID) and
/// increments the persistent device session count.
class SessionService {

    static let shared = SessionService()

    private static let debounceThresholdMs = 30_000 // 30 seconds

    private var storage: StorageService?
    private var npsManager: NpsManagerService?
    private var initialized = false
    private var pausedAtMs: Int?

    private init() {}

    func initialize(storage: StorageService, npsManager: NpsManagerService?) {
        if initialized { return }
        self.storage = storage
        self.npsManager = npsManager
        initialized = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        // Cold start = new session
        startNewSession()
    }

    @objc private func appDidEnterBackground() {
        pausedAtMs = Int(Date().timeIntervalSince1970 * 1000)
    }

    @objc private func appDidBecomeActive() {
        guard initialized else { return }
        let now = Int(Date().timeIntervalSince1970 * 1000)
        if let paused = pausedAtMs, (now - paused) > SessionService.debounceThresholdMs {
            startNewSession()
        }
        pausedAtMs = nil
    }

    private func startNewSession() {
        guard let storage = storage else { return }
        let now = Int(Date().timeIntervalSince1970 * 1000)

        // Record first-seen date on first ever session
        if storage.getDeviceFirstSeenAt() == nil {
            let iso = ISO8601DateFormatter().string(from: Date())
            storage.saveDeviceFirstSeenAt(iso)
        }

        // Increment session count
        let count = storage.getDeviceSessionCount()
        storage.saveDeviceSessionCount(count + 1)
        storage.saveDeviceLastSessionTimestamp(now)

        // Generate new session ID
        let sessionId = UUID().uuidString.lowercased()
        storage.saveSession(Session(sessionId: sessionId, timestamp: Date()))

        npsManager?.startNewSession()

        print("RelevaSDK: [SessionService] New session #\(count + 1), id=\(sessionId)")
    }

    /// Returns the current session ID from storage.
    func getSessionId() -> String {
        if let session = storage?.getSession() {
            return session.sessionId
        }
        // Safety fallback
        let sessionId = UUID().uuidString.lowercased()
        storage?.saveSession(Session(sessionId: sessionId, timestamp: Date()))
        return sessionId
    }

    func dispose() {
        NotificationCenter.default.removeObserver(self)
        initialized = false
    }
}
