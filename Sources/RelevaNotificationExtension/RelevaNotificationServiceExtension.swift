import UserNotifications
import UIKit
import ImageIO
import FirebaseMessaging

/// Notification Service Extension for rich push notifications
/// Inherit from this class in your Notification Service Extension to enable rich notifications
open class RelevaNotificationServiceExtension: UNNotificationServiceExtension {
    open var contentHandler: ((UNNotificationContent) -> Void)?
    open var bestAttemptContent: UNMutableNotificationContent?

    /// Set once `reply(_:)` has called `contentHandler`, so a second reply — the classic race
    /// between an in-flight image download and `serviceExtensionTimeWillExpire` — is dropped
    /// instead of triggering "Ignoring additional replacement content replies".
    private var hasReplied = false

    /// Delivers `content` through `contentHandler` exactly once. `contentHandler` and
    /// `bestAttemptContent` are `open`, so a subclass that replies through them directly
    /// rather than through this method can still double-reply.
    private func reply(_ content: UNNotificationContent) {
        guard !hasReplied, let handler = contentHandler else { return }
        hasReplied = true
        contentHandler = nil
        handler(content)
    }

    open override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        guard let bestAttemptContent = bestAttemptContent else {
            reply(request.content)
            return
        }

        // Firebase attaches `fcm_options.image` and calls the handler it is given — wrapped so
        // that reply also only ever lands once.
        guard Self.isRelevaMessage(bestAttemptContent.userInfo) else {
            Messaging.serviceExtension().populateNotificationContent(bestAttemptContent) { [weak self] content in
                self?.reply(content)
            }
            return
        }

        guard let data = Self.extractRelevaData(bestAttemptContent.userInfo) else {
            reply(bestAttemptContent)
            return
        }

        processRelevaNotification(bestAttemptContent, data: data) { [weak self] processedContent in
            self?.reply(processedContent)
        }
    }

    open override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content.
        if let bestAttemptContent = bestAttemptContent {
            reply(bestAttemptContent)
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
                    fileExtension = Self.fileExtension(for: mimeType)
                } else {
                    fileExtension = "jpg"
                }
            }

            // UNNotificationAttachment displays only JPEG, PNG and GIF; WebP and HEIC are
            // transcoded to JPEG.
            fileExtension = fileExtension.lowercased()
            var tempUrl = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(fileExtension)
            let nativeFormats: Set<String> = ["jpg", "jpeg", "png", "gif"]

            do {
                if nativeFormats.contains(fileExtension) {
                    try FileManager.default.moveItem(at: localUrl, to: tempUrl)
                } else {
                    // A notification service extension gets roughly 24 MB total. Decoding a
                    // camera-resolution HEIC/WebP as a full `UIImage` can materialise a ~48 MB
                    // bitmap on its own and get the extension jetsammed — losing the whole
                    // enrichment, on exactly the formats this branch exists for. A bounded
                    // ImageIO thumbnail never holds the full-size decode; the attachment is
                    // only ever displayed at a few hundred points anyway.
                    guard let source = CGImageSourceCreateWithURL(localUrl as CFURL, nil),
                          let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                              kCGImageSourceCreateThumbnailFromImageAlways: true,
                              kCGImageSourceThumbnailMaxPixelSize: 2048,
                              kCGImageSourceCreateThumbnailWithTransform: true
                          ] as CFDictionary),
                          let jpeg = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.9) else {
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
                        UNNotificationAttachmentOptionsTypeHintKey: Self.typeHint(for: fileExtension),
                        UNNotificationAttachmentOptionsThumbnailHiddenKey: false
                    ]
                )

                content.attachments = [attachment]
            } catch {
                relevaLog("RelevaSDK: Failed to attach image: \(error)")
                // The success path hands `tempUrl` to the attachment, which owns it from then
                // on; a thrown error here means nothing ever will, and it would otherwise be
                // left behind in `NSTemporaryDirectory()`.
                try? FileManager.default.removeItem(at: tempUrl)
            }

            completion(content)
        }

        downloadTask.resume()
    }

    /// Get file extension for MIME type
    static func fileExtension(for mimeType: String) -> String {
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
    static func typeHint(for fileExtension: String) -> String {
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
