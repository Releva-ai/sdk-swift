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
        // Firebase dependency (optional - only if using FCM)
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "10.0.0")
    ],
    targets: [
        // Main SDK target
        .target(
            name: "RelevaSDK",
            dependencies: [
                .product(name: "FirebaseMessaging", package: "firebase-ios-sdk", condition: .when(platforms: [.iOS]))
            ],
            path: "Sources/RelevaSDK"
        ),
        // Notification Service Extension target
        .target(
            name: "RelevaNotificationExtension",
            dependencies: [
                "RelevaSDK",
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