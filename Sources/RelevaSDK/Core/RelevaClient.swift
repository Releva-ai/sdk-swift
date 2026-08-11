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
        return deviceId
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
        return profileId
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
        if !isFirstInitialization && cartChanged && config.enableTracking {
            let request = ScreenViewRequest(screenToken: nil, productIds: nil, categories: nil, filter: nil)
            push(request, incrementViews: false) { result in
                if self.config.enableDebugLogging {
                    switch result {
                    case .success:
                        print("RelevaSDK: Cart changes synced to backend")
                    case .failure(let error):
                        print("RelevaSDK: Failed to sync cart changes - \(error)")
                    }
                }
            }
        }
    }

    /// Get current cart
    public func getCart() -> Cart? {
        return cart
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
        if !isFirstInitialization && wishlistChanged && config.enableTracking {
            let request = ScreenViewRequest(screenToken: nil, productIds: nil, categories: nil, filter: nil)
            push(request, incrementViews: false) { result in
                if self.config.enableDebugLogging {
                    switch result {
                    case .success:
                        print("RelevaSDK: Wishlist changes synced to backend")
                    case .failure(let error):
                        print("RelevaSDK: Failed to sync wishlist changes - \(error)")
                    }
                }
            }
        }
    }

    /// Get current wishlist
    public func getWishlist() -> [WishlistProduct]? {
        return wishlist
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
    /// - Parameters:
    ///   - request: Push request with page/product context
    ///   - completion: Completion handler with response
    public func push(
        _ request: any PushRequestConvertible,
        completion: @escaping (Result<RelevaResponse, RelevaError>) -> Void
    ) {
        push(request, incrementViews: true, completion: completion)
    }

    /// Internal push that lets callers opt out of incrementing the view counter.
    /// Cart and wishlist auto-syncs use `incrementViews: false` to avoid inflating
    /// the page-view count with non-navigation push calls.
    private func push(
        _ request: any PushRequestConvertible,
        incrementViews: Bool,
        completion: @escaping (Result<RelevaResponse, RelevaError>) -> Void
    ) {
        guard config.enableTracking else {
            completion(.success(RelevaResponse.empty()))
            return
        }

        // Ensure lifecycle-based session tracking is initialized
        SessionService.shared.initialize(storage: storage, npsManager: npsManager)

        let pushRequest = request.pushRequest

        // Build context
        let context = buildContext(for: pushRequest, incrementViews: incrementViews)

        // Get request dictionary
        let requestDict = pushRequest.toDict()

        // Send request
        networkService.sendPushRequest(requestDict, context: context) { result in
            // Reset change flags after successful request
            if case .success(let response) = result {
                self.resetChangeFlags()
                // Initialize banners from response
                if !response.banners.isEmpty {
                    self.bannerManager?.initialize(newBanners: response.banners, scrollPercentageProvider: nil)
                }
                // Initialize stories from response
                if !response.stories.isEmpty {
                    self.storyManager?.initialize(newStories: response.stories, scrollPercentageProvider: nil)
                }
                // Initialize NPS from response
                self.npsManager?.initialize(response.nps)
            }
            completion(result)
        }
    }

    // MARK: - Tracking Methods

    /// Track screen view
    /// - Parameters:
    ///   - screenToken: Screen identifier
    ///   - productIds: Product IDs on screen
    ///   - categories: Categories on screen
    ///   - filter: Applied filter
    ///   - completion: Completion handler
    public func trackScreenView(
        screenToken: String? = nil,
        productIds: [String]? = nil,
        categories: [String]? = nil,
        filter: AbstractFilter? = nil,
        completion: ((Result<RelevaResponse, RelevaError>) -> Void)? = nil
    ) {
        guard config.enableTracking else {
            completion?(.success(RelevaResponse.empty()))
            return
        }

        let request = ScreenViewRequest(
            screenToken: screenToken,
            productIds: productIds,
            categories: categories,
            filter: filter
        )

        push(request) { result in
            completion?(result)
        }
    }

    /// Track product view
    /// - Parameters:
    ///   - product: Viewed product
    ///   - screenToken: Screen identifier
    ///   - completion: Completion handler
    public func trackProductView(
        product: ViewedProduct,
        screenToken: String? = nil,
        completion: ((Result<RelevaResponse, RelevaError>) -> Void)? = nil
    ) {
        guard config.enableTracking else {
            completion?(.success(RelevaResponse.empty()))
            return
        }

        let request = PushRequest.forProductView(product, screenToken: screenToken)

        push(request) { result in
            completion?(result)
        }
    }

    /// Track search
    /// - Parameters:
    ///   - query: Search query
    ///   - resultProductIds: Product IDs in results
    ///   - screenToken: Screen identifier
    ///   - filter: Applied filter
    ///   - completion: Completion handler
    public func trackSearchView(
        query: String,
        resultProductIds: [String]? = nil,
        screenToken: String? = nil,
        filter: AbstractFilter? = nil,
        completion: ((Result<RelevaResponse, RelevaError>) -> Void)? = nil
    ) {
        guard config.enableTracking else {
            completion?(.success(RelevaResponse.empty()))
            return
        }

        let request = SearchRequest(
            screenToken: screenToken,
            query: query,
            resultProductIds: resultProductIds,
            filter: filter
        )

        push(request) { result in
            completion?(result)
        }
    }

    /// Track checkout success
    /// - Parameters:
    ///   - orderedCart: Cart that was ordered
    ///   - screenToken: Screen identifier
    ///   - completion: Completion handler
    public func trackCheckoutSuccess(
        orderedCart: Cart,
        screenToken: String? = nil,
        completion: ((Result<RelevaResponse, RelevaError>) -> Void)? = nil
    ) {
        guard config.enableTracking else {
            completion?(.success(RelevaResponse.empty()))
            return
        }

        let request = CheckoutSuccessRequest(
            screenToken: screenToken,
            orderedCart: orderedCart
        )

        push(request) { result in
            completion?(result)
        }
    }

    /// Track custom event
    /// - Parameters:
    ///   - event: Custom event
    ///   - screenToken: Screen identifier
    ///   - completion: Completion handler
    public func trackCustomEvent(
        _ event: CustomEvent,
        screenToken: String? = nil,
        completion: ((Result<RelevaResponse, RelevaError>) -> Void)? = nil
    ) {
        guard config.enableTracking else {
            completion?(.success(RelevaResponse.empty()))
            return
        }

        let request = PushRequest.forCustomEvent(event, screenToken: screenToken)

        push(request) { result in
            completion?(result)
        }
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

        networkService.sendBannerImpression(payload) { result in
            if self.config.enableDebugLogging {
                switch result {
                case .success:
                    print("RelevaSDK: Banner impression tracked for \(banner.token)")
                case .failure(let error):
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

        networkService.sendBannerAction(payload) { result in
            if self.config.enableDebugLogging {
                switch result {
                case .success:
                    print("RelevaSDK: Banner action '\(action)' tracked for \(banner.token)")
                case .failure(let error):
                    print("RelevaSDK: Failed to track banner action: \(error)")
                }
            }
        }
    }

    // MARK: - Push Notifications

    /// Register push notification token
    /// - Parameters:
    ///   - token: FCM token
    ///   - deviceType: Device type (defaults to current)
    ///   - completion: Completion handler
    public func registerPushToken(
        _ token: String,
        deviceType: DeviceType = .current,
        completion: ((Result<Bool, RelevaError>) -> Void)? = nil
    ) {
        guard config.enablePushNotifications else {
            completion?(.success(true))
            return
        }

        // Ensure deviceId is set before registering
        guard let deviceId = self.deviceId else {
            if config.enableDebugLogging {
                print("RelevaSDK: ERROR - Cannot register push token without deviceId. Call setDeviceId() first.")
            }
            completion?(.failure(.missingRequiredField("deviceId must be set before registering push token")))
            return
        }

        // Save token
        storage.savePushToken(token, deviceType: deviceType)
        lastPushTokenDeviceType = deviceType

        // Register with backend
        networkService.registerPushToken(token, deviceType: deviceType, deviceId: deviceId, profileId: profileId) { result in
            if case .success = result {
                self.storage.savePushTokenUploadedAt(Date())
            }
            if self.config.enableDebugLogging {
                switch result {
                case .success:
                    print("RelevaSDK: ✓ Successfully registered push token for \(deviceType.rawValue)")
                case .failure(let error):
                    print("RelevaSDK: ✗ Failed to register push token: \(error.localizedDescription)")
                }
            }
            completion?(result)
        }

        if config.enableDebugLogging {
            print("RelevaSDK: Registering push token for \(deviceType.rawValue)...")
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
                guard let self = self else { return }

                guard let token = token, !token.isEmpty else {
                    self.isRefreshingPushToken = false
                    if self.config.enableDebugLogging {
                        print("RelevaSDK: refreshPushToken - provider returned empty token")
                    }
                    return
                }

                // Re-read storage inside the Task: the provider call is async, and an
                // explicit `registerPushToken` from the host could have mutated `stored`
                // in the meantime. Computing `tokenChanged` against a fresh snapshot
                // keeps the change-detection consistent with `lastUpload`.
                let stored = self.storage.getPushToken()
                let deviceType = self.lastPushTokenDeviceType ?? stored?.deviceType ?? .current
                let tokenChanged = (stored?.token != token)
                let lastUpload = self.storage.getPushTokenUploadedAt()
                let isStale = lastUpload.map { Date().timeIntervalSince($0) > RelevaClient.pushTokenRefreshInterval } ?? true

                guard tokenChanged || isStale else {
                    self.isRefreshingPushToken = false
                    if self.config.enableDebugLogging {
                        print("RelevaSDK: refreshPushToken - token unchanged and uploaded recently, skipping")
                    }
                    return
                }

                self.registerPushToken(token, deviceType: deviceType) { [weak self] _ in
                    Task { @MainActor in
                        self?.isRefreshingPushToken = false
                    }
                }
            }
        }
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
    /// Failures are swallowed with one retry - the thank-you screen is shown regardless.
    public func submitNpsResponse(
        token: String,
        score: Int,
        comment: String? = nil,
        completion: ((Result<Bool, RelevaError>) -> Void)? = nil
    ) {
        guard (0...10).contains(score) else {
            completion?(.failure(.invalidConfiguration("NPS score must be between 0 and 10")))
            return
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

        networkService.sendNpsSubmission(payload, token: token) { result in
            switch result {
            case .success:
                completion?(.success(true))
            case .failure:
                // One silent retry
                self.networkService.sendNpsSubmission(payload, token: token) { retryResult in
                    completion?(retryResult)
                }
            }
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

        networkService.sendPushEvent(payload) { result in
            if self.config.enableDebugLogging {
                switch result {
                case .success:
                    print("RelevaSDK: Story action '\(action)' tracked for \(story.token)")
                case .failure(let error):
                    print("RelevaSDK: Failed to track story action: \(error)")
                }
            }
        }
    }

    // MARK: - Inbox

    /// Access the inbox service
    public var inbox: InboxService {
        return InboxService.shared
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

// MARK: - Async/Await Support

@available(iOS 15.0, *)
extension RelevaClient {

    /// Send push request using async/await
    ///
    /// See the completion-handler `push(_:completion:)` for why this takes
    /// `any PushRequestConvertible` rather than a generic parameter.
    public func push(_ request: any PushRequestConvertible) async throws -> RelevaResponse {
        return try await withCheckedThrowingContinuation { continuation in
            push(request) { result in
                continuation.resume(with: result)
            }
        }
    }

    /// Track screen view using async/await
    public func trackScreenView(
        screenToken: String? = nil,
        productIds: [String]? = nil,
        categories: [String]? = nil,
        filter: AbstractFilter? = nil
    ) async throws -> RelevaResponse {
        return try await withCheckedThrowingContinuation { continuation in
            trackScreenView(
                screenToken: screenToken,
                productIds: productIds,
                categories: categories,
                filter: filter
            ) { result in
                continuation.resume(with: result)
            }
        }
    }

    /// Register push token using async/await
    public func registerPushToken(_ token: String, deviceType: DeviceType = .current) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            registerPushToken(token, deviceType: deviceType) { result in
                continuation.resume(with: result)
            }
        }
    }
}