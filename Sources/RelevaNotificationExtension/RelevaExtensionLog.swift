import Foundation
import os

/// Extension-process logging under the same subsystem as the SDK (`ai.releva.sdk`), category
/// `extension`, so Console.app shows image download and category registration for a push.
private let relevaExtensionLogger = Logger(subsystem: "ai.releva.sdk", category: "extension")

func relevaLog(_ message: String) {
    // `.debug` is memory-only (unlike `.notice`, which persists to the unified log store), and
    // the extension has no config to gate call sites on, so this is the only lever that keeps a
    // release build from writing image-download/category errors to disk.
    relevaExtensionLogger.debug("\(message, privacy: .public)")
}
