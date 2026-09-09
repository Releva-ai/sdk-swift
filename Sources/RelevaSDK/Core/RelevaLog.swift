import Foundation
import os

/// SDK diagnostic logging. Every message goes to the unified log (Xcode's console shows it while debugging)
/// under subsystem `ai.releva.sdk`, so Console.app can show SDK lines from a device even when
/// Xcode is not attached (cold launches, notification taps, background pushes).
///
/// Console.app: search field → token type "Subsystem" → `ai.releva.sdk`.
/// Terminal:    `log stream --predicate 'subsystem == "ai.releva.sdk"' --level info`
///
/// Most callers gate on `config.enableDebugLogging`; this function does not filter. `.debug`
/// (rather than `.notice`, which is written to the *persistent* unified log store) is what
/// makes an ungated call site here a live-console-only leak instead of one that ships banner
/// tokens and overlay internals to disk in a release build, recoverable from any sysdiagnose.
/// `.debug` still shows in Xcode's console and in `log stream`, which is this file's use case.
private let relevaLogger = Logger(subsystem: "ai.releva.sdk", category: "sdk")

func relevaLog(_ message: String) {
    relevaLogger.debug("\(message, privacy: .public)")
}
