// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RelevaSDK",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        // Main SDK library
        .library(
            name: "RelevaSDK",
            targets: ["RelevaSDK"]
        ),
        // Notification Service Extension
        .library(
            name: "RelevaNotificationExtension",
            targets: ["RelevaNotificationExtension"]
        )
    ],
    dependencies: [
        // Firebase dependency (optional - only if using FCM).
        //
        // An explicit range, not `from:`: `from:` means `.upToNextMajor`, so it
        // capped this at `< 12.0.0` and left the graph unsatisfiable for an app
        // already on Firebase 12. Spanning both majors rather than raising the
        // floor to 12 keeps consumers still on 11.x resolving.
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", "11.15.0"..<"13.0.0")
    ],
    targets: [
        // Main SDK target
        .target(
            name: "RelevaSDK",
            dependencies: [
                .product(name: "FirebaseMessaging", package: "firebase-ios-sdk", condition: .when(platforms: [.iOS]))
            ],
            path: "Sources/RelevaSDK",
            // `.copy`, not `.process`: the manifest must reach the product
            // byte-for-byte, and no platform build rule applies to `.xcprivacy`
            // anyway. Either way it lands at the root of the generated
            // `RelevaSDK_RelevaSDK.bundle`, which is where Apple reads it from.
            resources: [.copy("PrivacyInfo.xcprivacy")]
        ),
        // Notification Service Extension target
        .target(
            name: "RelevaNotificationExtension",
            dependencies: [
                .product(name: "FirebaseMessaging", package: "firebase-ios-sdk", condition: .when(platforms: [.iOS]))
            ],
            path: "Sources/RelevaNotificationExtension"
        ),
        // Test target
        .testTarget(
            name: "RelevaSDKTests",
            dependencies: ["RelevaSDK"],
            path: "Tests/RelevaSDKTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)