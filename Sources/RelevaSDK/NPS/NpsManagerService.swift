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
/// All public methods are thread-safe. Internal state is serialized on a private queue.
public class NpsManagerService {

    private let queue = DispatchQueue(label: "com.releva.nps-manager")

    private var config: NpsConfig?

    /// True after the survey has been shown or suppressed by a cancel event.
    private var suppressedThisSession = false

    /// True once the delay timer has been started, to prevent double-firing.
    private var triggered = false

    private var delayTimer: Timer?

    /// Called on every push response with the server's NPS config (or nil).
    ///
    /// If the server returned a config, a server-side trigger has already fired.
    /// The SDK will:
    /// - Start the `triggerDelaySeconds` timer immediately if there are no `customEvent` triggers.
    /// - Otherwise hold the config and wait for a matching `trackEvent` call.
    public func initialize(_ config: NpsConfig?) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.config = config

            if self.suppressedThisSession || config == nil { return }
            if self.triggered { return }

            let hasCustomEventTriggers = config!.triggers.contains { $0.type == "customEvent" }

            if !hasCustomEventTriggers {
                self.fireTrigger()
            }
        }
    }

    /// Called by `RelevaClient.trackEvent`. Evaluates `customEvent` triggers and cancel events.
    public func trackEvent(_ eventName: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
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
            guard let self = self else { return }
            self.delayTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(delay), repeats: false) { [weak self] _ in
                self?.queue.async {
                    self?.showNps()
                }
            }
        }
    }

    /// Must be called on `queue`.
    private func showNps() {
        guard !suppressedThisSession, let config = config else { return }
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
            DispatchQueue.main.async {
                self.delayTimer?.invalidate()
                self.delayTimer = nil
            }
        }
    }

}
