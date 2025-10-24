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

    /// Callback for notification taps
    public var onNotificationTapped: ((UNNotificationResponse) -> Void)?

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
        print("RelevaSDK: Setting notification center delegate...")
        notificationCenter.delegate = self

        // Verify delegate was set
        if notificationCenter.delegate === self {
            print("RelevaSDK: ✓ Notification center delegate set successfully")
        } else {
            print("RelevaSDK: ✗ WARNING: Failed to set notification center delegate!")
            print("RelevaSDK: Current delegate: \(String(describing: notificationCenter.delegate))")
        }

        // Request authorization if needed
        notificationCenter.getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                self.requestAuthorization()
            }
        }

        // Register default category
        registerDefaultCategory()

        if config.enableDebugLogging {
            print("RelevaSDK: Notification service initialized")
        }
    }

    /// Request notification authorization
    public func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        let options: UNAuthorizationOptions = [.alert, .badge, .sound]

        notificationCenter.requestAuthorization(options: options) { granted, error in
            if let error = error {
                if self.config.enableDebugLogging {
                    print("RelevaSDK: Authorization error: \(error)")
                }
            }

            DispatchQueue.main.async {
                if granted {
                    self.safelyRegisterForRemoteNotifications()
                }
                completion?(granted)
            }

            if self.config.enableDebugLogging {
                print("RelevaSDK: Notification authorization: \(granted ? "granted" : "denied")")
            }
        }
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
            print("RelevaSDK: Registered notification category with button: \(buttonText)")
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
                    print("RelevaSDK: Failed to schedule notification: \(error)")
                }
            } else {
                if self.config.enableDebugLogging {
                    print("RelevaSDK: Notification scheduled: \(identifier)")
                }
            }
        }
    }

    /// Add image attachment to notification
    private func addImageAttachment(to content: UNMutableNotificationContent, from url: URL, completion: @escaping (UNNotificationContent) -> Void) {
        URLSession.shared.downloadTask(with: url) { localUrl, _, error in
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
                    print("RelevaSDK: Failed to create image attachment: \(error)")
                }
            }

            completion(content)
        }.resume()
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
        print("=== RELEVA SDK: NOTIFICATION WILL PRESENT (App in Foreground) ===")
        print("RelevaSDK: Title: \(notification.request.content.title)")
        print("RelevaSDK: Body: \(notification.request.content.body)")
        print("RelevaSDK: UserInfo: \(notification.request.content.userInfo)")

        // Check if it's a Releva notification
        let isReleva = notification.request.content.categoryIdentifier.hasPrefix("RELEVA")
        print("RelevaSDK: Is Releva: \(isReleva)")

        if isReleva {
            // Track delivered event
            if let client = RelevaClient.shared {
                client.trackEngagement(userInfo: notification.request.content.userInfo, type: .delivered)
            }

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

    /// Handle notification tap
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        print("=== RELEVA SDK: NOTIFICATION TAP RECEIVED ===")
        print("=== TIMESTAMP: \(Date()) ===")

        let notification = response.notification
        let content = notification.request.content
        let userInfo = content.userInfo
        let categoryId = content.categoryIdentifier

        // Log all notification details
        print("\nRelevaSDK: 📱 NOTIFICATION DETAILS:")
        print("RelevaSDK:   - Title: '\(content.title)'")
        print("RelevaSDK:   - Body: '\(content.body)'")
        print("RelevaSDK:   - Subtitle: '\(content.subtitle)'")
        print("RelevaSDK:   - Category ID: '\(categoryId)'")
        print("RelevaSDK:   - Action ID: '\(response.actionIdentifier)'")
        print("RelevaSDK:   - Badge: \(String(describing: content.badge))")

        print("\nRelevaSDK: 📦 FULL USER INFO (Raw):")
        print("RelevaSDK: \(userInfo)")

        print("\nRelevaSDK: 🔑 USER INFO KEYS:")
        print("RelevaSDK:   Keys found: \(userInfo.keys.map { String(describing: $0) }.joined(separator: ", "))")

        // Log each key-value pair
        print("\nRelevaSDK: 📋 KEY-VALUE PAIRS:")
        for (key, value) in userInfo {
            print("RelevaSDK:   [\(key)] = \(value)")

            // If it's a dictionary, log its contents too
            if let dict = value as? [String: Any] {
                print("RelevaSDK:     ↳ This is a dictionary with keys: \(dict.keys.joined(separator: ", "))")
                for (subKey, subValue) in dict {
                    print("RelevaSDK:       [\(subKey)] = \(subValue)")
                }
            }
        }

        print("\nRelevaSDK: 🔍 CHECKING FOR 'data' KEY:")
        if let data = userInfo["data"] as? [String: Any] {
            print("RelevaSDK:   ✓ Found 'data' dictionary!")
            print("RelevaSDK:   Data keys: \(data.keys.joined(separator: ", "))")
            for (key, value) in data {
                print("RelevaSDK:     data[\(key)] = \(value)")
            }
        } else {
            print("RelevaSDK:   ✗ No 'data' key found as dictionary")
            if let dataString = userInfo["data"] as? String {
                print("RelevaSDK:   ⚠️  'data' exists but is a STRING: \(dataString)")
            }
        }

        print("\nRelevaSDK: 🎯 FCM/GCM MESSAGE ID:")
        if let gcmMessageId = userInfo["gcm.message_id"] as? String {
            print("RelevaSDK:   ✓ FCM Message ID: \(gcmMessageId)")
        } else {
            print("RelevaSDK:   ✗ No FCM message ID found")
        }

        print("\nRelevaSDK: 🔔 APS (Apple Push Service) DATA:")
        if let aps = userInfo["aps"] as? [String: Any] {
            print("RelevaSDK:   ✓ Found 'aps': \(aps)")
        } else {
            print("RelevaSDK:   ✗ No 'aps' found")
        }

        let isReleva = categoryId.hasPrefix("RELEVA")
        print("\nRelevaSDK: 🏷️  Is Releva notification: \(isReleva)")

        // Handle ALL notifications, not just Releva ones (for Firebase compatibility)
        // Track engagement based on action
        if let client = RelevaClient.shared {
            print("RelevaSDK: Client available, tracking engagement...")
            if response.actionIdentifier == "RELEVA_ACTION_BUTTON" {
                client.trackEngagement(userInfo: userInfo, type: .clicked)
                print("RelevaSDK: ✓ Tracked as clicked")
            } else {
                client.trackEngagement(userInfo: userInfo, type: .opened)
                print("RelevaSDK: ✓ Tracked as opened")
            }
        } else {
            print("RelevaSDK: ⚠️ Client not available for tracking")
        }

        // Handle navigation for all notifications
        print("RelevaSDK: Attempting to handle navigation...")
        handleNotificationNavigation(from: userInfo)
        print("RelevaSDK: ✓ Navigation handled")

        // Call custom handler
        if let handler = onNotificationTapped {
            print("RelevaSDK: Calling custom tap handler...")
            handler(response)
            print("RelevaSDK: ✓ Custom handler called")
        } else {
            print("RelevaSDK: No custom tap handler set")
        }

        print("=== RELEVA SDK: NOTIFICATION TAP COMPLETE ===")
        completionHandler()
    }

    /// Handle navigation from notification
    private func handleNotificationNavigation(from userInfo: [AnyHashable: Any]) {
        print("RelevaSDK: handleNotificationNavigation called")
        print("RelevaSDK: userInfo keys: \(userInfo.keys)")

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
            print("RelevaSDK: ✓ Found 'data' wrapper (cross-platform format)")
            print("RelevaSDK: Data keys: \(data.keys)")
            handleNavigationData(data)
        } else {
            print("RelevaSDK: ℹ️ No 'data' wrapper, checking root level (Firebase iOS format)")
            // For Firebase iOS, custom data is at root level alongside "aps"
            handleNavigationData(stringUserInfo)
        }
    }

    /// Handle navigation with data dictionary
    private func handleNavigationData(_ data: [String: Any]) {
        print("RelevaSDK: handleNavigationData called with keys: \(data.keys)")

        guard let target = data["target"] as? String else {
            print("RelevaSDK: ⚠️ No 'target' key in data")
            return
        }

        print("RelevaSDK: Target type: \(target)")

        switch target {
        case "screen":
            if let screen = data["navigate_to_screen"] as? String {
                print("RelevaSDK: Navigating to screen: \(screen)")
                navigateToScreen(screen, parameters: data["navigate_to_parameters"] as? String)
            } else {
                print("RelevaSDK: ⚠️ No 'navigate_to_screen' in data")
            }

        case "url":
            if let urlString = data["navigate_to_url"] as? String {
                print("RelevaSDK: Navigating to URL: \(urlString)")
                guard let url = URL(string: urlString) else {
                    print("RelevaSDK: ✗ Invalid URL format: \(urlString)")
                    return
                }

                // Check if this is an internal deep link (custom scheme) or external URL
                if let scheme = url.scheme, scheme != "http" && scheme != "https" {
                    // Internal deep link - post notification for app to handle
                    print("RelevaSDK: Detected internal deep link, posting to app")
                    NotificationCenter.default.post(
                        name: Notification.Name("RelevaNavigateToURL"),
                        object: nil,
                        userInfo: ["url": url]
                    )
                } else {
                    // External URL - open in browser/external app
                    print("RelevaSDK: Opening external URL")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.safelyOpenURL(url)
                    }
                }
            } else {
                print("RelevaSDK: ⚠️ No 'navigate_to_url' in data")
            }

        default:
            print("RelevaSDK: ⚠️ Unknown target type: \(target)")
            break
        }
    }

    /// Navigate to screen within the app
    private func navigateToScreen(_ screen: String, parameters: String?) {
        // Post notification for app to handle navigation
        var userInfo: [String: Any] = ["screen": screen]

        if let parameters = parameters {
            userInfo["parameters"] = parameters
        }

        NotificationCenter.default.post(
            name: Notification.Name("RelevaNavigateToScreen"),
            object: nil,
            userInfo: userInfo
        )

        if config.enableDebugLogging {
            print("RelevaSDK: Navigate to screen: \(screen)")
        }
    }

    /// Safely register for remote notifications using runtime reflection
    /// Works in main app, gracefully skips in app extensions
    private func safelyRegisterForRemoteNotifications() {
        #if canImport(UIKit)
        // Use reflection to access UIApplication.shared - avoids compile-time errors in extensions
        guard let applicationClass = NSClassFromString("UIApplication") as? NSObject.Type else {
            if config.enableDebugLogging {
                print("RelevaSDK: ⚠️ UIApplication not available (running in app extension)")
            }
            return
        }

        let sharedSelector = NSSelectorFromString("sharedApplication")
        guard applicationClass.responds(to: sharedSelector),
              let sharedApplication = applicationClass.perform(sharedSelector)?.takeUnretainedValue() as? NSObject else {
            if config.enableDebugLogging {
                print("RelevaSDK: ⚠️ UIApplication not available (running in app extension)")
            }
            return
        }

        let registerSelector = NSSelectorFromString("registerForRemoteNotifications")
        _ = sharedApplication.perform(registerSelector)

        if config.enableDebugLogging {
            print("RelevaSDK: ✓ Registered for remote notifications")
        }
        #else
        if config.enableDebugLogging {
            print("RelevaSDK: ⚠️ Remote notifications not available on this platform")
        }
        #endif
    }

    /// Safely open URL using runtime reflection
    /// Works in main app, gracefully skips in app extensions
    private func safelyOpenURL(_ url: URL) {
        #if canImport(UIKit)
        // Use reflection to access UIApplication.shared - avoids compile-time errors in extensions
        guard let applicationClass = NSClassFromString("UIApplication") as? NSObject.Type else {
            print("RelevaSDK: ⚠️ UIApplication not available (running in app extension)")
            return
        }

        let sharedSelector = NSSelectorFromString("sharedApplication")
        guard applicationClass.responds(to: sharedSelector),
              let sharedApplication = applicationClass.perform(sharedSelector)?.takeUnretainedValue() as? NSObject else {
            print("RelevaSDK: ⚠️ UIApplication not available (running in app extension)")
            return
        }

        let canOpenSelector = NSSelectorFromString("canOpenURL:")
        let openSelector = NSSelectorFromString("openURL:options:completionHandler:")

        // Check if we can open the URL
        guard let canOpenMethod = sharedApplication.method(for: canOpenSelector) else {
            print("RelevaSDK: ✗ Cannot access canOpenURL method")
            return
        }

        typealias CanOpenURLFunction = @convention(c) (AnyObject, Selector, URL) -> Bool
        let canOpenURL = unsafeBitCast(canOpenMethod, to: CanOpenURLFunction.self)

        if canOpenURL(sharedApplication, canOpenSelector, url) {
            print("RelevaSDK: Opening URL...")

            // Open the URL
            if let openMethod = sharedApplication.method(for: openSelector) {
                typealias OpenURLFunction = @convention(c) (AnyObject, Selector, URL, [String: Any], ((Bool) -> Void)?) -> Void
                let openURL = unsafeBitCast(openMethod, to: OpenURLFunction.self)

                openURL(sharedApplication, openSelector, url, [:]) { success in
                    if success {
                        print("RelevaSDK: ✓ URL opened successfully")
                    } else {
                        print("RelevaSDK: ✗ Failed to open URL")
                    }
                }
            } else {
                print("RelevaSDK: ✗ Cannot access open method")
            }
        } else {
            print("RelevaSDK: ✗ Cannot open URL (not allowed)")
        }
        #else
        print("RelevaSDK: ⚠️ URL opening not available on this platform")
        #endif
    }
}