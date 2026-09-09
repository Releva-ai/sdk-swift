import Foundation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

/// Service for handling local notifications
public class NotificationService: NSObject {
    // MARK: - Properties

    /// Configuration
    private let config: RelevaConfig

    /// Notification center
    private let notificationCenter = UNUserNotificationCenter.current()

    /// Whatever delegate the host app (or another SDK) had installed before `initialize()`
    /// overwrote it, so `shutdown()` can hand it back instead of leaving the slot `nil`.
    private weak var previousDelegate: UNUserNotificationCenterDelegate?

    /// Callback for notification taps
    public var onNotificationTapped: ((UNNotificationResponse) -> Void)?

    /// A navigation request the SDK posted through NotificationCenter that the host app may not
    /// have observed yet. On a cold launch from a notification tap, iOS delivers the tap to the SDK
    /// before most apps have registered their observers, so the post would otherwise be lost.
    /// Apps that register late call `consumePendingNavigation()` once their navigation is ready.
    public struct PendingNavigation {
        /// `RelevaNavigateToScreen`, `RelevaNavigateToURL` or `RelevaNavigateToInbox`.
        public let name: Notification.Name
        /// The same `userInfo` the NotificationCenter post carried.
        public let userInfo: [String: Any]
        public let postedAt: Date
    }

    /// The most recent navigation request, kept until consumed. Overwritten by a newer tap.
    public private(set) var pendingNavigation: PendingNavigation?

    /// Returns the most recent navigation request and clears it.
    @discardableResult
    public func consumePendingNavigation() -> PendingNavigation? {
        let pending = pendingNavigation
        pendingNavigation = nil
        return pending
    }

    /// Remember the request, then post it for observers that already exist.
    private func postNavigation(_ name: Notification.Name, userInfo: [String: Any]) {
        pendingNavigation = PendingNavigation(name: name, userInfo: userInfo, postedAt: Date())
        NotificationCenter.default.post(name: name, object: nil, userInfo: userInfo)
    }

    // MARK: - Initializers

    /// Initialize notification service
    /// - Parameter config: SDK configuration
    public init(config: RelevaConfig) {
        self.config = config
        super.init()
    }

    // MARK: - Public Methods

    /// Initialize notification service
    public func initialize() {
        if config.enableDebugLogging {
            relevaLog("RelevaSDK: Setting notification center delegate...")
        }
        // Idempotent: a second `initialize()` on the same instance (`enablePushEngagementTracking()`
        // is public and reuses the service) would otherwise capture `self` as "previous", and
        // `restorePreviousDelegate()` would then re-install this shut-down service instead of
        // whatever the host had before the *first* call — the only capture `previousDelegate`
        // (held `weak`) ever gets.
        if notificationCenter.delegate !== self {
            previousDelegate = notificationCenter.delegate
        }
        notificationCenter.delegate = self

        // Verify delegate was set
        if config.enableDebugLogging {
            if notificationCenter.delegate === self {
                relevaLog("RelevaSDK: ✓ Notification center delegate set successfully")
            } else {
                relevaLog("RelevaSDK: ✗ WARNING: Failed to set notification center delegate!")
                relevaLog("RelevaSDK: Current delegate: \(String(describing: notificationCenter.delegate))")
            }
        }

        // Request authorization if needed
        notificationCenter.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            Task {
                await self.requestAuthorization()
            }
        }

        // Register default category
        registerDefaultCategory()

        if config.enableDebugLogging {
            relevaLog("RelevaSDK: Notification service initialized")
        }
    }

    /// Hands the notification-centre delegate back to whatever it was before `initialize()`,
    /// if this instance is still the one installed (a later `RelevaClient` may already have
    /// replaced it). Called from `RelevaClient.shutdown()`.
    func restorePreviousDelegate() {
        guard notificationCenter.delegate === self else { return }
        notificationCenter.delegate = previousDelegate
    }

    /// Request notification authorization
    /// - Returns: Whether the user granted it. A thrown authorization error counts as denied,
    ///   which is how the 4.x completion handler reported it too.
    @discardableResult
    public func requestAuthorization() async -> Bool {
        let options: UNAuthorizationOptions = [.alert, .badge, .sound]

        var granted = false
        do {
            granted = try await notificationCenter.requestAuthorization(options: options)
        } catch {
            if config.enableDebugLogging {
                relevaLog("RelevaSDK: Authorization error: \(error)")
            }
        }

        if config.enableDebugLogging {
            relevaLog("RelevaSDK: Notification authorization: \(granted ? "granted" : "denied")")
        }

        if granted {
            // `safelyRegisterForRemoteNotifications` reaches `UIApplication`, so it has to run
            // on the main actor; this method itself is nonisolated and does not.
            await MainActor.run {
                self.safelyRegisterForRemoteNotifications()
            }
        }

        return granted
    }

    /// Display notification from data payload
    /// - Parameters:
    ///   - data: Notification data payload
    ///   - identifier: Unique identifier
    public func displayNotification(from data: [String: Any], identifier: String = UUID().uuidString) {
        let content = UNMutableNotificationContent()

        // Set basic content
        content.title = data["title"] as? String ?? ""
        content.body = data["body"] as? String ?? ""
        content.sound = .default

        // Set category for action buttons
        if data["button"] != nil {
            content.categoryIdentifier = "RELEVA_ACTION"
        } else {
            content.categoryIdentifier = "RELEVA_DEFAULT"
        }

        // Add data to userInfo
        content.userInfo = ["data": data]

        // Add image attachment if available
        if let imageUrlString = data["imageUrl"] as? String,
           let imageUrl = URL(string: imageUrlString) {
            addImageAttachment(to: content, from: imageUrl) { updatedContent in
                self.scheduleNotification(updatedContent, identifier: identifier)
            }
        } else {
            scheduleNotification(content, identifier: identifier)
        }
    }

    /// Register notification category with actions
    /// - Parameters:
    ///   - categoryId: Category identifier
    ///   - buttonText: Action button text
    public func registerNotificationCategory(categoryId: String = "RELEVA_ACTION", buttonText: String) {
        let action = UNNotificationAction(
            identifier: "RELEVA_ACTION_BUTTON",
            title: buttonText,
            options: [.foreground]
        )

        let category = UNNotificationCategory(
            identifier: categoryId,
            actions: [action],
            intentIdentifiers: [],
            options: []
        )

        notificationCenter.setNotificationCategories([category])

        if config.enableDebugLogging {
            relevaLog("RelevaSDK: Registered notification category with button: \(buttonText)")
        }
    }

    // MARK: - Private Methods

    /// Register default notification category
    private func registerDefaultCategory() {
        let defaultCategory = UNNotificationCategory(
            identifier: "RELEVA_DEFAULT",
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        let actionCategory = UNNotificationCategory(
            identifier: "RELEVA_ACTION",
            actions: [
                UNNotificationAction(
                    identifier: "RELEVA_ACTION_BUTTON",
                    title: "Open",
                    options: [.foreground]
                )
            ],
            intentIdentifiers: [],
            options: []
        )

        notificationCenter.getNotificationCategories { existingCategories in
            var categories = existingCategories
            categories.insert(defaultCategory)
            categories.insert(actionCategory)
            self.notificationCenter.setNotificationCategories(categories)
        }
    }

    /// Schedule notification for display
    private func scheduleNotification(_ content: UNNotificationContent, identifier: String) {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        notificationCenter.add(request) { error in
            if let error = error {
                if self.config.enableDebugLogging {
                    relevaLog("RelevaSDK: Failed to schedule notification: \(error)")
                }
            } else {
                if self.config.enableDebugLogging {
                    relevaLog("RelevaSDK: Notification scheduled: \(identifier)")
                }
            }
        }
    }

    /// Add image attachment to notification
    private func addImageAttachment(to content: UNMutableNotificationContent, from url: URL, completion: @escaping (UNNotificationContent) -> Void) {
        let task = URLSession.shared.downloadTask(with: url) { localUrl, _, error in
            guard let localUrl = localUrl, error == nil else {
                completion(content)
                return
            }

            // Move to temporary directory with proper extension
            let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(url.pathExtension.isEmpty ? "jpg" : url.pathExtension)

            do {
                try FileManager.default.moveItem(at: localUrl, to: tempUrl)

                let attachment = try UNNotificationAttachment(
                    identifier: "image",
                    url: tempUrl,
                    options: nil
                )

                content.attachments = [attachment]
            } catch {
                if self.config.enableDebugLogging {
                    relevaLog("RelevaSDK: Failed to create image attachment: \(error)")
                }
            }

            completion(content)
        }
        task.resume()
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {
    /// Handle notification when app is in foreground
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if config.enableDebugLogging {
            relevaLog("=== RELEVA SDK: NOTIFICATION WILL PRESENT (App in Foreground) ===")
            relevaLog("RelevaSDK: Title: \(notification.request.content.title)")
            relevaLog("RelevaSDK: Body: \(notification.request.content.body)")
            relevaLog("RelevaSDK: UserInfo: \(notification.request.content.userInfo)")
        }

        // Check if it's a Releva notification via userInfo (categoryIdentifier is unreliable for direct APNs)
        let userInfo = notification.request.content.userInfo
        let categoryPrefix = notification.request.content.categoryIdentifier.hasPrefix("RELEVA")
        let enableDebugLogging = config.enableDebugLogging

        Task { @MainActor in
            let isReleva = categoryPrefix
                || RelevaClient.shared?.isRelevaMessage(userInfo: userInfo) == true
            if enableDebugLogging {
                relevaLog("RelevaSDK: Is Releva: \(isReleva)")
            }

            if isReleva {
                // Track delivered event
                RelevaClient.shared?.trackEngagement(userInfo: userInfo, type: .delivered)

                // Show notification even when app is in foreground
                if #available(iOS 14.0, *) {
                    completionHandler([.banner, .sound, .badge])
                } else {
                    completionHandler([.alert, .sound, .badge])
                }
            } else {
                // Let other notifications through
                completionHandler([])
            }
        }
    }

    /// Handle notification tap
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let notification = response.notification
        let content = notification.request.content
        let userInfo = content.userInfo
        let categoryId = content.categoryIdentifier

        if config.enableDebugLogging {
            relevaLog("=== RELEVA SDK: NOTIFICATION TAP RECEIVED ===")
            relevaLog("=== TIMESTAMP: \(Date()) ===")

            relevaLog("\nRelevaSDK: 📱 NOTIFICATION DETAILS:")
            relevaLog("RelevaSDK:   - Title: '\(content.title)'")
            relevaLog("RelevaSDK:   - Body: '\(content.body)'")
            relevaLog("RelevaSDK:   - Subtitle: '\(content.subtitle)'")
            relevaLog("RelevaSDK:   - Category ID: '\(categoryId)'")
            relevaLog("RelevaSDK:   - Action ID: '\(response.actionIdentifier)'")
            relevaLog("RelevaSDK:   - Badge: \(String(describing: content.badge))")

            relevaLog("\nRelevaSDK: 📦 FULL USER INFO (Raw):")
            relevaLog("RelevaSDK: \(userInfo)")

            relevaLog("\nRelevaSDK: 🔑 USER INFO KEYS:")
            relevaLog("RelevaSDK:   Keys found: \(userInfo.keys.map { String(describing: $0) }.joined(separator: ", "))")

            relevaLog("\nRelevaSDK: 📋 KEY-VALUE PAIRS:")
            for (key, value) in userInfo {
                relevaLog("RelevaSDK:   [\(key)] = \(value)")

                if let dict = value as? [String: Any] {
                    relevaLog("RelevaSDK:     ↳ This is a dictionary with keys: \(dict.keys.joined(separator: ", "))")
                    for (subKey, subValue) in dict {
                        relevaLog("RelevaSDK:       [\(subKey)] = \(subValue)")
                    }
                }
            }

            relevaLog("\nRelevaSDK: 🔍 CHECKING FOR 'data' KEY:")
            if let data = userInfo["data"] as? [String: Any] {
                relevaLog("RelevaSDK:   ✓ Found 'data' dictionary!")
                relevaLog("RelevaSDK:   Data keys: \(data.keys.joined(separator: ", "))")
                for (key, value) in data {
                    relevaLog("RelevaSDK:     data[\(key)] = \(value)")
                }
            } else {
                relevaLog("RelevaSDK:   ✗ No 'data' key found as dictionary")
                if let dataString = userInfo["data"] as? String {
                    relevaLog("RelevaSDK:   ⚠️  'data' exists but is a STRING: \(dataString)")
                }
            }

            relevaLog("\nRelevaSDK: 🎯 FCM/GCM MESSAGE ID:")
            if let gcmMessageId = userInfo["gcm.message_id"] as? String {
                relevaLog("RelevaSDK:   ✓ FCM Message ID: \(gcmMessageId)")
            } else {
                relevaLog("RelevaSDK:   ✗ No FCM message ID found")
            }

            relevaLog("\nRelevaSDK: 🔔 APS (Apple Push Service) DATA:")
            if let aps = userInfo["aps"] as? [String: Any] {
                relevaLog("RelevaSDK:   ✓ Found 'aps': \(aps)")
            } else {
                relevaLog("RelevaSDK:   ✗ No 'aps' found")
            }

            // Same test as willPresent: the category is REQUIRE_INTERACTION on pushes the
            // extension did not touch, so the category prefix alone under-reports.
            let isReleva = categoryId.hasPrefix("RELEVA")
                || (userInfo["click_action"] as? String)?.hasPrefix("RELEVA_") == true
                || ((userInfo["data"] as? [String: Any])?["click_action"] as? String)?.hasPrefix("RELEVA_") == true
            relevaLog("\nRelevaSDK: 🏷️  Is Releva notification: \(isReleva)")
        }

        // Handle ALL notifications, not just Releva ones (for Firebase compatibility)
        // Track engagement based on action
        let actionIdentifier = response.actionIdentifier
        let enableDebugLogging = config.enableDebugLogging
        Task { @MainActor in
            if let client = RelevaClient.shared {
                if enableDebugLogging {
                    relevaLog("RelevaSDK: Client available, tracking engagement...")
                }
                if actionIdentifier == "RELEVA_ACTION_BUTTON" {
                    client.trackEngagement(userInfo: userInfo, type: .clicked)
                    if enableDebugLogging {
                        relevaLog("RelevaSDK: ✓ Tracked as clicked")
                    }
                } else {
                    client.trackEngagement(userInfo: userInfo, type: .opened)
                    if enableDebugLogging {
                        relevaLog("RelevaSDK: ✓ Tracked as opened")
                    }
                }
            } else if enableDebugLogging {
                relevaLog("RelevaSDK: ⚠️ Client not available for tracking")
            }
        }

        // Handle navigation for all notifications
        if config.enableDebugLogging {
            relevaLog("RelevaSDK: Attempting to handle navigation...")
        }
        handleNotificationNavigation(from: userInfo)
        if config.enableDebugLogging {
            relevaLog("RelevaSDK: ✓ Navigation handled")
        }

        // Call custom handler
        if let handler = onNotificationTapped {
            if config.enableDebugLogging {
                relevaLog("RelevaSDK: Calling custom tap handler...")
            }
            handler(response)
            if config.enableDebugLogging {
                relevaLog("RelevaSDK: ✓ Custom handler called")
            }
        } else if config.enableDebugLogging {
            relevaLog("RelevaSDK: No custom tap handler set")
        }

        if config.enableDebugLogging {
            relevaLog("=== RELEVA SDK: NOTIFICATION TAP COMPLETE ===")
        }
        completionHandler()
    }

    /// Handle navigation from notification
    private func handleNotificationNavigation(from userInfo: [AnyHashable: Any]) {
        if config.enableDebugLogging {
            relevaLog("RelevaSDK: handleNotificationNavigation called")
            relevaLog("RelevaSDK: userInfo keys: \(userInfo.keys)")
        }

        // Convert AnyHashable keys to String keys for easier handling
        var stringUserInfo: [String: Any] = [:]
        for (key, value) in userInfo {
            if let stringKey = key as? String {
                stringUserInfo[stringKey] = value
            }
        }

        // Firebase iOS notifications can have data in two formats:
        // 1. Wrapped in "data" key: {"data": {"target": "..."}}
        // 2. At root level: {"target": "...", "aps": {...}}

        if let data = stringUserInfo["data"] as? [String: Any] {
            if config.enableDebugLogging {
                relevaLog("RelevaSDK: ✓ Found 'data' wrapper (cross-platform format)")
                relevaLog("RelevaSDK: Data keys: \(data.keys)")
            }
            handleNavigationData(data)
        } else {
            if config.enableDebugLogging {
                relevaLog("RelevaSDK: ℹ️ No 'data' wrapper, checking root level (Firebase iOS format)")
            }
            // For Firebase iOS, custom data is at root level alongside "aps"
            handleNavigationData(stringUserInfo)
        }
    }

    /// Handle navigation with data dictionary
    private func handleNavigationData(_ data: [String: Any]) {
        if config.enableDebugLogging {
            relevaLog("RelevaSDK: handleNavigationData called with keys: \(data.keys)")
        }

        // Handle inbox sync signal
        if let inboxSync = data["inbox_sync"] as? String, inboxSync == "true" {
            if config.enableDebugLogging {
                relevaLog("RelevaSDK: Inbox sync signal received")
            }
            InboxService.shared.handleSyncSignal()
        }

        guard let target = data["target"] as? String else {
            if config.enableDebugLogging {
                relevaLog("RelevaSDK: ⚠️ No 'target' key in data")
            }
            return
        }

        if config.enableDebugLogging {
            relevaLog("RelevaSDK: Target type: \(target)")
        }

        switch target {
        case "screen":
            if let screen = data["navigate_to_screen"] as? String {
                if config.enableDebugLogging {
                    relevaLog("RelevaSDK: Navigating to screen: \(screen)")
                }
                navigateToScreen(screen, parameters: data["navigate_to_parameters"] as? String)
            } else if config.enableDebugLogging {
                relevaLog("RelevaSDK: ⚠️ No 'navigate_to_screen' in data")
            }

        case "url":
            if let urlString = data["navigate_to_url"] as? String {
                if config.enableDebugLogging {
                    relevaLog("RelevaSDK: Navigating to URL: \(urlString)")
                }
                guard let url = URL(string: urlString) else {
                    if config.enableDebugLogging {
                        relevaLog("RelevaSDK: ✗ Invalid URL format: \(urlString)")
                    }
                    return
                }

                // Check if this is an internal deep link (custom scheme) or external URL
                if let scheme = url.scheme, scheme != "http" && scheme != "https" {
                    // Internal deep link - post notification for app to handle
                    if config.enableDebugLogging {
                        relevaLog("RelevaSDK: Detected internal deep link, posting to app")
                    }
                    postNavigation(Notification.Name("RelevaNavigateToURL"), userInfo: ["url": url])
                } else {
                    // External URL - open in browser/external app
                    if config.enableDebugLogging {
                        relevaLog("RelevaSDK: Opening external URL")
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.safelyOpenURL(url)
                    }
                }
            } else if config.enableDebugLogging {
                relevaLog("RelevaSDK: ⚠️ No 'navigate_to_url' in data")
            }

        case "inbox":
            if config.enableDebugLogging {
                relevaLog("RelevaSDK: Navigating to inbox")
            }
            navigateToInbox(parameters: data["navigate_to_parameters"] as? String)

        default:
            if config.enableDebugLogging {
                relevaLog("RelevaSDK: ⚠️ Unknown target type: \(target)")
            }
        }
    }

    /// Navigate to screen within the app
    private func navigateToScreen(_ screen: String, parameters: String?) {
        // Post notification for app to handle navigation
        var userInfo: [String: Any] = ["screen": screen]

        if let parameters = parameters {
            userInfo["parameters"] = parameters
            // Parse JSON parameters to extract structured data like inboxMessageId
            if let data = parameters.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                userInfo["parsedParameters"] = parsed
            }
        }

        postNavigation(Notification.Name("RelevaNavigateToScreen"), userInfo: userInfo)

        if config.enableDebugLogging {
            relevaLog("RelevaSDK: Navigate to screen: \(screen)")
        }
    }

    /// Navigate to inbox within the app
    private func navigateToInbox(parameters: String?) {
        var userInfo: [String: Any] = [:]

        if let parameters = parameters {
            userInfo["parameters"] = parameters
            if let data = parameters.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                userInfo["parsedParameters"] = parsed
            }
        }

        postNavigation(Notification.Name("RelevaNavigateToInbox"), userInfo: userInfo)

        if config.enableDebugLogging {
            relevaLog("RelevaSDK: Navigate to inbox posted")
        }
    }

    /// Safely register for remote notifications using runtime reflection
    /// Works in main app, gracefully skips in app extensions
    private func safelyRegisterForRemoteNotifications() {
        #if canImport(UIKit)
        // Use reflection to access UIApplication.shared - avoids compile-time errors in extensions
        guard let applicationClass = NSClassFromString("UIApplication") as? NSObject.Type else {
            if config.enableDebugLogging {
                relevaLog("RelevaSDK: ⚠️ UIApplication not available (running in app extension)")
            }
            return
        }

        let sharedSelector = NSSelectorFromString("sharedApplication")
        guard applicationClass.responds(to: sharedSelector),
              let sharedApplication = applicationClass.perform(sharedSelector)?.takeUnretainedValue() as? NSObject else {
            if config.enableDebugLogging {
                relevaLog("RelevaSDK: ⚠️ UIApplication not available (running in app extension)")
            }
            return
        }

        let registerSelector = NSSelectorFromString("registerForRemoteNotifications")
        _ = sharedApplication.perform(registerSelector)

        if config.enableDebugLogging {
            relevaLog("RelevaSDK: ✓ Registered for remote notifications")
        }
        #else
        if config.enableDebugLogging {
            relevaLog("RelevaSDK: ⚠️ Remote notifications not available on this platform")
        }
        #endif
    }

    /// Safely open URL using runtime reflection
    /// Works in main app, gracefully skips in app extensions
    private func safelyOpenURL(_ url: URL) {
        #if canImport(UIKit)
        // Use reflection to access UIApplication.shared - avoids compile-time errors in extensions
        guard let applicationClass = NSClassFromString("UIApplication") as? NSObject.Type else {
            if config.enableDebugLogging {
                relevaLog("RelevaSDK: ⚠️ UIApplication not available (running in app extension)")
            }
            return
        }

        let sharedSelector = NSSelectorFromString("sharedApplication")
        guard applicationClass.responds(to: sharedSelector),
              let sharedApplication = applicationClass.perform(sharedSelector)?.takeUnretainedValue() as? NSObject else {
            if config.enableDebugLogging {
                relevaLog("RelevaSDK: ⚠️ UIApplication not available (running in app extension)")
            }
            return
        }

        let canOpenSelector = NSSelectorFromString("canOpenURL:")
        let openSelector = NSSelectorFromString("openURL:options:completionHandler:")

        // Check if we can open the URL
        guard let canOpenMethod = sharedApplication.method(for: canOpenSelector) else {
            if config.enableDebugLogging {
                relevaLog("RelevaSDK: ✗ Cannot access canOpenURL method")
            }
            return
        }

        typealias CanOpenURLFunction = @convention(c) (AnyObject, Selector, URL) -> Bool
        let canOpenURL = unsafeBitCast(canOpenMethod, to: CanOpenURLFunction.self)

        if canOpenURL(sharedApplication, canOpenSelector, url) {
            if config.enableDebugLogging {
                relevaLog("RelevaSDK: Opening URL...")
            }

            // Open the URL
            if let openMethod = sharedApplication.method(for: openSelector) {
                typealias OpenURLFunction = @convention(c) (AnyObject, Selector, URL, [String: Any], ((Bool) -> Void)?) -> Void
                let openURL = unsafeBitCast(openMethod, to: OpenURLFunction.self)

                openURL(sharedApplication, openSelector, url, [:]) { success in
                    if self.config.enableDebugLogging {
                        if success {
                            relevaLog("RelevaSDK: ✓ URL opened successfully")
                        } else {
                            relevaLog("RelevaSDK: ✗ Failed to open URL")
                        }
                    }
                }
            } else if config.enableDebugLogging {
                relevaLog("RelevaSDK: ✗ Cannot access open method")
            }
        } else if config.enableDebugLogging {
            relevaLog("RelevaSDK: ✗ Cannot open URL (not allowed)")
        }
        #else
        if config.enableDebugLogging {
            relevaLog("RelevaSDK: ⚠️ URL opening not available on this platform")
        }
        #endif
    }
}

// `userInfo: [String: Any]` isn't provably `Sendable`, but every read and write of a
// `PendingNavigation` happens on the main thread (`postNavigation` runs there, and so does
// every UIKit/push delivery path that constructs one), so `@unchecked` is safe in practice.
extension NotificationService.PendingNavigation: @unchecked Sendable {}
