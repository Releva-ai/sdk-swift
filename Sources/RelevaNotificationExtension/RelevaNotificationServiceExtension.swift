import UserNotifications
import FirebaseMessaging

/// Notification Service Extension for rich push notifications
public class RelevaNotificationServiceExtension: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override public func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        guard let bestAttemptContent = bestAttemptContent else {
            contentHandler(request.content)
            return
        }

        // Handle Firebase Messaging
        Messaging.serviceExtension().populateNotificationContent(
            bestAttemptContent,
            withContentHandler: contentHandler
        )

        // Check if this is a Releva notification
        // Firebase iOS puts custom data at root level, not in "data" wrapper
        var relevaData: [String: Any]? = nil
        var isReleva = false

        // Check root level first (iOS format)
        if let clickAction = bestAttemptContent.userInfo["click_action"] as? String,
           clickAction == "RELEVA_NOTIFICATION_CLICK" {
            // Convert userInfo to String dictionary
            var data: [String: Any] = [:]
            for (key, value) in bestAttemptContent.userInfo {
                if let stringKey = key as? String {
                    data[stringKey] = value
                }
            }
            relevaData = data
            isReleva = true
        }
        // Also check "data" wrapper (cross-platform format)
        else if let data = bestAttemptContent.userInfo["data"] as? [String: Any],
                let clickAction = data["click_action"] as? String,
                clickAction == "RELEVA_NOTIFICATION_CLICK" {
            relevaData = data
            isReleva = true
        }

        if isReleva, let data = relevaData {
            // Process Releva notification
            processRelevaNotification(bestAttemptContent, data: data) { processedContent in
                contentHandler(processedContent)
            }
        } else {
            // Not a Releva notification, deliver as-is
            contentHandler(bestAttemptContent)
        }
    }

    override public func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content.
        if let contentHandler = contentHandler, let bestAttemptContent = bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

    // MARK: - Private Methods

    /// Process Releva notification
    private func processRelevaNotification(_ content: UNMutableNotificationContent, data: [String: Any], completion: @escaping (UNNotificationContent) -> Void) {

        // Set title and body from data if available
        if let title = data["title"] as? String {
            content.title = title
        }

        if let body = data["body"] as? String {
            content.body = body
        }

        // Set sound
        content.sound = .default

        // Register category with custom button if needed
        if let buttonText = data["button"] as? String, !buttonText.isEmpty {
            registerDynamicCategory(buttonText: buttonText)
            content.categoryIdentifier = "RELEVA_DYNAMIC"
        } else {
            content.categoryIdentifier = "RELEVA_DEFAULT"
        }

        // Add image attachment if available
        if let imageUrlString = data["imageUrl"] as? String,
           let imageUrl = URL(string: imageUrlString) {
            downloadAndAttachImage(to: content, from: imageUrl) { updatedContent in
                completion(updatedContent)
            }
        } else {
            completion(content)
        }
    }

    /// Register dynamic notification category
    private func registerDynamicCategory(buttonText: String) {
        let action = UNNotificationAction(
            identifier: "RELEVA_ACTION_BUTTON",
            title: buttonText,
            options: [.foreground]
        )

        let category = UNNotificationCategory(
            identifier: "RELEVA_DYNAMIC",
            actions: [action],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().getNotificationCategories { existingCategories in
            var categories = existingCategories
            categories.insert(category)
            UNUserNotificationCenter.current().setNotificationCategories(categories)
        }
    }

    /// Download and attach image to notification
    private func downloadAndAttachImage(to content: UNMutableNotificationContent, from url: URL, completion: @escaping (UNNotificationContent) -> Void) {
        let downloadTask = URLSession.shared.downloadTask(with: url) { localUrl, response, error in
            guard let localUrl = localUrl, error == nil else {
                completion(content)
                return
            }

            // Get file extension from response or URL
            var fileExtension = url.pathExtension
            if fileExtension.isEmpty {
                if let mimeType = (response as? HTTPURLResponse)?.mimeType {
                    fileExtension = self.fileExtension(for: mimeType)
                } else {
                    fileExtension = "jpg"
                }
            }

            // Move to temporary location with proper extension
            let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(fileExtension)

            do {
                try FileManager.default.moveItem(at: localUrl, to: tempUrl)

                // Create attachment
                let attachment = try UNNotificationAttachment(
                    identifier: "image",
                    url: tempUrl,
                    options: [
                        UNNotificationAttachmentOptionsTypeHintKey: self.typeHint(for: fileExtension),
                        UNNotificationAttachmentOptionsThumbnailHiddenKey: false
                    ]
                )

                content.attachments = [attachment]
            } catch {
                print("RelevaSDK: Failed to attach image: \(error)")
            }

            completion(content)
        }

        downloadTask.resume()
    }

    /// Get file extension for MIME type
    private func fileExtension(for mimeType: String) -> String {
        switch mimeType.lowercased() {
        case "image/jpeg", "image/jpg":
            return "jpg"
        case "image/png":
            return "png"
        case "image/gif":
            return "gif"
        case "image/webp":
            return "webp"
        case "image/heic":
            return "heic"
        case "image/heif":
            return "heif"
        default:
            return "jpg"
        }
    }

    /// Get type hint for file extension
    private func typeHint(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "jpg", "jpeg":
            return "public.jpeg"
        case "png":
            return "public.png"
        case "gif":
            return "com.compuserve.gif"
        case "webp":
            return "public.webp"
        case "heic":
            return "public.heic"
        case "heif":
            return "public.heif"
        default:
            return "public.image"
        }
    }
}

// MARK: - Releva Message Detection

extension RelevaNotificationServiceExtension {

    /// Check if notification is from Releva
    public static func isRelevaMessage(_ userInfo: [AnyHashable: Any]) -> Bool {
        // Firebase iOS puts custom data at root level (iOS format)
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

    /// Extract Releva data from notification
    public static func extractRelevaData(_ userInfo: [AnyHashable: Any]) -> [String: Any]? {
        // Try "data" wrapper first (cross-platform format)
        if let data = userInfo["data"] as? [String: Any] {
            return data
        }

        // For iOS format, convert root level userInfo to String dictionary
        var data: [String: Any] = [:]
        for (key, value) in userInfo {
            if let stringKey = key as? String, stringKey != "aps" {
                data[stringKey] = value
            }
        }
        return data.isEmpty ? nil : data
    }
}