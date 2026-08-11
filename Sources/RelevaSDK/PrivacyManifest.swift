import Foundation

/// Locates the `PrivacyInfo.xcprivacy` that `Package.swift` copies into this
/// target's resource bundle.
///
/// SwiftPM generates `Bundle.module` per target and leaves it `internal`, so the
/// test target cannot reach `RelevaSDK`'s copy of it even with `@testable
/// import` — the symbol resolves against whichever module the reference is
/// compiled into. This accessor exists so `PrivacyManifestTests` can read the
/// manifest out of the bundle it actually ships in.
enum PrivacyManifest {

    /// The bundled manifest, or `nil` if the resource bundle exists but does
    /// not contain it.
    ///
    /// - Note: if the bundle itself is missing, SwiftPM's generated
    ///   `Bundle.module` accessor calls `fatalError` — the caller gets a
    ///   process trap, not `nil`.
    static var url: URL? {
        Bundle.module.url(forResource: "PrivacyInfo", withExtension: "xcprivacy")
    }
}
