import UserNotifications
import UIKit
import FirebaseMessaging

/// Notification Service Extension for rich push notifications
/// Inherit from this class in your Notification Service Extension to enable rich notifications
open class RelevaNotificationServiceExtension: UNNotificationServiceExtension {
    open var contentHandler: ((UNNotificationContent) -> Void)?
    open var bestAttemptContent: UNMutableNotificationContent?

    open override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        guard let bestAttemptContent = bestAttemptContent else {
            contentHandler(request.content)
            return
        }

        // Firebase attaches `fcm_options.image` and calls the handler it is given. Only a
        // non-Releva push lets that reply reach the system; a Releva push is completed once,
        // below.
        let isRelevaPush = Self.isRelevaMessage(bestAttemptContent.userInfo)
        if !isRelevaPush {
            Messaging.serviceExtension().populateNotificationContent(
                bestAttemptContent,
                withContentHandler: contentHandler
            )
            return
        }

        // Check if this is a Releva notification
        // Firebase iOS puts custom data at root level, not in "data" wrapper
        var relevaData: [String: Any]?
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

    open override func serviceExtensionTimeWillExpire() {
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
            // `Set.insert` keeps an existing category, so drop the stale RELEVA_DYNAMIC before
            // inserting the one with the new label.
            var categories = existingCategories.filter { $0.identifier != "RELEVA_DYNAMIC" }
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

            // UNNotificationAttachment displays only JPEG, PNG and GIF; WebP and HEIC are
            // transcoded to JPEG.
            var tempUrl = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(fileExtension)
            let nativeFormats: Set<String> = ["jpg", "jpeg", "png", "gif"]

            do {
                if nativeFormats.contains(fileExtension.lowercased()) {
                    try FileManager.default.moveItem(at: localUrl, to: tempUrl)
                } else {
                    let data = try Data(contentsOf: localUrl)
                    guard let image = UIImage(data: data),
                          let jpeg = image.jpegData(compressionQuality: 0.9) else {
                        relevaLog("RelevaSDK: Image format '\(fileExtension)' could not be decoded, delivering without attachment")
                        completion(content)
                        return
                    }
                    tempUrl = tempUrl.deletingPathExtension().appendingPathExtension("jpg")
                    fileExtension = "jpg"
                    try jpeg.write(to: tempUrl)
                }

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
                relevaLog("RelevaSDK: Failed to attach image: \(error)")
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
