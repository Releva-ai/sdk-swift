import Foundation

/// Service for tracking push notification engagement events with batching
public class EngagementTrackingService {
    // MARK: - Properties

    /// Storage service
    private let storage: StorageService

    /// Network service
    private let networkService: NetworkService

    /// Configuration
    private let config: RelevaConfig

    /// Timer for batch processing
    private var batchTimer: Timer?

    /// Queue for thread safety
    private let queue = DispatchQueue(label: "com.releva.engagement", qos: .background)

    /// Pending events to send
    private var pendingEvents: [EngagementEvent] = []

    /// Is currently sending events
    private var isSending = false

    // MARK: - Initializers

    /// Initialize engagement tracking service
    /// - Parameters:
    ///   - storage: Storage service
    ///   - networkService: Network service
    ///   - config: SDK configuration
    public init(storage: StorageService, networkService: NetworkService, config: RelevaConfig) {
        self.storage = storage
        self.networkService = networkService
        self.config = config

        // Load any pending events from storage
        loadPendingEvents()
    }

    // `deinit` deliberately does *not* call `stopTracking()`. That reaches `processBatch()`,
    // which does `queue.async { self… }` — escaping `self` out of an object whose `deinit` is
    // already running. Swift does not resurrect, so the memory is freed the moment `deinit`
    // returns and the `.background` queue then dereferences it. Nothing in the SDK ever
    // released this service (`RelevaClient` holds one for the process lifetime), so the
    // use-after-free was unreachable until `EngagementTrackingServiceTests` started building
    // and dropping one per test — at which point it crashed the test bundle.
    //
    // No pending event is lost by not flushing here: `trackEvent(_:)` persists each event
    // through `storage.addPendingEngagementEvent(_:)` as it arrives, and `init` reloads them.
    //
    // Invalidating the timer is all that remains, and in practice it is already `nil`: a
    // scheduled `Timer` retains `self` through its closure, so reaching `deinit` at all means
    // `stopTracking()` has run.
    deinit {
        batchTimer?.invalidate()
    }

    // MARK: - Public Methods

    /// Start tracking engagement events
    public func startTracking() {
        stopTracking() // Stop any existing timer

        // Start batch timer
        batchTimer = Timer.scheduledTimer(withTimeInterval: config.engagementBatchInterval, repeats: true) { _ in
            self.processBatch()
        }

        if config.enableDebugLogging {
            print("RelevaSDK: Engagement tracking started (batch interval: \(config.engagementBatchInterval)s)")
        }
    }

    /// Stop tracking engagement events
    public func stopTracking() {
        batchTimer?.invalidate()
        batchTimer = nil

        // Process any remaining events
        processBatch()

        if config.enableDebugLogging {
            print("RelevaSDK: Engagement tracking stopped")
        }
    }

    /// Track an engagement event
    /// - Parameter event: Engagement event to track
    public func trackEvent(_ event: EngagementEvent) {
        queue.async {
            // Validate event
            do {
                try event.validate()
            } catch {
                if self.config.enableDebugLogging {
                    print("RelevaSDK: Invalid engagement event: \(error)")
                }
                return
            }

            // Add to pending events
            self.pendingEvents.append(event)
            self.storage.addPendingEngagementEvent(event)

            if self.config.enableDebugLogging {
                print("RelevaSDK: Tracked engagement event: \(event.type.rawValue)")
            }

            // Send immediately for high-priority events
            if event.shouldSendImmediately {
                self.processBatch()
            } else if self.pendingEvents.count >= self.config.engagementBatchSize {
                // Send if batch size reached
                self.processBatch()
            }
        }
    }

    /// Track delivered event
    /// - Parameter userInfo: Notification payload
    public func trackDelivered(userInfo: [AnyHashable: Any]) {
        if let event = EngagementEvent.fromNotificationPayload(userInfo) {
            let deliveredEvent = EngagementEvent(
                type: .delivered,
                callbackUrl: event.callbackUrl,
                notificationId: event.notificationId,
                metadata: event.metadata
            )
            trackEvent(deliveredEvent)
        }
    }

    /// Track opened event
    /// - Parameter userInfo: Notification payload
    public func trackOpened(userInfo: [AnyHashable: Any]) {
        if let event = EngagementEvent.fromNotificationPayload(userInfo) {
            let openedEvent = EngagementEvent(
                type: .opened,
                callbackUrl: event.callbackUrl,
                notificationId: event.notificationId,
                metadata: event.metadata
            )
            trackEvent(openedEvent)
        }
    }

    /// Track clicked event
    /// - Parameters:
    ///   - userInfo: Notification payload
    ///   - actionIdentifier: Action button identifier
    public func trackClicked(userInfo: [AnyHashable: Any], actionIdentifier: String? = nil) {
        if let event = EngagementEvent.fromNotificationPayload(userInfo) {
            var metadata = event.metadata
            if let action = actionIdentifier {
                metadata["action"] = action
            }

            let clickedEvent = EngagementEvent(
                type: .clicked,
                callbackUrl: event.callbackUrl,
                notificationId: event.notificationId,
                metadata: metadata
            )
            trackEvent(clickedEvent)
        }
    }

    /// Force process pending events
    public func flush() {
        processBatch()
    }

    // MARK: - Private Methods

    /// Load pending events from storage
    private func loadPendingEvents() {
        queue.async {
            self.pendingEvents = self.storage.getPendingEngagementEvents()

            if !self.pendingEvents.isEmpty && self.config.enableDebugLogging {
                print("RelevaSDK: Loaded \(self.pendingEvents.count) pending engagement events")
            }

            // Remove expired events
            self.pendingEvents = EngagementEvent.filterExpired(self.pendingEvents)
        }
    }

    /// Process batch of events
    private func processBatch() {
        queue.async {
            guard !self.pendingEvents.isEmpty, !self.isSending else { return }

            self.isSending = true

            // Get events to send (up to batch size)
            let eventsToSend = Array(self.pendingEvents.prefix(self.config.engagementBatchSize))

            if self.config.enableDebugLogging {
                print("RelevaSDK: Sending \(eventsToSend.count) engagement events")
            }

            // Send events. The unstructured `Task` is the bridge from this serial queue into
            // the async fan-out; the state it touches afterwards is hopped back onto the queue
            // by `finishBatch`, so `pendingEvents` and `isSending` stay queue-confined.
            Task {
                do {
                    try await self.networkService.sendEngagementEvents(eventsToSend)
                    if self.config.enableDebugLogging {
                        print("RelevaSDK: Successfully sent \(eventsToSend.count) engagement events")
                    }
                    self.finishBatch(eventsToSend, delivered: true)
                } catch {
                    if self.config.enableDebugLogging {
                        print("RelevaSDK: Failed to send engagement events: \(error)")
                    }
                    // Events will be retried in next batch
                    self.finishBatch(eventsToSend, delivered: false)
                }
            }
        }
    }

    /// Settle a batch back on `queue`: clear the in-flight flag, drop the events if they
    /// were delivered, and persist whatever is left.
    private func finishBatch(_ eventsToSend: [EngagementEvent], delivered: Bool) {
        queue.async {
            self.isSending = false

            if delivered {
                self.pendingEvents.removeAll { event in
                    eventsToSend.contains { $0.notificationId == event.notificationId }
                }
                self.storage.removePendingEngagementEvents(eventsToSend)
            }

            // Save updated pending events
            self.storage.savePendingEngagementEvents(self.pendingEvents)
        }
    }

    /// Clear all pending events
    public func clearPendingEvents() {
        queue.async {
            self.pendingEvents.removeAll()
            self.storage.clearPendingEngagementEvents()

            if self.config.enableDebugLogging {
                print("RelevaSDK: Cleared all pending engagement events")
            }
        }
    }

    /// Get pending event count
    public func getPendingEventCount() async -> Int {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.pendingEvents.count)
            }
        }
    }
}

// MARK: - Statistics

/// A snapshot of the engagement queue.
///
/// Replaces the `[String: Any]` that `getStatistics` used to hand back: the keys were
/// undocumented, every read needed a cast, and the dictionary is not `Sendable`, which
/// matters now that it crosses from the tracking queue to whatever awaited it.
public struct EngagementStatistics: Sendable, Equatable {
    /// Events waiting to be sent.
    public let pendingCount: Int
    /// Whether the batch timer is running.
    public let isTracking: Bool
    /// Whether a batch is in flight right now.
    public let isSending: Bool
    /// Configured maximum events per batch.
    public let batchSize: Int
    /// Configured seconds between batches.
    public let batchInterval: TimeInterval
    /// Pending event counts keyed by `EngagementEventType.rawValue`.
    public let eventTypes: [String: Int]
}

extension EngagementTrackingService {
    /// Get engagement statistics
    public func getStatistics() async -> EngagementStatistics {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: EngagementStatistics(
                    pendingCount: self.pendingEvents.count,
                    isTracking: self.batchTimer != nil,
                    isSending: self.isSending,
                    batchSize: self.config.engagementBatchSize,
                    batchInterval: self.config.engagementBatchInterval,
                    eventTypes: Dictionary(grouping: self.pendingEvents) { $0.type.rawValue }
                        .mapValues { $0.count }
                ))
            }
        }
    }
}
