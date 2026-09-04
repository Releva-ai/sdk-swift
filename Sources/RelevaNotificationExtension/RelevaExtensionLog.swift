import Foundation
import os

/// Extension-process logging under the same subsystem as the SDK (`ai.releva.sdk`), category
/// `extension`, so Console.app shows image download and category registration for a push.
private let relevaExtensionLogger = Logger(subsystem: "ai.releva.sdk", category: "extension")

func relevaLog(_ message: String) {
    relevaExtensionLogger.notice("\(message, privacy: .public)")
}
