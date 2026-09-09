import Foundation

/// Manages NPS display timing and custom-event trigger evaluation.
///
/// **Trigger responsibility split:**
/// - `appOpen`, `sessionCount`, and `screenView` triggers are evaluated server-side.
///   If the server returned an `nps` field in the push response, a server-side trigger has already fired.
/// - `customEvent` triggers remain SDK-side: the SDK holds the config and waits for a matching
///   `trackEvent` call before starting the delay timer.
///
/// **Session-scoped suppression:** once the survey is shown or cancelled via a cancel event,
/// it will not show again until `startNewSession()` is called.
///
/// All public methods are thread-safe. Internal state is serialized on `queue`.
public class NpsManagerService {
    /// Serializes the state below.
    private let queue = DispatchQueue(label: "com.releva.nps-manager")

    private var config: NpsConfig?

    /// True after the survey has been shown or suppressed by a cancel event.
    private var suppressedThisSession = false

    /// True once the delay timer has been started, to prevent double-firing.
    private var triggered = false

    private var delayTimer: Timer?

    /// Set by `dispose()`. Checked at the top of every method that can queue work, so a call
    /// already in flight when `shutdown()` runs — or queued behind it — cannot arm a timer or
    /// show a survey afterwards; invalidating `delayTimer` alone only stops a timer that had
    /// already been scheduled.
    private var disposed = false

    /// Called on every push response with the server's NPS config (or nil).
    ///
    /// If the server returned a config, a server-side trigger has already fired.
    /// The SDK will:
    /// - Start the `triggerDelaySeconds` timer immediately if there are no `customEvent` triggers.
    /// - Otherwise hold the config and wait for a matching `trackEvent` call.
    ///
    /// - Parameter clearsWhenAbsent: `true` for a push that named a page (`trackScreenView` and
    ///   friends): `nps: null` there means "this screen has no survey", so a held config must be
    ///   dropped or it can fire on a screen the admin never targeted. `false` (the default) for a
    ///   push with no page context (a cart/wishlist sync, a bare custom event): there `nps: null`
    ///   only means "this request doesn't carry page-level targeting", and an armed
    ///   `customEvent` trigger or its cancel event must survive it. The web SDK ignores a null
    ///   NPS field the same way for that case; only `startNewSession` forgets a config other than
    ///   through this path.
    public func initialize(_ config: NpsConfig?, clearsWhenAbsent: Bool = false) {
        queue.async { [weak self] in
            guard let self = self, !self.disposed else { return }
            guard let config = config else {
                if clearsWhenAbsent { self.config = nil }
                return
            }
            self.config = config

            guard !self.suppressedThisSession else { return }
            if self.triggered { return }

            let hasCustomEventTriggers = config.triggers.contains { $0.type == "customEvent" }

            if !hasCustomEventTriggers {
                self.fireTrigger()
            }
        }
    }

    /// Called by `RelevaClient.trackEvent`. Evaluates `customEvent` triggers and cancel events.
    public func trackEvent(_ eventName: String) {
        queue.async { [weak self] in
            guard let self = self, !self.disposed else { return }
            guard let config = self.config, !self.suppressedThisSession else { return }

            // Cancel events take priority
            if config.cancelOnEvents.contains(eventName) {
                DispatchQueue.main.async { [weak self] in
                    self?.delayTimer?.invalidate()
                    self?.delayTimer = nil
                }
                self.suppressedThisSession = true
                return
            }

            if self.triggered { return }

            for trigger in config.triggers {
                if trigger.type == "customEvent" && trigger.eventName == eventName {
                    self.fireTrigger()
                    return
                }
            }
        }
    }

    /// Must be called on `queue`.
    private func fireTrigger() {
        triggered = true
        let delay = config?.triggerDelaySeconds ?? 0

        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.disposed else { return }
            self.delayTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(delay), repeats: false) { [weak self] _ in
                self?.queue.async {
                    self?.showNps()
                }
            }
        }
    }

    /// Must be called on `queue`.
    private func showNps() {
        guard !disposed, !suppressedThisSession, let config = config else { return }
        suppressedThisSession = true
        DispatchQueue.main.async {
            NpsDisplayController.shared.showNps(config)
        }
    }

    /// Reset session-level state when a new NPS session begins.
    public func startNewSession() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.config = nil
            self.suppressedThisSession = false
            self.triggered = false
            DispatchQueue.main.async { [weak self] in
                self?.delayTimer?.invalidate()
                self?.delayTimer = nil
            }
        }
    }

    public func dispose() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.disposed = true
            self.config = nil
            DispatchQueue.main.async {
                self.delayTimer?.invalidate()
                self.delayTimer = nil
            }
        }
    }

    /// Calls back once everything already enqueued on `queue` has drained. Test seam
    /// only: lets tests order themselves after `initialize` / `trackEvent`'s work
    /// without sleeping, while keeping `queue` itself private so nothing in the module
    /// can enqueue arbitrary work onto it and no caller can violate the `/// Must be
    /// called on queue` contract the private methods above rely on.
    func drainPendingWork(_ completion: @escaping @Sendable () -> Void) {
        queue.async { completion() }
    }
}
