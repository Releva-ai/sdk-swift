import Foundation
import UIKit

/// Main SDK client for Releva integration
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

        if config.enableDebugLogging {
            print("RelevaSDK: Initialized with realm '\(realm)'")
        }
    }

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
    /// - Parameter profileId: User profile identifier
    public func setProfileId(_ profileId: String) {
        let previousId = self.profileId

        // Add previous profile to merge list if different
        if let prevId = previousId, prevId != profileId {
            mergeProfileIds.append(prevId)
            storage.addMergeProfileId(prevId)
        }

        self.profileId = profileId
        self.profileChanged = (previousId != nil && previousId != profileId)

        storage.saveProfileId(profileId)

        if config.enableDebugLogging {
            print("RelevaSDK: Profile ID set to '\(profileId)' (changed: \(profileChanged))")
        }
    }

    /// Get current profile ID
    public func getProfileId() -> String? {
        return profileId
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

        if config.enableDebugLogging {
            print("RelevaSDK: Cart updated with \(cart.products.count) products (changed: \(cartChanged))")
        }

        // Automatically sync cart changes to backend (skip on first initialization)
        if !isFirstInitialization && cartChanged && config.enableTracking {
            trackScreenView(screenToken: nil) { result in
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

        // Simple change detection - could be improved with proper equality
        self.wishlistChanged = (previousWishlist?.count != products.count)

        let isFirstInitialization = !wishlistInitialized
        if !wishlistInitialized {
            wishlistInitialized = true
            storage.markWishlistInitialized()
        }

        storage.saveWishlist(products)

        if config.enableDebugLogging {
            print("RelevaSDK: Wishlist updated with \(products.count) products (changed: \(wishlistChanged))")
        }

        // Automatically sync wishlist changes to backend (skip on first initialization)
        if !isFirstInitialization && wishlistChanged && config.enableTracking {
            trackScreenView(screenToken: nil) { result in
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
    /// - Parameters:
    ///   - request: Push request with page/product context
    ///   - completion: Completion handler with response
    public func push(_ request: PushRequest, completion: @escaping (Result<RelevaResponse, RelevaError>) -> Void) {
        guard config.enableTracking else {
            completion(.success(RelevaResponse.empty()))
            return
        }

        // Build context
        let context = buildContext(for: request)

        // Get request dictionary
        let requestDict = request.toDict()

        // Send request
        networkService.sendPushRequest(requestDict, context: context) { result in
            // Reset change flags after successful request
            if case .success = result {
                self.resetChangeFlags()
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
    ///   - userEmail: User email
    ///   - userPhoneNumber: User phone
    ///   - userFirstName: User first name
    ///   - userLastName: User last name
    ///   - userRegisteredAt: User registration date
    ///   - completion: Completion handler
    public func trackCheckoutSuccess(
        orderedCart: Cart,
        screenToken: String? = nil,
        userEmail: String? = nil,
        userPhoneNumber: String? = nil,
        userFirstName: String? = nil,
        userLastName: String? = nil,
        userRegisteredAt: Date? = nil,
        completion: ((Result<RelevaResponse, RelevaError>) -> Void)? = nil
    ) {
        guard config.enableTracking else {
            completion?(.success(RelevaResponse.empty()))
            return
        }

        let request = CheckoutSuccessRequest(
            screenToken: screenToken,
            orderedCart: orderedCart,
            userEmail: userEmail,
            userPhoneNumber: userPhoneNumber,
            userFirstName: userFirstName,
            userLastName: userLastName,
            userRegisteredAt: userRegisteredAt
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

    // MARK: - Push Notifications

    /// Register push notification token
    /// - Parameters:
    ///   - token: APNs or FCM token
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

        // Register with backend
        networkService.registerPushToken(token, deviceType: deviceType, deviceId: deviceId, profileId: profileId) { result in
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
            return clickAction == "RELEVA_NOTIFICATION_CLICK"
        }

        // Also check "data" wrapper (cross-platform / Android format)
        if let data = userInfo["data"] as? [String: Any],
           let clickAction = data["click_action"] as? String {
            return clickAction == "RELEVA_NOTIFICATION_CLICK"
        }

        return false
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
    private func buildContext(for request: PushRequest) -> [String: Any] {
        var context: [String: Any] = [:]

        // Session
        let session = sessionManager.getCurrentSession()
        context["sessionId"] = session.sessionId

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
    public func push(_ request: PushRequest) async throws -> RelevaResponse {
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