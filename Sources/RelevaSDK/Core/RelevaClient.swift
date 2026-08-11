import Foundation
import UIKit

/// Main SDK client for Releva integration
@MainActor
public class RelevaClient {
    // MARK: - Singleton

    /// Shared instance (optional - can also create custom instances)
    public static var shared: RelevaClient?

    // MARK: - Properties

    /// API realm
    private let realm: String

    /// API access token
    private let accessToken: String

    /// SDK configuration
    public let config: RelevaConfig

    /// Storage service
    private let storage: StorageService

    /// Network service
    private let networkService: NetworkService

    /// Session manager
    private let sessionManager: SessionManager

    /// Current device ID
    private var deviceId: String?

    /// Current profile ID
    private var profileId: String?

    /// Current cart
    private var cart: Cart?

    /// Current wishlist
    private var wishlist: [WishlistProduct]?

    /// Track if device ID changed
    private var deviceIdChanged = false

    /// Track if profile ID changed
    private var profileChanged = false

    /// Track if cart changed
    private var cartChanged = false

    /// Track if wishlist changed
    private var wishlistChanged = false

    /// Track if cart was initialized
    private var cartInitialized = false

    /// Track if wishlist was initialized
    private var wishlistInitialized = false

    /// Profile IDs to merge
    private var mergeProfileIds: [String] = []

    /// Engagement tracking service
    private var engagementService: EngagementTrackingService?

    /// Notification service
    private var notificationService: NotificationService?

    /// Banner manager service
    private var bannerManager: BannerManagerService?

    /// NPS manager service
    private var npsManager: NpsManagerService?

    /// Story manager service
    private var storyManager: StoryManagerService?

    /// App version string (sent in NPS push context)
    private var appVersion: String?

    /// Host-supplied callback that fetches the latest push token from the OS / Firebase.
    /// The SDK invokes this on app launch and on foreground to keep the backend in sync
    /// with FCM's rotating token. Host should wire it to e.g. `Messaging.messaging().token`.
    ///
    /// The inner `(String?) -> Void` completion may be invoked from any thread (Firebase's
    /// `Messaging.token(...)` delivers on an internal queue); the SDK re-hops to the main
    /// actor before touching any state, so host implementers do not need to dispatch.
    public var pushTokenProvider: ((@escaping @Sendable (String?) -> Void) -> Void)?

    /// Last device type used for `registerPushToken`, replayed by `refreshPushToken()`.
    private var lastPushTokenDeviceType: DeviceType?

    /// Lifecycle observer that triggers `refreshPushToken()` when the app becomes active.
    private var pushTokenLifecycleObserver: NSObjectProtocol?

    /// In-flight guard for `refreshPushToken()` so a fast background→foreground→background→foreground
    /// cycle cannot enqueue overlapping provider callbacks and produce duplicate uploads.
    private var isRefreshingPushToken = false

    // MARK: - Initializers

    /// Initialize Releva client
    /// - Parameters:
    ///   - realm: API realm
    ///   - accessToken: API access token
    ///   - config: SDK configuration (defaults to full)
    public init(realm: String, accessToken: String, config: RelevaConfig = .full()) {
        self.realm = realm
        self.accessToken = accessToken
        self.config = config

        // Initialize services
        self.storage = StorageService()
        self.networkService = NetworkService(
            realm: realm,
            accessToken: accessToken,
            config: config
        )
        self.sessionManager = SessionManager(storage: storage)

        // Load stored data
        loadStoredData()

        // Set as shared instance if none exists
        if RelevaClient.shared == nil {
            RelevaClient.shared = self
        }

        // Subscribe to foreground events so we can refresh the FCM token.
        // FCM rotates tokens silently and the host's `didRegisterForRemoteNotifications`
        // only fires on first registration, so the backend would otherwise drift stale.
        if config.enablePushNotifications {
            installPushTokenLifecycleObserver()
        }

        if config.enableDebugLogging {
            print("RelevaSDK: Initialized with realm '\(realm)'")
        }
    }

    // Intentionally no `deinit` observer cleanup: `RelevaClient` is `@MainActor`-isolated
    // so touching `pushTokenLifecycleObserver` from a nonisolated `deinit` would emit a
    // Swift 6 strict-concurrency warning. The observer block captures `[weak self]`, so
    // it no-ops once the client is freed; the `NSObjectProtocol` token lives only until
    // the (typically singleton) client is itself deallocated.

    // MARK: - User Identification

    /// Set device ID
    /// - Parameter deviceId: Unique device identifier
    public func setDeviceId(_ deviceId: String) {
        let previousId = self.deviceId
        self.deviceId = deviceId
        self.deviceIdChanged = (previousId != nil && previousId != deviceId)

        storage.saveDeviceId(deviceId)

        if config.enableDebugLogging {
            print("RelevaSDK: Device ID set to '\(deviceId)' (changed: \(deviceIdChanged))")
        }
    }

    /// Get current device ID
    public func getDeviceId() -> String? {
        deviceId
    }

    /// Set profile ID
    /// - Parameters:
    ///   - profileId: User profile identifier
    ///   - skipMergeWithPreviousProfileId: If true, clears merge profile IDs (used for logout). Defaults to false.
    public func setProfileId(_ profileId: String, _ skipMergeWithPreviousProfileId: Bool = false) {
        let previousId = self.profileId

        if skipMergeWithPreviousProfileId {
            // Clear merge profile IDs when explicitly skipping merge (e.g., on logout)
            mergeProfileIds = []
            storage.clearMergeProfileIds()

            if config.enableDebugLogging {
                print("RelevaSDK: Profile ID changed to '\(profileId)' (skip merge = true)")
            }
        } else if let prevId = previousId, prevId != profileId {
            // Normal behavior: merge previous profile with new one
            if !mergeProfileIds.contains(prevId) {
                mergeProfileIds.append(prevId)
                storage.addMergeProfileId(prevId)

                if config.enableDebugLogging {
                    print("RelevaSDK: Profile ID changed from '\(prevId)' to '\(profileId)' (merge enabled)")
                    print("RelevaSDK: Merge profile IDs stored: \(mergeProfileIds)")
                }
            } else if config.enableDebugLogging {
                print("RelevaSDK: Profile ID changed to '\(profileId)' (previous profile already in merge list)")
            }
        } else if config.enableDebugLogging {
            print("RelevaSDK: Profile ID set to '\(profileId)' (first time, no merge needed)")
        }

        self.profileId = profileId
        self.profileChanged = (previousId != nil && previousId != profileId)

        storage.saveProfileId(profileId)
    }

    /// Get current profile ID
    public func getProfileId() -> String? {
        profileId
    }

    // MARK: - Configuration

    /// Override the API endpoint at runtime (e.g. ngrok URL for local dev)
    /// - Parameter url: The override URL, or nil to clear
    public func setEndpointOverride(_ url: String?) {
        networkService.setEndpointOverride(url)
    }

    /// Set the app version string (used in NPS push context for server-side filtering)
    /// - Parameter version: Semantic version string (e.g. "1.2.3")
    public func setAppVersion(_ version: String) {
        self.appVersion = version
        if config.enableDebugLogging {
            print("RelevaSDK: App version set to '\(version)'")
        }
    }

    /// Fire a named event for NPS trigger evaluation
    /// - Parameter eventName: The event name to evaluate (e.g. "checkout_complete")
    public func trackEvent(_ eventName: String) {
        npsManager?.trackEvent(eventName)
    }

    // MARK: - Cart Management

    /// Set the current cart
    /// - Parameter cart: Shopping cart
    public func setCart(_ cart: Cart) {
        let previousCart = self.cart
        self.cart = cart
        self.cartChanged = (previousCart != cart)

        let isFirstInitialization = !cartInitialized
        if !cartInitialized {
            cartInitialized = true
            storage.markCartInitialized()
        }

        storage.saveCart(cart)

        // Trigger cart change banners and stories
        if cartChanged {
            bannerManager?.onCartChanged()
            storyManager?.onCartChanged()
        }

        if config.enableDebugLogging {
            print("RelevaSDK: Cart updated with \(cart.products.count) products (changed: \(cartChanged))")
        }

        // Automatically sync cart changes to backend (skip on first initialization).
        // Uses incrementViews: false so cart updates don't inflate the page-view counter.
        //
        // `preparePush` runs *here*, synchronously, and only the transfer is deferred to the
        // `Task`. 4.x built the payload inline for the same reason — only its completion
        // handler was asynchronous — and building it inside the `Task` instead would let
        // anything that happens later in the same run-loop turn rewrite what goes on the
        // wire: a second `setCart` (both pushes would carry the final cart), or a
        // `setProfileId(_:skipMergeWithPreviousProfileId: true)` (this cart would arrive
        // under the *new* profile, with no merge to stitch it back). Pinning the whole
        // prepared payload, rather than just the cart, is what makes that hold for the
        // identity fields too.
        if !isFirstInitialization && cartChanged {
            let request = ScreenViewRequest(screenToken: nil, productIds: nil, categories: nil, filter: nil)
            guard let prepared = preparePush(request, incrementViews: false) else { return }
            Task { [weak self] in
                guard let self = self else { return }
                do {
                    _ = try await self.send(prepared)
                    if self.config.enableDebugLogging {
                        print("RelevaSDK: Cart changes synced to backend")
                    }
                } catch {
                    if self.config.enableDebugLogging {
                        print("RelevaSDK: Failed to sync cart changes - \(error)")
                    }
                }
            }
        }
    }

    /// Get current cart
    public func getCart() -> Cart? {
        cart
    }

    /// Clear cart storage
    public func clearCartStorage() {
        cart = nil
        cartChanged = false
        cartInitialized = false
        storage.clearCart()

        if config.enableDebugLogging {
            print("RelevaSDK: Cart storage cleared")
        }
    }

    // MARK: - Wishlist Management

    /// Set the wishlist
    /// - Parameter products: Wishlist products
    public func setWishlist(_ products: [WishlistProduct]) {
        let previousWishlist = self.wishlist
        self.wishlist = products

        self.wishlistChanged = (previousWishlist != products)

        let isFirstInitialization = !wishlistInitialized
        if !wishlistInitialized {
            wishlistInitialized = true
            storage.markWishlistInitialized()
        }

        storage.saveWishlist(products)

        // Trigger wishlist change banners and stories
        if wishlistChanged {
            bannerManager?.onWishlistChanged()
            storyManager?.onWishlistChanged()
        }

        if config.enableDebugLogging {
            print("RelevaSDK: Wishlist updated with \(products.count) products (changed: \(wishlistChanged))")
        }

        // Automatically sync wishlist changes to backend (skip on first initialization).
        // Uses incrementViews: false so wishlist updates don't inflate the page-view counter.
        // Prepared synchronously for the same reason `setCart` prepares synchronously:
        // see the comment there.
        if !isFirstInitialization && wishlistChanged {
            let request = ScreenViewRequest(screenToken: nil, productIds: nil, categories: nil, filter: nil)
            guard let prepared = preparePush(request, incrementViews: false) else { return }
            Task { [weak self] in
                guard let self = self else { return }
                do {
                    _ = try await self.send(prepared)
                    if self.config.enableDebugLogging {
                        print("RelevaSDK: Wishlist changes synced to backend")
                    }
                } catch {
                    if self.config.enableDebugLogging {
                        print("RelevaSDK: Failed to sync wishlist changes - \(error)")
                    }
                }
            }
        }
    }

    /// Get current wishlist
    public func getWishlist() -> [WishlistProduct]? {
        wishlist
    }

    /// Clear wishlist storage
    public func clearWishlistStorage() {
        wishlist = nil
        wishlistChanged = false
        wishlistInitialized = false
        storage.clearWishlist()

        if config.enableDebugLogging {
            print("RelevaSDK: Wishlist storage cleared")
        }
    }

    // MARK: - Core Push Method

    /// Send a push request to the API
    ///
    /// Takes `any PushRequestConvertible` rather than a generic parameter so a caller can
    /// hold requests as the protocol type — a request queue or a `-> PushRequest` factory
    /// typed `any PushRequestConvertible` can be pushed directly; Swift existentials don't
    /// self-conform, so a generic `<Request: PushRequestConvertible>` parameter would reject
    /// exactly that value.
    /// - Parameter request: Push request with page/product context
    /// - Returns: The API response, or an empty response when tracking is disabled
    @discardableResult
    public func push(_ request: any PushRequestConvertible) async throws -> RelevaResponse {
        try await push(request, incrementViews: true)
    }

    /// Internal push that lets callers opt out of incrementing the view counter.
    /// Cart and wishlist auto-syncs use `incrementViews: false` to avoid inflating
    /// the page-view count with non-navigation push calls.
    private func push(_ request: any PushRequestConvertible, incrementViews: Bool) async throws -> RelevaResponse {
        guard let prepared = preparePush(request, incrementViews: incrementViews) else {
            return RelevaResponse.empty()
        }
        return try await send(prepared)
    }

    /// A payload and its context, both already assembled from `@MainActor` client state.
    private struct PreparedPush {
        let payload: [String: Any]
        let context: [String: Any]
    }

    /// The synchronous half of `push`: everything that reads main-actor client state.
    ///
    /// Split out so a caller that cannot `await` — `setCart` / `setWishlist` — can still pin
    /// the *whole* payload at the moment it is called and defer only the transfer. Returns
    /// `nil` when tracking is off, which is the `RelevaResponse.empty()` case for `push`.
    private func preparePush(_ request: any PushRequestConvertible, incrementViews: Bool) -> PreparedPush? {
        guard config.enableTracking else { return nil }

        // Ensure lifecycle-based session tracking is initialized
        SessionService.shared.initialize(storage: storage, npsManager: npsManager)

        let pushRequest = request.pushRequest

        return PreparedPush(
            payload: pushRequest.toDict(),
            context: buildContext(for: pushRequest, incrementViews: incrementViews)
        )
    }

    /// The asynchronous half of `push`: the transfer, plus the main-actor bookkeeping that
    /// depends on the response.
    private func send(_ prepared: PreparedPush) async throws -> RelevaResponse {
        // `NetworkService` is nonisolated, so payload serialization, the transfer and response
        // decoding all run off the main actor; this method is suspended, not blocking the main
        // thread, until the decoded response comes back.
        let response = try await networkService.sendPushRequest(prepared.payload, context: prepared.context)

        // Reset change flags after successful request
        resetChangeFlags()

        // Initialize banners from response
        if !response.banners.isEmpty {
            bannerManager?.initialize(newBanners: response.banners, scrollPercentageProvider: nil)
        }
        // Initialize stories from response
        if !response.stories.isEmpty {
            storyManager?.initialize(newStories: response.stories, scrollPercentageProvider: nil)
        }
        // Initialize NPS from response
        npsManager?.initialize(response.nps)

        return response
    }

    // MARK: - Tracking Methods

    // Each of these forwards to `push(_:)`, which owns the `config.enableTracking` check and
    // returns an empty response when tracking is off — so none of them repeats that guard.
    // The result is `@discardableResult` because these are usually called for their effect,
    // but the response carries the banners/stories/NPS the backend returned, so it is offered.

    /// Track screen view
    /// - Parameters:
    ///   - screenToken: Screen identifier
    ///   - productIds: Product IDs on screen
    ///   - categories: Categories on screen
    ///   - filter: Applied filter
    /// - Returns: The API response
    @discardableResult
    public func trackScreenView(
        screenToken: String? = nil,
        productIds: [String]? = nil,
        categories: [String]? = nil,
        filter: AbstractFilter? = nil
    ) async throws -> RelevaResponse {
        let request = ScreenViewRequest(
            screenToken: screenToken,
            productIds: productIds,
            categories: categories,
            filter: filter
        )

        return try await push(request)
    }

    /// Track product view
    /// - Parameters:
    ///   - product: Viewed product
    ///   - screenToken: Screen identifier
    /// - Returns: The API response
    @discardableResult
    public func trackProductView(
        product: ViewedProduct,
        screenToken: String? = nil
    ) async throws -> RelevaResponse {
        try await push(PushRequest.forProductView(product, screenToken: screenToken))
    }

    /// Track search
    /// - Parameters:
    ///   - query: Search query
    ///   - resultProductIds: Product IDs in results
    ///   - screenToken: Screen identifier
    ///   - filter: Applied filter
    /// - Returns: The API response
    @discardableResult
    public func trackSearchView(
        query: String,
        resultProductIds: [String]? = nil,
        screenToken: String? = nil,
        filter: AbstractFilter? = nil
    ) async throws -> RelevaResponse {
        let request = SearchRequest(
            screenToken: screenToken,
            query: query,
            resultProductIds: resultProductIds,
            filter: filter
        )

        return try await push(request)
    }

    /// Track checkout success
    /// - Parameters:
    ///   - orderedCart: Cart that was ordered
    ///   - screenToken: Screen identifier
    /// - Returns: The API response
    @discardableResult
    public func trackCheckoutSuccess(
        orderedCart: Cart,
        screenToken: String? = nil
    ) async throws -> RelevaResponse {
        try await push(CheckoutSuccessRequest(screenToken: screenToken, orderedCart: orderedCart))
    }

    /// Track custom event
    /// - Parameters:
    ///   - event: Custom event
    ///   - screenToken: Screen identifier
    /// - Returns: The API response
    @discardableResult
    public func trackCustomEvent(
        _ event: CustomEvent,
        screenToken: String? = nil
    ) async throws -> RelevaResponse {
        try await push(PushRequest.forCustomEvent(event, screenToken: screenToken))
    }

    // MARK: - Banner Tracking

    /// Track banner impression
    /// - Parameter banner: The banner that was displayed
    public func bannerImpression(_ banner: BannerResponse) {
        let payload: [String: Any] = [
            "profileId": profileId ?? "",
            "deviceId": deviceId ?? "",
            "sessionId": SessionService.shared.getSessionId(),
            "banners": [
                [
                    "token": banner.token,
                    "bannerId": String(banner.bannerId),
                    "segmentId": String(banner.segmentId)
                ]
            ]
        ]

        Task { [weak self] in
            guard let self = self else { return }
            do {
                try await self.networkService.sendBannerImpression(payload)
                if self.config.enableDebugLogging {
                    print("RelevaSDK: Banner impression tracked for \(banner.token)")
                }
            } catch {
                if self.config.enableDebugLogging {
                    print("RelevaSDK: Failed to track banner impression: \(error)")
                }
            }
        }
    }

    /// Track banner action (click, close, etc.)
    /// - Parameters:
    ///   - banner: The banner that was acted upon
    ///   - action: Action type (e.g., "bannerClick", "bannerClose")
    public func bannerAction(_ banner: BannerResponse, action: String) {
        let payload: [String: Any] = [
            "deviceId": deviceId ?? "",
            "profileId": profileId ?? "",
            "sessionId": SessionService.shared.getSessionId(),
            "action": action,
            "attributions": [
                "bannerBlockId": banner.token,
                "bannerId": String(banner.bannerId)
            ]
        ]

        Task { [weak self] in
            guard let self = self else { return }
            do {
                try await self.networkService.sendBannerAction(payload)
                if self.config.enableDebugLogging {
                    print("RelevaSDK: Banner action '\(action)' tracked for \(banner.token)")
                }
            } catch {
                if self.config.enableDebugLogging {
                    print("RelevaSDK: Failed to track banner action: \(error)")
                }
            }
        }
    }

    // MARK: - Push Notifications

    /// Register push notification token
    ///
    /// Returns `Void` rather than the `Bool` the 4.x completion handler carried: that flag was
    /// `true` on every path that reached it, so `throws` already says everything it said.
    /// - Parameters:
    ///   - token: FCM token
    ///   - deviceType: Device type (defaults to current)
    public func registerPushToken(_ token: String, deviceType: DeviceType = .current) async throws {
        guard config.enablePushNotifications else { return }

        // Ensure deviceId is set before registering
        guard let deviceId = self.deviceId else {
            if config.enableDebugLogging {
                print("RelevaSDK: ERROR - Cannot register push token without deviceId. Call setDeviceId() first.")
            }
            throw RelevaError.missingRequiredField("deviceId must be set before registering push token")
        }

        // Save token
        storage.savePushToken(token, deviceType: deviceType)
        lastPushTokenDeviceType = deviceType

        if config.enableDebugLogging {
            print("RelevaSDK: Registering push token for \(deviceType.rawValue)...")
        }

        // Register with backend
        do {
            try await networkService.registerPushToken(
                token,
                deviceType: deviceType,
                deviceId: deviceId,
                profileId: profileId
            )
        } catch {
            if config.enableDebugLogging {
                print("RelevaSDK: ✗ Failed to register push token: \(error.localizedDescription)")
            }
            throw error
        }

        storage.savePushTokenUploadedAt(Date())

        if config.enableDebugLogging {
            print("RelevaSDK: ✓ Successfully registered push token for \(deviceType.rawValue)")
        }
    }

    /// Minimum interval between unconditional push-token re-uploads. A changed
    /// token is always re-uploaded; an unchanged token is re-uploaded at most
    /// once per this interval to keep the backend record fresh.
    private static let pushTokenRefreshInterval: TimeInterval = 24 * 60 * 60

    /// Fetch the current push token from `pushTokenProvider` and re-register it with
    /// the backend if the token changed or the last successful upload was more than
    /// 24 hours ago. Safe to call anytime; no-ops if the provider isn't set or the
    /// provider returns nil. Called automatically on app launch and on foreground.
    public func refreshPushToken() {
        guard config.enablePushNotifications else { return }
        guard let provider = pushTokenProvider else {
            if config.enableDebugLogging {
                print("RelevaSDK: refreshPushToken skipped - pushTokenProvider not set")
            }
            return
        }

        guard !isRefreshingPushToken else {
            if config.enableDebugLogging {
                print("RelevaSDK: refreshPushToken skipped - refresh already in flight")
            }
            return
        }
        isRefreshingPushToken = true

        provider { [weak self] token in
            Task { @MainActor in
                await self?.completePushTokenRefresh(token)
            }
        }
    }

    /// The second half of `refreshPushToken()`, run once the provider has answered.
    ///
    /// The `defer` is what makes the in-flight guard correct: it clears on every exit,
    /// including the `throws` from `registerPushToken`, which the 4.x nested-completion
    /// version only managed because its completion fired on both branches.
    private func completePushTokenRefresh(_ token: String?) async {
        defer { isRefreshingPushToken = false }

        guard let token = token, !token.isEmpty else {
            if config.enableDebugLogging {
                print("RelevaSDK: refreshPushToken - provider returned empty token")
            }
            return
        }

        // Re-read storage here rather than in `refreshPushToken`: the provider call is
        // asynchronous, and an explicit `registerPushToken` from the host could have mutated
        // `stored` in the meantime. Computing `tokenChanged` against a fresh snapshot keeps
        // the change-detection consistent with `lastUpload`.
        let stored = storage.getPushToken()
        let deviceType = lastPushTokenDeviceType ?? stored?.deviceType ?? .current
        let tokenChanged = (stored?.token != token)
        let lastUpload = storage.getPushTokenUploadedAt()
        let isStale = lastUpload.map { Date().timeIntervalSince($0) > RelevaClient.pushTokenRefreshInterval } ?? true

        guard tokenChanged || isStale else {
            if config.enableDebugLogging {
                print("RelevaSDK: refreshPushToken - token unchanged and uploaded recently, skipping")
            }
            return
        }

        // Failures are already logged by `registerPushToken`; a background refresh has
        // nobody to report to, so it is swallowed here exactly as it was in 4.x.
        try? await registerPushToken(token, deviceType: deviceType)
    }

    /// Subscribe to `didBecomeActive` so that every app launch / foreground triggers
    /// `refreshPushToken()`. The first emission happens once the app finishes launching,
    /// which covers the cold-start case too.
    private func installPushTokenLifecycleObserver() {
        #if canImport(UIKit)
        pushTokenLifecycleObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPushToken()
            }
        }
        #endif
    }

    /// Enable push engagement tracking
    public func enablePushEngagementTracking() {
        guard config.enablePushNotifications else { return }

        if engagementService == nil {
            engagementService = EngagementTrackingService(
                storage: storage,
                networkService: networkService,
                config: config
            )
        }

        engagementService?.startTracking()

        if notificationService == nil {
            notificationService = NotificationService(config: config)
        }

        notificationService?.initialize()

        if bannerManager == nil {
            bannerManager = BannerManagerService()
        }

        if npsManager == nil {
            npsManager = NpsManagerService()
        }

        if storyManager == nil {
            storyManager = StoryManagerService()
        }

        if config.enableDebugLogging {
            print("RelevaSDK: Push engagement tracking enabled")
        }
    }

    /// Track engagement from push notification
    /// - Parameters:
    ///   - userInfo: Notification payload
    ///   - type: Engagement type
    public func trackEngagement(userInfo: [AnyHashable: Any], type: EngagementEventType = .opened) {
        guard config.enablePushNotifications else { return }

        if let event = EngagementEvent.fromNotificationPayload(userInfo) {
            let updatedEvent = EngagementEvent(
                type: type,
                callbackUrl: event.callbackUrl,
                notificationId: event.notificationId,
                timestamp: Date(),
                metadata: event.metadata
            )

            engagementService?.trackEvent(updatedEvent)
        }
    }

    /// Check if a notification is from Releva
    /// - Parameter userInfo: Notification payload
    /// - Returns: True if from Releva
    public func isRelevaMessage(userInfo: [AnyHashable: Any]) -> Bool {
        // Firebase iOS notifications put custom data at root level (not in "data" wrapper)
        // Check root level first (iOS format)
        if let clickAction = userInfo["click_action"] as? String {
            return clickAction.hasPrefix("RELEVA_")
        }

        // Also check "data" wrapper (cross-platform / Android format)
        if let data = userInfo["data"] as? [String: Any],
           let clickAction = data["click_action"] as? String {
            return clickAction.hasPrefix("RELEVA_")
        }

        return false
    }

    // MARK: - NPS

    /// Submit an NPS survey response.
    ///
    /// Retried once on failure here, on top of the one retry `NetworkService` already gives
    /// every 5xx — so a persistent server error produces up to four requests over roughly
    /// 4 seconds of combined backoff before this throws. A cancelled task is the exception
    /// and is not retried. The survey UI shows its thank-you screen regardless, so a caller
    /// that does not care about delivery can `try?` this.
    public func submitNpsResponse(token: String, score: Int, comment: String? = nil) async throws {
        guard (0...10).contains(score) else {
            throw RelevaError.invalidConfiguration("NPS score must be between 0 and 10")
        }

        var payload: [String: Any] = [
            "profileId": profileId ?? "",
            "deviceId": deviceId ?? "",
            "sessionId": SessionService.shared.getSessionId(),
            "score": score
        ]
        if let comment = comment, !comment.isEmpty {
            payload["comment"] = comment
        }

        do {
            try await networkService.sendNpsSubmission(payload, token: token)
        } catch {
            // One silent retry, then the second failure is the caller's to see. A cancelled
            // task is not retried: `NetworkService` maps cancellation to `RelevaError`, so the
            // error itself no longer identifies it, but the retry would be a request the
            // caller has already asked to abandon.
            if Task.isCancelled { throw error }
            try await networkService.sendNpsSubmission(payload, token: token)
        }
    }

    // MARK: - Stories

    /// Track story impression
    public func storyImpression(_ story: StoryResponse) {
        storyAction(story, action: "storyImpression")
    }

    /// Track story action (view, click, complete, close, slide events)
    public func storyAction(_ story: StoryResponse, action: String, slideId: String? = nil) {
        var attributions: [String: Any] = [
            "storyId": story.token
        ]
        if let slideId = slideId {
            attributions["slideId"] = slideId
        }

        let payload: [String: Any] = [
            "deviceId": deviceId ?? "",
            "profileId": profileId ?? "",
            "sessionId": SessionService.shared.getSessionId(),
            "action": action,
            "attributions": attributions
        ]

        Task { [weak self] in
            guard let self = self else { return }
            do {
                try await self.networkService.sendPushEvent(payload)
                if self.config.enableDebugLogging {
                    print("RelevaSDK: Story action '\(action)' tracked for \(story.token)")
                }
            } catch {
                if self.config.enableDebugLogging {
                    print("RelevaSDK: Failed to track story action: \(error)")
                }
            }
        }
    }

    // MARK: - Inbox

    /// Access the inbox service
    public var inbox: InboxService {
        InboxService.shared
    }

    /// Initialize the inbox service. Call after setProfileId().
    public func initializeInbox() {
        InboxService.shared.initialize(
            networkService: networkService,
            accessToken: accessToken,
            profileId: profileId,
            storage: storage
        )
        InboxService.shared.refreshIfStale()
    }

    // MARK: - Private Methods

    /// Load data from storage
    private func loadStoredData() {
        deviceId = storage.getDeviceId()
        profileId = storage.getProfileId()
        cart = storage.getCart()
        wishlist = storage.getWishlist()
        mergeProfileIds = storage.getMergeProfileIds()
        cartInitialized = storage.isCartInitialized()
        wishlistInitialized = storage.isWishlistInitialized()
    }

    /// Build context for API request
    /// - Parameter incrementViews: Whether to increment the persistent view counter.
    ///   Pass `false` for background syncs (cart/wishlist updates) that should not
    ///   count as user-initiated page views.
    private func buildContext(for request: PushRequest, incrementViews: Bool = true) -> [String: Any] {
        var context: [String: Any] = [:]

        // Session
        context["sessionId"] = SessionService.shared.getSessionId()

        // Device ID
        if let deviceId = deviceId {
            context["deviceId"] = deviceId
            context["deviceIdChanged"] = deviceIdChanged
        }

        // Profile
        if let profileId = profileId {
            context["profile"] = ["id": profileId]
            context["profileChanged"] = profileChanged
        }

        // Cart
        let cartToUse = request.cart ?? cart
        if let cart = cartToUse {
            context["cart"] = cart.toDict()
            context["cartChanged"] = cartChanged || request.cart != nil
        }

        // Wishlist
        if let wishlist = wishlist {
            context["wishlist"] = ["products": wishlist.map { $0.toDict() }]
            context["wishlistChanged"] = wishlistChanged
        }

        // Merge profile IDs
        if !mergeProfileIds.isEmpty {
            context["mergeProfileIds"] = mergeProfileIds
        }

        // Build device context (with analytics)
        let sessionCount = storage.getDeviceSessionCount()
        let firstSeenAt = storage.getDeviceFirstSeenAt()
        let views = storage.getDeviceViewsCount() + (incrementViews ? 1 : 0)
        if incrementViews {
            storage.saveDeviceViewsCount(views)
        }

        var device: [String: Any] = [
            "sessions": sessionCount,
            "platform": "ios",
            "views": views,
            "sdkVersion": SDKVersion.current
        ]
        if let appVersion = appVersion {
            device["version"] = appVersion
        }
        if let firstSeenAt = firstSeenAt {
            device["firstSeenAt"] = firstSeenAt
        }
        context["device"] = device

        return context
    }

    /// Reset change flags after successful request
    private func resetChangeFlags() {
        deviceIdChanged = false
        profileChanged = false
        cartChanged = false
        wishlistChanged = false

        // Clear merge profile IDs after sending
        if !mergeProfileIds.isEmpty {
            mergeProfileIds = []
            storage.clearMergeProfileIds()
        }
    }
}
