import Foundation
import os

/// SDK diagnostic logging. Every message goes to the unified log (Xcode's console shows it while debugging)
/// under subsystem `ai.releva.sdk`, so Console.app can show SDK lines from a device even when
/// Xcode is not attached (cold launches, notification taps, background pushes).
///
/// Console.app: search field → token type "Subsystem" → `ai.releva.sdk`.
/// Terminal:    `log stream --predicate 'subsystem == "ai.releva.sdk"' --level info`
///
/// Callers already gate on `config.enableDebugLogging`; this function does not filter.
private let relevaLogger = Logger(subsystem: "ai.releva.sdk", category: "sdk")

func relevaLog(_ message: String) {
    relevaLogger.notice("\(message, privacy: .public)")
}
