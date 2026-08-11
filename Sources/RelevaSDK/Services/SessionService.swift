import Foundation
import UIKit

/// Tracks device sessions based on app lifecycle events.
///
/// A new session is counted when the app returns to the foreground after being
/// in the background for longer than `debounceThresholdMs` (or on first-ever
/// cold start). Each new session generates a fresh sessionId (UUID) and
/// increments the persistent device session count.
///
/// All methods must be called on the main thread. UIApplication lifecycle
/// notifications are always delivered on the main thread, and SDK callers
/// are expected to invoke this service from the main thread as well.
@MainActor
class SessionService {
    static let shared = SessionService()

    /// Minimum background duration (ms) before a new session is counted.
    /// In DEBUG builds this is a `var` so unit tests can override it without sleeping.
    #if DEBUG
    static var debounceThresholdMs = 30 * 60 * 1000 // 30 minutes
    #else
    static let debounceThresholdMs = 30 * 60 * 1000 // 30 minutes
    #endif
    private static let isoFormatter = ISO8601DateFormatter()

    private var storage: StorageService?
    private var npsManager: NpsManagerService?
    private var initialized = false
    private var pausedAtMs: Int?

    /// Stable session ID used before `initialize()` is called, so all pre-init
    /// callers (bannerImpression, bannerAction, etc.) share the same ID.
    private var fallbackSessionId: String?

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
            let iso = SessionService.isoFormatter.string(from: Date())
            storage.saveDeviceFirstSeenAt(iso)
        }

        // Increment session count
        let count = storage.getDeviceSessionCount()
        storage.saveDeviceSessionCount(count + 1)
        storage.saveDeviceLastSessionTimestamp(now)

        // Generate new session ID and clear any pre-init fallback
        let sessionId = UUID().uuidString.lowercased()
        fallbackSessionId = nil
        storage.saveSession(Session(sessionId: sessionId, timestamp: Date()))

        npsManager?.startNewSession()
    }

    /// Returns the current session ID from storage.
    func getSessionId() -> String {
        if let session = storage?.getSession() {
            return session.sessionId
        }
        // Safety fallback: return a stable ID until initialize() is called so that
        // all pre-init callers (bannerImpression, bannerAction, etc.) share the same ID.
        if let existing = fallbackSessionId {
            return existing
        }
        let sessionId = UUID().uuidString.lowercased()
        fallbackSessionId = sessionId
        return sessionId
    }

    func dispose() {
        // Name-scoped removals mirroring the two addObserver registrations in
        // initialize(), rather than the bare removeObserver(self) form: this is a
        // singleton (private init() + static let shared) so deinit never runs and
        // dispose() is the only teardown path, but the bare form would also detach
        // any observation this type didn't register. There are only ever these two.
        NotificationCenter.default.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
        initialized = false
        storage = nil
        npsManager = nil
        fallbackSessionId = nil
    }
}
