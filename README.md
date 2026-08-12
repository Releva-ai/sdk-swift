# Releva SDK for iOS

Native iOS SDK for integrating Releva's AI-powered e-commerce personalization platform into your iOS applications.

## Features

### E-commerce Personalization
- **Product Recommendations** - AI-powered product suggestions with real-time personalization
- **Dynamic Content** - Personalized banners, stories, and content blocks based on user behavior
- **Advanced Filtering** - Complex product filtering with nested AND/OR logic, price ranges, custom fields
- **Smart Search** - Search tracking with result optimization and recommendation integration

### Mobile Tracking & Analytics
- **E-commerce Events** - Product views, cart changes, checkout tracking, search analytics
- **Custom Events** - Flexible event system for business-specific tracking needs
- **Session Management** - Automatic 24-hour session handling

### Push Notifications
- **Firebase Integration** - Complete FCM push notification system
- **Rich Notifications** - Images, action buttons, and deep linking support
- **Navigation** - Automatic screen and URL navigation from notification taps
- **Engagement Analytics** - Delivered, opened, clicked tracking
- **Notification Service Extension** - Background processing for rich media

### In-App Banners
- **Multiple Display Types** - Popup modals, bar overlays (top/bottom), flyout side panels, and static inline banners
- **Server-Driven Triggers** - immediately, delaySeconds, scrollPercentage, cartChanged, wishlistChanged
- **Unlayer Rendering** - Native SwiftUI rendering of Unlayer design JSON (images, text, headings, buttons, dividers)
- **Automatic Tracking** - Impression, click, and dismiss events

### Stories
- **Full-Screen Viewer** - Instagram/Facebook-style multi-slide story viewer
- **Auto-Advance** - Configurable duration per slide with animated progress bars
- **Navigation** - Tap left/right halves, swipe, or use close button
- **End Behaviors** - dismiss, loop, or stayOnLast
- **Queue System** - Multiple stories queued and shown sequentially
- **Automatic Tracking** - Impression, slide view, slide click, complete, close events

### NPS Surveys
- **Server-Driven UI** - Colors, button styles, labels, and dark mode all controlled from the dashboard
- **Trigger System** - appOpen, sessionCount, customEvent, screenView triggers
- **3-Step Flow** - Score selection (0-10) → follow-up comment → thank you (auto-dismiss)
- **Session Suppression** - Survey shown once per session, with cancel event support

### App Inbox
- **Persistent Messages** - In-app message centre where messages survive until read, deleted, or expired
- **Rich Content** - Messages rendered with Unlayer design JSON, fully personalized per user
- **Real-Time Sync** - Silent push notifications trigger automatic inbox refresh
- **Optimistic Updates** - Mark read, mark all read, and delete with instant UI feedback and rollback
- **Cursor Pagination** - Efficient infinite scroll with server-side cursor pagination
- **Local Caching** - Messages cached locally with 5-minute stale detection

### Flexible Configuration
- **Modular Setup** - Enable only needed features (tracking, push, analytics)
- **Endpoint Override** - Runtime API endpoint override for local development
- **Offline Support** - Events queued and sent when connection is available

## Requirements

- iOS 15.0+ (`firebase-ios-sdk` 12.x declares the same iOS 15 floor, so which
  Firebase major you resolve does not move this)
- Xcode: whatever the Firebase version you resolve requires. SPM picks the
  newest `firebase-ios-sdk` your own constraints allow, and Firebase raises its
  toolchain floor over time — including within the 12.x series — so check
  [Firebase's iOS release notes](https://firebase.google.com/support/release-notes/ios)
  for the version you land on. This package accepts `>= 11.15.0, < 13.0.0`, so
  capping yourself to `"11.15.0"..<"12.0.0"` is a supported way to stay on an
  older toolchain: Xcode 16.2 is enough for `firebase-ios-sdk` 11.15.
- Swift 5.7 language mode or later (the package declares `swift-tools-version: 5.7`)

## Installation

Swift Package Manager is the only supported distribution channel. The package
exposes two library products:

- `RelevaSDK` — add to your app target.
- `RelevaNotificationExtension` — add to your Notification Service Extension
  target, if you want rich push notifications.

`firebase-ios-sdk` (`>= 11.15.0, < 13.0.0`, i.e. Firebase 11 or 12) is resolved
automatically as a dependency, but SPM only attaches package *products* to
targets that ask for them. The push notification setup below calls
`Messaging.messaging()` directly from your own `AppDelegate`, so your app target
also needs to depend on `FirebaseMessaging` (and `FirebaseCore`, which it
requires) explicitly — see below.

### In a `Package.swift` manifest

Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/Releva-ai/sdk-swift.git", from: "5.0.0"),
    // Required because the push setup below calls Messaging.messaging() from
    // your own code: SPM only lets a target use products from packages this
    // manifest declares directly, so a transitive resolve is not enough.
    //
    // Firebase 11 and 12 both work. `from: "11.15.0"` would also resolve, but
    // it means `< 12.0.0`, so it pins you to Firebase 11 — which is a
    // reasonable choice on an older Xcode; see Requirements above.
    .package(url: "https://github.com/firebase/firebase-ios-sdk.git", "11.15.0"..<"13.0.0")
]
```

and depend on the products from your target:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "RelevaSDK", package: "sdk-swift"),
        .product(name: "FirebaseMessaging", package: "firebase-ios-sdk"),
        .product(name: "FirebaseCore", package: "firebase-ios-sdk")
    ]
)
```

### In Xcode

1. File → Add Package Dependencies…
2. Enter: `https://github.com/Releva-ai/sdk-swift.git`
3. Dependency Rule: "Up to Next Major Version", starting from `5.0.0`
4. Add the `RelevaSDK` product to your app target
5. Add `https://github.com/firebase/firebase-ios-sdk.git` as a second package
   dependency (Dependency Rule: "Up to Next Major Version", starting from
   `11.15.0` for Firebase 11 or from any `12.x` for Firebase 12 — this package
   accepts either) and add its `FirebaseMessaging` and `FirebaseCore` products
   to your app target — the push-notification setup below calls
   `Messaging.messaging()` from your own code, and the "Choose Package Products"
   sheet for `sdk-swift` only offers this package's own products (`RelevaSDK`,
   `RelevaNotificationExtension`).
6. For rich push notifications, also add the `RelevaNotificationExtension` product
   to your Notification Service Extension target — see
   [Add Notification Service Extension for Rich Notifications](#3-add-notification-service-extension-for-rich-notifications)

This SDK does not set up Firebase itself: you still need a `GoogleService-Info.plist`
in your app target and a `FirebaseApp.configure()` call (typically in
`application(_:didFinishLaunchingWithOptions:)`, before the push setup below)
from the standard Firebase iOS setup.

## Migrating to 5.0.0

Every completion handler in the public API is gone, replaced by `async`. There are
no overloads and nothing is deprecated-but-kept: a 4.x call site that passes a
closure will not compile, which is deliberate — a silently retained completion
variant is how half-migrated call sites survive a release.

### Changed method signatures

| 4.x | 5.0.0 |
|---|---|
| `push(_:completion:)` | `push(_:) async throws -> RelevaResponse` |
| `@available(iOS 15.0, *) push(_:) async throws -> RelevaResponse` | same signature, without the `@available` |
| `trackScreenView(screenToken:productIds:categories:filter:completion:)` | `trackScreenView(screenToken:productIds:categories:filter:) async throws -> RelevaResponse` |
| `@available(iOS 15.0, *) trackScreenView(...) async throws -> RelevaResponse` | same signature, without the `@available` |
| `trackProductView(product:screenToken:completion:)` | `trackProductView(product:screenToken:) async throws -> RelevaResponse` |
| `trackSearchView(query:resultProductIds:screenToken:filter:completion:)` | `trackSearchView(query:resultProductIds:screenToken:filter:) async throws -> RelevaResponse` |
| `trackCheckoutSuccess(orderedCart:screenToken:completion:)` | `trackCheckoutSuccess(orderedCart:screenToken:) async throws -> RelevaResponse` |
| `trackCustomEvent(_:screenToken:completion:)` | `trackCustomEvent(_:screenToken:) async throws -> RelevaResponse` |
| `registerPushToken(_:deviceType:completion:)` | `registerPushToken(_:deviceType:) async throws` |
| `@available(iOS 15.0, *) registerPushToken(_:deviceType:) async throws -> Bool` | `registerPushToken(_:deviceType:) async throws` |
| `submitNpsResponse(token:score:comment:completion:)` | `submitNpsResponse(token:score:comment:) async throws` |
| `NetworkService` — every method taking a `CompletionHandler` | the same method, `async throws`, returning what it used to pass to the handler |
| `EngagementTrackingService.getPendingEventCount(completion:)` | `getPendingEventCount() async -> Int` |
| `EngagementTrackingService.getStatistics(completion:)` | `getStatistics() async -> EngagementStatistics` |
| `NotificationService.requestAuthorization(completion:)` | `requestAuthorization() async -> Bool` |

`NetworkService.NetworkResult<T>` and `NetworkService.CompletionHandler<T>` are
deleted. Where a method used to hand you `.failure(error)` it now throws that same
`RelevaError`; where it handed you `.success(value)` it now returns that value.

### Call sites

A tracking call:

```swift
// 4.x
client.trackScreenView(screenToken: "home") { result in
    switch result {
    case .success(let response):
        render(response.recommenders)
    case .failure(let error):
        print("Error: \(error)")
    }
}
```

```swift
// 5.0.0
Task {
    do {
        let response = try await client.trackScreenView(screenToken: "home")
        render(response.recommenders)
    } catch {
        print("Error: \(error)")
    }
}
```

A fire-and-forget call. The tracking methods are `@discardableResult`, so nothing
has to be bound:

```swift
// 4.x
client.push(request) { _ in }
```

```swift
// 5.0.0
Task { try? await client.push(request) }
```

From a SwiftUI view, prefer an unstructured `Task` for anything that must be
delivered even if the user navigates away quickly — it has no parent to be
cancelled by:

```swift
// 5.0.0
ContentView()
    .onAppear { Task { try? await client.trackScreenView(screenToken: "home") } }
```

`.task { }` is available too and needs no `Task`, but ties the call's lifetime to
the view:

```swift
// 5.0.0
ContentView()
    .task { try? await client.trackScreenView(screenToken: "home") }
```

> **Note:** `.task { }` ties the call's lifetime to the view — SwiftUI cancels it when
> the view disappears, and `URLSession` honours that cancellation. In 4.x the underlying
> `URLSessionDataTask` was not tied to the view and delivered regardless. A cancellation
> surfaces the same way any other transport failure does: as `RelevaError.networkError`
> carrying the underlying error's description, not as a distinct case — check
> `Task.isCancelled` at the call site if you need to tell "cancelled" apart from "the
> network failed" rather than switching on the thrown error. For an event that must be
> delivered even if the user navigates away quickly, use the unstructured `Task { }`
> form above instead.

Push-token registration. `registerPushToken` used to report a `Bool`; that flag was
`true` on every path that reached the handler, so `throws` already carries
everything it carried:

```swift
// 4.x
client.registerPushToken(fcmToken, deviceType: .ios) { result in
    if case .failure(let error) = result { print(error) }
}
```

```swift
// 5.0.0
Task {
    do {
        try await client.registerPushToken(fcmToken, deviceType: .ios)
    } catch {
        print(error)
    }
}
```

NPS submission, from the `onSubmit` closure of `.npsDisplay` or `NpsPresenter`.
That closure is synchronous on both paths, so the call goes in a `Task`:

```swift
// 4.x
.npsDisplay(onSubmit: { token, score, comment in
    client.submitNpsResponse(token: token, score: score, comment: comment)
})
```

```swift
// 5.0.0
.npsDisplay(onSubmit: { token, score, comment in
    Task { try? await client.submitNpsResponse(token: token, score: score, comment: comment) }
})
```

Engagement statistics now come back as a struct rather than a `[String: Any]`, so
the keys are checked by the compiler instead of by you:

```swift
// 4.x
service.getStatistics { stats in
    let pending = stats["pendingCount"] as? Int ?? 0
}
```

```swift
// 5.0.0
let stats = await service.getStatistics()
let pending = stats.pendingCount
```

`EngagementStatistics` is a `Sendable`, `Equatable` struct with `pendingCount`,
`isTracking`, `isSending`, `batchSize`, `batchInterval` and
`eventTypes: [String: Int]` — the same six values the dictionary carried, under the
same names.

### What did *not* change

Anything that only touches local state stays synchronous, because making it `async`
would add a suspension point without adding anything to await:

`setDeviceId`, `getDeviceId`, `setProfileId`, `getProfileId`, `setEndpointOverride`,
`setAppVersion`, `getCart`, `getWishlist`, `clearCartStorage`,
`clearWishlistStorage`, `trackEvent`, `enablePushEngagementTracking`,
`trackEngagement`, `isRelevaMessage`, `startTracking`, `stopTracking` and
`clearPendingEvents`. (`trackEngagement` only appends to the engagement service's
pending queue; the batch that queue sends later is what reaches the network.)

`setCart`, `setWishlist`, `bannerImpression`, `bannerAction`, `storyImpression`,
`storyAction`, `refreshPushToken`, `flush`, `initializeInbox` and every method on
`InboxService` keep their synchronous signatures too, even though they do reach the
network: they are called from SwiftUI view bodies, UIKit action handlers and
lifecycle hooks that cannot await, so each starts its own `Task` internally. Failures
are reported through debug logging, as before.

The wire format is unchanged. A 5.0.0 client and a 4.x client send byte-identical
request bodies.

### Behaviour change in `InboxService`

`refresh`, `loadMore`, `markAsRead`, `markAllAsRead`, `deleteMessage` and
`trackAction` keep their signatures, but their optimistic state update now always
lands on the next main-actor turn. In 4.x, a call made *from* the main thread
mutated `state` before returning. SwiftUI observers see the same values either way;
code that read `inbox.state` on the line after the call did not.

## Migrating to 4.0.0

The open-ended JSON the API returns — Unlayer banner, story and inbox designs,
recommender `meta`, product `custom` and `data` — used to be typed `[String: Any]`.
`Any` is not `Sendable`, so no model holding one could cross a concurrency
boundary, and it is not `Codable` either, which is why those fields were silently
dropped by the standard decoders. They are now typed `JSONValue`, and the models
that hold them are `Sendable`.

The request side moved for the same reason: `PushRequest` was a class holding a
`[String: Any]` payload, and its three tracking subclasses kept it non-final. All
four are now `Sendable` structs. The payload on the wire is unchanged.

### Request builders are value types

`PushRequest`, `ScreenViewRequest`, `SearchRequest` and `CheckoutSuccessRequest`
are structs. The three tracking requests no longer inherit from `PushRequest`;
they conform to the new `PushRequestConvertible` protocol, which `client.push(...)`
takes as `any PushRequestConvertible`, so every existing `push` call site compiles
unchanged.

Chained builder calls are unchanged. Each one returns a copy where it used to
return the same instance, which reads identically in a chain:

```swift
// unchanged in 4.0.0
let request = PushRequest().screenView("home").locale("en_US")
```

A builder called as a bare statement no longer compiles. The returned copy is the
only thing carrying the edit, so the builders are deliberately not
`@discardableResult`: a discarded one is a compiler diagnostic rather than a
silently missing attribute.

```swift
// 3.x — mutated the request in place
let request = PushRequest()
request.screenView("home")
```

```swift
// 4.0.0 — keep the returned copy
let request = PushRequest().screenView("home")
```

`ScreenViewRequest`, `SearchRequest` and `CheckoutSuccessRequest` used to inherit
every `public` member of `PushRequest` — `cart`, `toDict()` and all thirteen
fluent builders. `PushRequestConvertible` exposes only `pushRequest` and
`validate()`, so reach the rest through `.pushRequest`. Since `pushRequest` is
computed, chain onto one value and push *that* value:

```swift
// 3.x — cart, toDict() and every builder were inherited
let request = ScreenViewRequest(screenToken: "cart")
request.cart = snapshot
let payload = request.toDict()
client.push(request) { _ in }
```

```swift
// 4.0.0 — 5.0.0 changed `push` again; see "Migrating to 5.0.0" above
let request = ScreenViewRequest(screenToken: "cart").pushRequest.setCart(snapshot)
let payload = request.toDict()
try await client.push(request)
```

Deleting a `request.cart = …` line rather than carrying it over is not a no-op:
the cart was transmitted in 3.x, so move it onto the `PushRequest` with `setCart`
as above.

If you subclassed `PushRequest`, conform to `PushRequestConvertible` instead:
supply a `pushRequest` that builds the request you want, and implement
`validate()` only if you have rules of your own beyond the cart checks. And
because `RelevaClient` is a non-final `public class`, a subclass overriding
`push(_:)` has to update the parameter type to `any PushRequestConvertible`.

Everything the requests hold is `Sendable` too — `Cart`, `CartProduct`,
`ViewedProduct`, `CustomEvent`, `CustomEventProduct`, `CustomFields`,
`CustomField` (where its values are), and the `AbstractFilter` protocol along with
`SimpleFilter` and `NestedFilter`. A filter type of your own conforming to
`AbstractFilter` therefore has to be `Sendable`: a struct of `Sendable` stored
properties needs nothing beyond the conformance you already declare, but a
**class** conformer, or a struct holding a non-`Sendable` stored property, will
now be diagnosed — make it a struct of `Sendable` values, or declare
`@unchecked Sendable` and take on the synchronization yourself.

### Changed property types

| Type | Property | 3.x | 4.0.0 |
|---|---|---|---|
| `InboxMessage` | `design` | `[String: Any]` | `[String: JSONValue]` |
| `BannerResponse` | `cssStyles` | `[String: Any]` | `[String: JSONValue]` |
| `BannerResponse` | `design` | `[String: Any]?` | `[String: JSONValue]?` |
| `BannerResponse` | `meta` | `[String: Any]?` | `[String: JSONValue]?` |
| `StorySlideResponse` | `design` | `[String: Any]?` | `[String: JSONValue]?` |
| `ProductRecommendation` | `custom` | `[String: Any]?` | `[String: JSONValue]?` |
| `ProductRecommendation` | `data` | `[String: Any]?` | `[String: JSONValue]?` |
| `RecommenderResponse` | `meta` | `[String: Any]?` | `[String: JSONValue]?` |

The memberwise `init` of each of those types takes the new type in the same
position; no parameter was added, removed or reordered.

### Changed method signatures

| Symbol | 3.x | 4.0.0 |
|---|---|---|
| `DesignRenderer.render(design:maxWidth:transparentBody:onLinkTap:)` | `design: [String: Any]` | `design: [String: JSONValue]` |
| `DesignRenderer.getDesignBodyValues(_:)` | `-> [String: Any]` | `-> [String: JSONValue]` |

Those two are the rendering entry points, so any code that renders an inbox or
banner design outside the SDK's own views calls them directly. Pass
`[String: JSONValue](any: someFoundationDictionary)` if you are holding a design
you decoded yourself with `JSONSerialization`.

`DesignRenderer`'s parsing helpers take `JSONValue?` instead of `Any?` for the
same reason. `DesignRenderer.parseColor` is the one that changed shape: it is now
`parseColor(_ value: JSONValue?)`, with `parseColor(css: String?)` for a colour
you already hold as a `String`.

### Reading a `JSONValue`

Replace conditional casts with the accessor of the matching name. Each returns
`nil` for any other case, so a lookup that used to be several `as?` casts is one
optional chain:

```swift
// 3.x
let body = message.design["body"] as? [String: Any]
let values = body?["values"] as? [String: Any]
let color = values?["backgroundColor"] as? String

// 4.0.0
let color = message.design["body"]?["values"]?["backgroundColor"]?.stringValue
```

`JSONValue` offers `stringValue`, `boolValue`, `intValue`, `doubleValue`,
`arrayValue`, `objectValue` and `isNull`, plus `subscript(String)` for object keys
and `subscript(Int)` for array elements. `intValue` and `doubleValue` convert
between the two number cases the way `NSNumber` did, so a JSON `7` reads as either
`7` or `7.0`; a JSON integer that is only ever read and re-encoded stays an
integer rather than becoming `7.0`. The guarantee is "a JSON integer stays an
integer", not full byte-for-byte number round-tripping: a whole-number `Double`
in the source (`1.0`) also decodes as `.int(1)` and re-encodes as `1`, the same
as a literal `1` would.

### Writing a `JSONValue`

Literals work directly, so test fixtures and hand-built designs need no
annotation:

```swift
let design: [String: JSONValue] = [
    "body": ["values": ["backgroundColor": "#ffffff"], "rows": []]
]
```

If you are holding a `[String: Any]` from `JSONSerialization`, wrap it with
`[String: JSONValue](any:)`, and unwrap with `.anyValue` to go back. The
`from(dict:)` factories still take `[String: Any]` and `toDict()` still returns
it, so code that goes through those is unaffected.

### Decoding

`RelevaResponse.init(from:)` used to decode only the `Codable`-compatible fields:
a plain `JSONDecoder().decode(RelevaResponse.self, from:)` returned a response
with no stories and no NPS, and printed a warning telling you to call
`RelevaResponse.from(jsonData:)` instead. There is now one decoding path.
`from(jsonData:)` still exists and is unchanged for callers; it is now a thin
wrapper over `JSONDecoder`.

For the same reason, `RecommenderResponse.meta` and `ProductRecommendation`'s
`custom` and `data` now actually carry the values from the payload. In 3.x they
decoded to `nil` unconditionally and were skipped on encode. If you worked around
that by re-parsing the raw response yourself, you can drop the workaround.

Decoding is now complete, but encoding is intentionally still partial:
`RelevaResponse.encode(to:)` only writes `recommenders` and `push` — `banners`,
`stories` and `nps` are read-only API payloads this SDK never re-encodes
internally, so a `decode → encode → decode` round trip on this type silently
drops those three fields. Nothing in the SDK does this today; if you need to
cache a full response yourself, cache the original response `Data` rather than
a re-encoded `RelevaResponse`.

## Quick Start

### 1. Initialize the SDK

```swift
import RelevaSDK

// In your AppDelegate or App initialization
let config = RelevaConfig.full() // or .pushOnly(), .trackingOnly()
let client = RelevaClient(
    realm: "",
    // You can get the access token from Releva's admin panel -> Settings
    accessToken: "your-access-token",
    config: config
)

// Set user identification
client.setDeviceId(UIDevice.current.identifierForVendor?.uuidString ?? "")
// This should be the id for the user that you use internally to identify this user
client.setProfileId("user-123")
```

## Profile Management and User Logout

### Important: Handling User Logout

When a user logs out of your application, it's **critical** to prevent merging the logged-in user's profile with the anonymous profile created for the logged-out state. To do this, use the `skipMergeWithPreviousProfileId` parameter when setting the new anonymous profile ID:

```swift
// When user logs out, generate a new anonymous profile ID
let newAnonymousProfileId = UUID().uuidString

// Set the new profile ID with skipMergeWithPreviousProfileId set to true
// The second parameter can be passed as true or false without a label
client.setProfileId(newAnonymousProfileId, true)

// Re-register push token with the new anonymous profile
// This is necessary because we skipped the merge, so the token needs to be explicitly registered
// (Messaging.messaging() needs `import FirebaseMessaging` in the enclosing file.)
Task {
    do {
        let fcmToken = try await Messaging.messaging().token()
        try await client.registerPushToken(fcmToken, deviceType: .ios)
    } catch {
        print("Failed to re-register push token: \(error)")
    }
}
```

**Why is this important?**

By default, when you change a profile ID, the SDK will merge the previous profile with the new one to maintain user behavior continuity. However, when a user logs out, you want to start fresh with a completely separate anonymous profile. Passing `true` as the second parameter ensures:

- The logged-in user's profile data remains separate
- The new anonymous profile starts with a clean slate
- No cross-contamination of user behavior data

**Default Behavior (when logging in or switching users):**
```swift
// Normal profile change - previous profile will be merged
client.setProfileId(loggedInUserId)
```

This default behavior is ideal for:
- User login (merging anonymous behavior with logged-in profile)
- Account linking
- Profile migrations

### 2. Configure Push Notifications

#### Enable Push Capabilities

1. In Xcode, select your project
2. Select your app target
3. Go to "Signing & Capabilities"
4. Click "+" and add "Push Notifications"
5. Click "+" and add "Background Modes"
6. Check "Remote notifications"

#### Register for Push Notifications

```swift
import UserNotifications
// Required for the Messaging.messaging() calls below (see the FirebaseMessaging
// dependency in the installation steps above).
import FirebaseMessaging

// Request permission
UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
    if granted {
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }
}

// In AppDelegate
func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    // Set the APNs token for Firebase Messaging.
    //
    // This is only required if your Firebase app is NOT configured with an APNs Authentication Key.
    //
    // If you have not set up the APNs Authentication Key, you can:
    // 1. Generate an APNs key in the Apple Developer Portal
    // 2. Upload it in the Firebase Console: Project Settings → Cloud Messaging
    //
    // Once the APNs Authentication Key is configured, this line is no longer needed.
    // Only use this line if you have not configured that in Firebase Console
    // Messaging.messaging().apnsToken = deviceToken

    // Wire a token provider so the SDK can fetch the current FCM token on every app
    // launch / foreground. FCM rotates tokens silently — without this, the backend's
    // record drifts stale and test pushes start failing with "device token expired".
    client.pushTokenProvider = { completion in
        Messaging.messaging().token { token, _ in
            completion(token)
        }
    }

    // Initial registration (the lifecycle observer will also fire shortly after).
    Task {
        do {
            let fcmToken = try await Messaging.messaging().token()
            try await client.registerPushToken(fcmToken, deviceType: .ios)
            client.enablePushEngagementTracking()
        } catch {
            print("Failed to register push token: \(error)")
        }
    }
}

// Also re-register whenever FCM rotates the token at runtime.
// IMPORTANT: assign the delegate during app launch — typically in
// `application(_:didFinishLaunchingWithOptions:)` — otherwise this
// extension will never be invoked:
//
//     Messaging.messaging().delegate = self
//
extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken = fcmToken else { return }
        Task { try? await client.registerPushToken(fcmToken, deviceType: .ios) }
    }
}

// Handle notification taps
func userNotificationCenter(_ center: UNUserNotificationCenter,
                          didReceive response: UNNotificationResponse,
                          withCompletionHandler completionHandler: @escaping () -> Void) {
    let userInfo = response.notification.request.content.userInfo

    if client.isRelevaMessage(userInfo: userInfo) {
        client.trackEngagement(userInfo: userInfo, type: .opened)
    }

    completionHandler()
}
```

### 3. Add Notification Service Extension for Rich Notifications

**For rich push notifications with images and custom buttons**, add a Notification Service Extension:

#### Step 1: Create the Extension Target

1. In Xcode, select your project in the navigator
2. File → New → Target...
3. Select "Notification Service Extension"
4. Name it (e.g., "NotificationExtension")
5. Click "Finish" (Activate if prompted)

#### Step 2: Add the SDK to the Extension Target

The extension needs the `RelevaNotificationExtension` product (the app target only
needs `RelevaSDK`):

1. In Xcode, select your project → the extension target → General
2. Under "Frameworks and Libraries", click "+"
3. Pick `RelevaNotificationExtension` from the `sdk-swift` package

If you have not added the package yet, do File → Add Package Dependencies… first
(see [Installation](#installation)) — the "Add to Target" column of that dialog
also lets you assign `RelevaNotificationExtension` to the extension target
directly.

#### Step 3: Inherit from SDK's Base Class

In your extension's `NotificationService.swift`, replace the entire file with:

```swift
import UserNotifications
import RelevaNotificationExtension

class NotificationService: RelevaNotificationServiceExtension {
    // That's it! No additional code needed.
    // The SDK handles all rich notification processing automatically.
}
```

**Done!** Your app now supports:
- Push notifications with images
- Custom action buttons
- Automatic click tracking
- Deep link handling (both internal and external URLs)
- Screen navigation within your app

> **Note**: The SDK uses runtime reflection to safely handle UIApplication APIs. This means it works out-of-the-box in both your main app and the extension without any build configuration.

### Handling Navigation from Push Notifications

When a user taps a notification, the SDK posts `NotificationCenter` notifications that your app observes to perform navigation. Set up observers in your main view or app state:

```swift
// Listen for screen navigation
NotificationCenter.default.addObserver(
    forName: Notification.Name("RelevaNavigateToScreen"),
    object: nil,
    queue: .main
) { notification in
    guard let screen = notification.userInfo?["screen"] as? String else { return }
    let parameters = notification.userInfo?["parsedParameters"] as? [String: Any]

    // Map screen name to your app's navigation
    // screen is a free-form value configured in the Releva dashboard
    switch screen {
    case "cart":
        // Navigate to cart
    case "product_details":
        let productId = parameters?["productId"] as? String
        // Navigate to product details
    default:
        // Navigate to home or handle unknown screens
    }
}

// Listen for URL navigation (deep links with custom scheme)
NotificationCenter.default.addObserver(
    forName: Notification.Name("RelevaNavigateToURL"),
    object: nil,
    queue: .main
) { notification in
    guard let url = notification.userInfo?["url"] as? URL else { return }
    // Handle deep link (e.g. myapp://product/123)
}

// Listen for inbox navigation
NotificationCenter.default.addObserver(
    forName: Notification.Name("RelevaNavigateToInbox"),
    object: nil,
    queue: .main
) { notification in
    let parameters = notification.userInfo?["parsedParameters"] as? [String: Any]
    let inboxMessageId = parameters?["inboxMessageId"]
    // Navigate to inbox, optionally scrolling to the specific message
}
```

> **Note:** External URLs (`https://...`) are opened directly in Safari by the SDK. Only internal deep links (custom schemes) post a `RelevaNavigateToURL` notification.

### Navigation Types Supported

The SDK supports three types of navigation from push notifications:

**1. Screen Navigation** (`target: "screen"`):
```json
{
  "target": "screen",
  "navigate_to_screen": "cart",
  "navigate_to_parameters": "{\"inboxMessageId\": 123}"
}
```
Posts a `RelevaNavigateToScreen` notification that your app can observe. Parameters are parsed from JSON and included as `parsedParameters` in the notification userInfo.

**2. URL Navigation** (`target: "url"`):
```json
{
  "target": "url",
  "navigate_to_url": "https://example.com"
}
```
- **Internal deep links** (e.g., `myapp://...`): Posts `RelevaNavigateToURL` notification for your app to handle
- **External URLs** (e.g., `https://...`): Opens in Safari or appropriate app

**3. Inbox Navigation** (`target: "inbox"`):
```json
{
  "target": "inbox",
  "navigate_to_parameters": "{\"inboxMessageId\": 456}"
}
```
Posts a `RelevaNavigateToInbox` notification. Your app navigates to the inbox screen, optionally opening a specific message.

## Core Features

### User Tracking

Most tracking — screen views, product views, search, checkout, recommendations — is sent through a single API: build a `PushRequest` using the fluent builder, then hand it to `client.push(...)`. The builder methods can be chained in any order.

`PushRequest` is a `Sendable` value type and each builder returns a new copy rather than mutating the receiver, so a request can be shared across tasks and a partly built one can be reused as the base for several pushes. Since the returned copy is the only thing that carries the change, the builders are deliberately not `@discardableResult` — calling one as a bare statement is a dropped edit, and the compiler flags it.

```swift
let base = PushRequest().locale("en_US").currency("USD")

let home = base.screenView("home")          // base is unchanged
let search = base.screenView("search_results").search("iPhone")
```

```swift
// Track a screen view (home page, listing page, etc.)
let request = PushRequest()
    // Token should be changed with the one you have for the page inside Releva's admin panel (UUID)
    .screenView("home")
    .pageProductIds(["product-1", "product-2"])
    .pageCategories(["electronics", "phones"])
    .locale("en_US")
    .currency("USD")

// `push` is `async throws`, so this needs an async context — a `Task { }`, a
// SwiftUI `.task { }`, or an enclosing `async` function.
do {
    let response = try await client.push(request)
    // Process recommendations returned for this page
    for recommender in response.recommenders {
        print("Recommender: \(recommender.name)")
        for product in recommender.response {
            print("- \(product.name): $\(product.price)")
        }
    }
} catch {
    print("Error: \(error)")
}

// Track a product view
let product = ViewedProduct(id: "product-123")
    .withStringField(key: "brand", values: ["Apple"])
    .withNumericField(key: "speakersCount", values: [2])
    .withDateField(key: "releaseDate", values: [Date()])

let productRequest = PushRequest()
    // Token should be changed with the one you have for product page inside Releva's admin panel (UUID)
    .screenView("product_detail")
    .productView(product)

// `push` is `@discardableResult`, so a fire-and-forget call needs no `_ =`.
try await client.push(productRequest)

// Track a search
let searchRequest = PushRequest()
    // Token should be changed with the one you have for search page inside Releva's admin panel (UUID)
    .screenView("search_results")
    .search("iPhone")
    .pageProductIds(["product-1", "product-2", "product-3"])

try await client.push(searchRequest)
```

The `push()` response includes recommenders, banners, stories, and NPS configuration — the SDK handles banner/story/NPS state internally, so a screen-view push is also what populates them.

### Cart Management

`client.setCart(...)` is stateful: it stores the cart locally and automatically syncs changes to the backend. Checkout success is a tracking event and goes through the builder.

```swift
// Create cart products
let product1 = CartProduct(id: "sku-123", price: 29.99, quantity: 2)
let product2 = CartProduct(id: "sku-456", price: 49.99, quantity: 1)

// Set the active cart (auto-syncs on change)
let cart = Cart.active([product1, product2])
client.setCart(cart)

// Track checkout success. The SDK identifies the user solely by the profileId set
// via setProfileId(); contact details and other profile attributes are never sent.
let orderedCart = Cart.paid([product1, product2], orderId: "order-789")
try await client.trackCheckoutSuccess(orderedCart: orderedCart, screenToken: "checkout_success")
```

### Wishlist Management

The wishlist is stateful, like the cart — set it on the client and the SDK syncs changes automatically.

```swift
let wishlistProducts = [
    WishlistProduct(id: "product-1"),
    WishlistProduct(id: "product-2")
]

client.setWishlist(wishlistProducts)
```

### Custom Events

Custom events are the one exception to the builder pattern — call `client.trackCustomEvent(...)` directly.

`CustomFields` is built fluently: start from an empty `CustomFields()` and chain the typed field builders. Each method takes a `key` and an array of values, and returns a new `CustomFields`. Three field types are supported:

```swift
let customFields = CustomFields()
    .withStringField(key: "color", values: ["red"])           // [String]
    .withNumericField(key: "discountPercent", values: [15])   // [Double]
    .withDateField(key: "promoEndsAt", values: [Date()])      // [Date] — serialized as ISO-8601 (e.g. "2026-06-11T12:00:00Z")

let event = CustomEvent(action: "selectedColor")
    .withProduct(id: "product-123", quantity: 1)
    .withTag("promo")
    .withCustomFields(customFields)

try await client.trackCustomEvent(event)
```

> Date fields take native `Date` values. The SDK converts them to ISO-8601 strings on serialization via `ISO8601DateFormatter`, so you never format the date yourself. The same `.withStringField` / `.withNumericField` / `.withDateField` builders also exist directly on `ViewedProduct` (see [User Tracking](#user-tracking)).

### Advanced Filtering

Filters compose with the rest of the request via `pageFilter(...)` on the builder.

```swift
// Simple filter
let priceFilter = SimpleFilter.priceRange(
    minPrice: 100,
    maxPrice: 500,
    action: .include
)

// Nested filter (price AND brand)
let complexFilter = NestedFilter.and(
    SimpleFilter.priceRange(minPrice: 100, maxPrice: 500),
    SimpleFilter.brand("Apple")
)

// Apply filter to a screen view
let request = PushRequest()
    // Token should be changed with the one you have for category page inside Releva's admin panel (UUID)
    .screenView("category_listing")
    .pageFilter(complexFilter)

try await client.push(request)
```

## Banners

Banners are dynamic content overlays (popup modals, bars, flyouts, or static inline content) that can be displayed based on user behavior and configured triggers. The SDK automatically handles banner display, positioning, and tracking.

### Using the Banner Display Modifier

Add the `.bannerDisplay()` modifier to the view where banners should appear:

```swift
HomeView()
    .bannerDisplay(client: relevaClient, targetSelector: "#home-content") { url in
        // Handle link taps from banner content
        handleDeepLink(url)
    }
```

### Banner Lifecycle

**Banners reset on each `trackScreenView()` call.** When you navigate back to a screen and call `trackScreenView()`, banners are re-evaluated and will show again based on their trigger conditions. This matches the web SDK behavior.

### Banner Triggers

Banners are configured with triggers in the Releva dashboard:

- **immediately** — Shows as soon as the screen loads
- **delaySeconds** — Shows after a specified delay
- **scrollPercentage** — Shows when user scrolls to a certain percentage (requires scroll percentage provider)
- **cartChanged** — Shows when cart is modified
- **wishlistChanged** — Shows when wishlist is modified
- **leaveIntent** — Not supported on mobile (web-only feature)

### Banner Types

| Type | Description |
|------|-------------|
| **Popup** | Centered modal dialog with overlay backdrop and close button. Supports full-screen mode. |
| **Bar** | Fixed position bar at top or bottom with close button and shadow. |
| **Flyout** | Side panel sliding in from left or right with scrollable content. |
| **Static** | Inline content injected before or after the wrapped view (afterbegin, beforeend, afterend, replace). |

All banner styling, positioning, and content are configured in the Releva dashboard using the Unlayer editor.

### Automatic Tracking

The SDK automatically tracks:
- **Banner impressions** — when a banner is displayed
- **Banner clicks** — when user taps a link or button within a banner
- **Banner dismissals** — when user closes a banner

## Stories

Stories are full-screen, multi-slide content experiences similar to Instagram or Facebook stories. They support auto-advance timers, progress indicators, tap/swipe navigation, and configurable end behavior. Like banners, stories are configured in the Releva dashboard and delivered as part of the push response.

### Setup

Add the `.storyDisplay()` modifier to the view where stories should appear:

```swift
HomeView()
    .storyDisplay(client: relevaClient) { url in
        // Handle link taps from story slides
        handleDeepLink(url)
    }
```

Stories are triggered automatically when the server returns them in a push response. The SDK evaluates triggers and opens the story viewer when conditions are met.

### How Stories Are Triggered

Stories share the same trigger system as banners. When you call `trackScreenView()` (or any push method), the server response may include stories:

- **immediately** — Story opens as soon as the response is processed
- **delaySeconds** — Story opens after the configured delay
- **scrollPercentage** — Story opens when the user scrolls past the threshold
- **cartChanged** / **wishlistChanged** — Story opens when cart or wishlist is modified

### Story Viewer Behavior

The story viewer is a full-screen overlay that displays slides sequentially:

- **Progress indicators** at the top show the current position and auto-advance timer
- **Tap left half** of the screen to go to the previous slide
- **Tap right half** to go to the next slide
- **Swipe left/right** to navigate between slides
- **Close button** (X) next to the progress bars dismisses the story
- Each slide's **background color** is read from the Unlayer design JSON
- **Action buttons** at the bottom when a slide has a configured action

When multiple stories are triggered simultaneously, they are queued and shown one at a time.

### End Behavior

Each story has a configurable end behavior (set in the Releva dashboard):

- **dismiss** (default) — Story closes automatically after the last slide
- **loop** — Story restarts from the first slide
- **stayOnLast** — Story stays on the last slide until the user closes it

### Link Handling

Story slides can contain interactive elements (buttons, links) created in the Unlayer editor. When a user taps one of these elements, the `onLinkTap` callback is called with the URL:

```swift
.storyDisplay(client: client) { url in
    // Navigate to a screen, open a browser, or handle deep links
    if let parsed = URL(string: url) {
        UIApplication.shared.open(parsed)
    }
}
```

### Automatic Tracking

The SDK automatically tracks all story engagement events:

- **storyImpression** — when the story viewer opens
- **storySlideView** — when each slide is displayed
- **storySlideClick** — when the user taps a link or button within a slide
- **storyComplete** — when the last slide is reached
- **storyClose** — when the user dismisses the story

## NPS Surveys

The SDK supports native NPS (Net Promoter Score) surveys delivered as overlays. The server decides which profiles are eligible; the SDK handles trigger evaluation, rendering, and submission.

### Setup

**1. Add `.npsDisplay()` to your root view**

Wrap your root view so surveys can appear on any screen:

`onSubmit` is synchronous and `submitNpsResponse` is `async throws`, so the call
goes in a `Task`:

```swift
ContentView()
    .npsDisplay(onSubmit: { token, score, comment in
        Task { try? await client.submitNpsResponse(token: token, score: score, comment: comment) }
    })
```

**2. Set the app version (recommended)**

Call this once after initialising the client so the server can filter by app version:

```swift
client.setAppVersion("1.2.3")
```

### How It Works

On every `push()` call the SDK automatically includes device context (platform, SDK version, app version) in the request body. When the server returns an `nps` field in the response, the SDK stores the config and evaluates trigger conditions:

| Trigger type | When it fires |
|---|---|
| `appOpen` | First push call of a new session |
| `sessionCount` | Treated as already satisfied (server pre-checks `minSessions`) |
| `screenView` | Server-side evaluation |
| `customEvent` | When `client.trackEvent(eventName)` matches the configured `eventName` |

After a trigger fires, the SDK waits `triggerDelaySeconds` before presenting the overlay. Once shown (or cancelled), it is suppressed for the rest of the session.

### Firing Custom Events

```swift
// Trigger NPS after checkout
client.trackEvent("checkout_complete")

// Cancel pending NPS if user enters a sensitive flow
client.trackEvent("checkout_started")
```

### Overlay Appearance

The survey appearance is fully server-driven: colors, button style (`pill`/`rounded`/`square`), position (`bottomSheet`/`modal`), labels, and dark-mode variants are all read from the `nps.appearance` config returned by the server. No hardcoded strings or colors are used.

### NPS API Reference

| Method | Description |
|---|---|
| `setAppVersion(_ version: String)` | Set the running app version for NPS context |
| `trackEvent(_ eventName: String)` | Fire a named event (triggers / cancel events) |
| `submitNpsResponse(token:score:comment:)` | Submit a survey response (called by `NpsDisplayModifier`) |

## App Inbox

App Inbox is a persistent, in-app message centre. Unlike push notifications, inbox messages survive until the user reads or deletes them (or they expire). Messages are delivered server-side with content already personalized — the SDK receives ready-to-render data.

### Initialize the Inbox

Call `initializeInbox()` after setting the profile ID:

```swift
client.setProfileId("user-123")
client.initializeInbox()
```

### Access Inbox State

The `InboxService` is an `ObservableObject`. Use Combine or SwiftUI observation for reactive UI updates:

```swift
@ObservedObject var inboxService = InboxService.shared

// Current state
inboxService.state.messages      // [InboxMessage]
inboxService.state.unreadCount   // Int
inboxService.state.isLoading     // Bool
inboxService.state.hasMore       // Bool (more pages available)
inboxService.state.isStale       // Bool (cache older than 5 min)
```

### Refresh and Pagination

```swift
let inbox = client.inbox

// Pull-to-refresh: fetch first page + unread count in parallel
inbox.refresh()

// Infinite scroll: load next page (cursor-based)
inbox.loadMore()

// Refresh only if cache is stale (> 5 minutes)
inbox.refreshIfStale()
```

### Mark as Read and Delete

All mutations use optimistic updates — the UI updates instantly, and reverts on API
error. "Instantly" means on the next main-actor turn: `state` is `@Published` and
main-actor-isolated, so as of 5.0.0 these methods no longer write to it before
returning, even when called from the main thread. SwiftUI observers see the same
values either way; code that reads `inbox.state` on the line after the call does not.

```swift
// Mark a single message as read
inbox.markAsRead(message.id)

// Mark all messages as read
inbox.markAllAsRead()

// Delete a message
inbox.deleteMessage(message.id)
```

### Track Message Actions

Call `trackAction()` when a user taps an interactive element inside a message (e.g. a button or link). This records an analytics event but does not mark the message as read:

```swift
inbox.trackAction(message.id)
```

### Render Message Content

Use `InboxMessageView` to render the message body. It wraps the SDK's `DesignRenderer` and automatically tracks actions on link taps:

```swift
import RelevaSDK

InboxMessageView(message: inboxMessage) { url in
    // Handle URL (e.g. open in browser or deep link)
    if let parsed = URL(string: url) {
        UIApplication.shared.open(parsed)
    }
}
```

### Inbox Sync

When a push notification has an associated inbox message, the backend includes an `inbox_sync` flag in the push payload. The SDK automatically handles this — it refreshes the inbox alongside displaying the notification. No additional setup is required beyond `enablePushEngagementTracking()`.

The inbox also refreshes automatically when the app returns to the foreground (via `UIApplication.willEnterForegroundNotification`), as a reliable fallback for when silent push doesn't arrive.

### InboxMessage Data Model

| Field | Type | Description |
|---|---|---|
| `id` | `String` (UUID) | Unique ID of this delivery. Use in all read/delete/action calls. |
| `title` | `String` | Resolved message title. |
| `design` | `[String: JSONValue]` | Unlayer design JSON, ready to render via `InboxMessageView`. Was `[String: Any]` before 4.0.0 — see [Migrating to 4.0.0](#migrating-to-400). |
| `read` | `Bool` | Whether the user has read this message. |
| `createdAt` | `Date` | When the message was delivered. Messages are sorted newest-first. |
| `inboxMessageId` | `Int` | ID of the source message template. Use for push notification routing. |

## UIKit Integration

Every visual feature works from a plain `UIViewController` — no SwiftUI view hierarchy required. Banners and NPS surveys have presenters that mirror the SwiftUI modifiers; stories and inbox messages are SwiftUI views you host yourself in a `UIHostingController`.

Each snippet below is complete and compiles as written, given the imports shown.

### Banners in UIKit

`BannerPresenter` is the UIKit counterpart of `.bannerDisplay(client:targetSelector:onLinkTap:)`. It hosts the same SwiftUI banner views and reports impressions, clicks and dismissals through the same code, so tracking is identical on both paths.

```swift
import RelevaSDK
import UIKit

final class HomeViewController: UIViewController {
    private var banners: BannerPresenter?

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let client = RelevaClient.shared else { return }

        banners = BannerPresenter(host: self, client: client) { [weak self] url in
            self?.handleDeepLink(url)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        banners?.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        banners?.stop()
    }

    private func handleDeepLink(_ url: String) {
        // Your routing.
    }
}
```

`start()` and `stop()` are the UIKit equivalents of SwiftUI's `onAppear` and `onDisappear`. Call them from the appearance callbacks as above — otherwise the presenter keeps putting banners over a screen the user has already left.

Popup, flyout and bar banners are displayed. **Static and replace banners are not**: they belong inline in your own content, which a presenter has no way to place them in, so they are ignored — including for impression tracking, so your reports are not inflated by banners nobody saw. Use the SwiftUI modifier if you need those types.

How they are presented:

- Popups and flyouts share one `.overFullScreen` modal, presented from the frontmost view controller. A banner arriving while your app already has a sheet up appears over it instead of failing to present, and two banners arriving together stack inside that one modal exactly as they do in SwiftUI.
- Bar banners are child view controllers pinned to the top or bottom safe area, so the rest of the screen stays usable while a bar is up.

### NPS Surveys in UIKit

`NpsPresenter` is the UIKit counterpart of `.npsDisplay(onSubmit:onSkip:)`, and shows the same survey in a sheet. Submitting the response is the app's job on both paths:

```swift
import RelevaSDK
import UIKit

final class SettingsViewController: UIViewController {
    private var nps: NpsPresenter?

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let client = RelevaClient.shared else { return }

        nps = NpsPresenter(host: self, onSubmit: { token, score, comment in
            Task { try? await client.submitNpsResponse(token: token, score: score, comment: comment) }
        })
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        nps?.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        nps?.stop()
    }
}
```

The survey dismisses itself when the user skips it, and two seconds after the thank-you screen appears. If the user swipes the sheet away, the next survey that fires is presented normally.

### Stories in UIKit

There is no story presenter: a story is a full-screen takeover, so hosting `StoryViewerView` yourself is both shorter and gives you control over how it is presented.

`StoryViewerView` tracks slide views, slide clicks, completion and close on its own. The one event it does not track is the story impression — the SwiftUI `.storyDisplay(client:onLinkTap:)` modifier does that before opening the viewer, so a UIKit host has to call `storyImpression(_:)` itself:

```swift
import Combine
import RelevaSDK
import SwiftUI
import UIKit

final class FeedViewController: UIViewController {
    private var subscriptions = Set<AnyCancellable>()

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        StoryDisplayController.shared.storyPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] story in
                self?.presentStory(story)
            }
            .store(in: &subscriptions)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Drops every subscription in the set. Without this, a popped controller keeps
        // receiving stories, and re-subscribes on its way back in.
        subscriptions.removeAll()
    }

    private func presentStory(_ story: StoryResponse) {
        guard let client = RelevaClient.shared else { return }

        client.storyImpression(story)

        let viewer = UIHostingController(rootView: StoryViewerView(
            story: story,
            client: client,
            onLinkTap: { [weak self] url in
                self?.handleDeepLink(url)
            },
            onClose: { [weak self] in
                self?.dismiss(animated: true)
            }
        ))
        viewer.modalPresentationStyle = .fullScreen
        present(viewer, animated: true)
    }

    private func handleDeepLink(_ url: String) {
        // Your routing.
    }
}
```

`onClose` fires when the user taps the close button, and when the story ends with the dashboard's end behaviour set to `dismiss`. The viewer never takes itself off screen — dismissing is up to you.

`NpsDisplayController.shared.npsPublisher` and `BannerDisplayController.shared.bannerPublisher` follow the same shape if you want to bypass the presenters and drive the display yourself. Note that the presenters already subscribe on your behalf, so you would then be responsible for reporting impressions, clicks and dismissals through `RelevaClient`.

### Inbox Messages in UIKit

`InboxMessageView` renders a message body and tracks link taps for you. Wrap it in a `ScrollView` — the design has its own height and can be taller than the screen.

Pushed onto a navigation stack:

```swift
import RelevaSDK
import SwiftUI
import UIKit

extension UIViewController {
    func pushInboxMessage(_ message: InboxMessage) {
        let detail = UIHostingController(rootView: ScrollView {
            InboxMessageView(message: message) { url in
                guard let parsed = URL(string: url) else { return }
                UIApplication.shared.open(parsed)
            }
        })
        detail.title = message.title
        navigationController?.pushViewController(detail, animated: true)
    }
}
```

Presented modally, wrapped in its own navigation controller so it gets a title bar:

```swift
import RelevaSDK
import SwiftUI
import UIKit

extension UIViewController {
    func presentInboxMessage(_ message: InboxMessage) {
        let detail = UIHostingController(rootView: ScrollView {
            InboxMessageView(message: message) { url in
                guard let parsed = URL(string: url) else { return }
                UIApplication.shared.open(parsed)
            }
        })
        detail.title = message.title

        present(UINavigationController(rootViewController: detail), animated: true)
    }
}
```

Marking the message read is separate from rendering it, on both paths — call `RelevaClient.shared?.inbox.markAsRead(message.id)` when you consider it read.

## Expected Push Notification Payload

Releva sends push notifications with the following payload structure. On iOS, Firebase places custom data at the root level alongside `aps`:

```json
{
  "click_action": "RELEVA_NOTIFICATION_CLICK",
  "title": "Special Offer!",
  "body": "Get 20% off your next purchase",
  "imageUrl": "https://example.com/image.jpg",
  "button": "Shop Now",
  "target": "screen",
  "navigate_to_screen": "/product/123",
  "navigate_to_parameters": "{\"inboxMessageId\": 456}",
  "inbox_sync": "true",
  "callbackUrl": "https://api.releva.ai/track/..."
}
```

The SDK automatically:
- Displays rich notifications with images and action buttons
- Navigates to the specified screen or URL when tapped
- Tracks engagement metrics (delivered, opened, clicked)
- Triggers inbox refresh when `inbox_sync` is present

## Endpoint Override

For local development (e.g., using ngrok), you can override the API endpoint at runtime:

```swift
// Point all API requests to a local/ngrok endpoint
client.setEndpointOverride("https://abc123.ngrok-free.app")

// Clear the override (revert to realm-based URL)
client.setEndpointOverride(nil)
```

The override takes precedence over both the realm-based URL and the `customEndpoint` in `RelevaConfig`.

## Configuration Options

### Preset Configurations

```swift
// All features enabled (default)
let config = RelevaConfig.full()

// Only tracking, no push notifications
let config = RelevaConfig.trackingOnly()

// Only push notifications, no tracking
let config = RelevaConfig.pushOnly()

// Custom configuration
let config = RelevaConfig(
    enableTracking: true,
    enableScreenTracking: true,
    enablePushNotifications: true,
    enableAnalytics: true,
    enableDebugLogging: true,
    requestTimeoutInterval: 30.0,
    maxRetryAttempts: 3,
    engagementBatchSize: 10,
    engagementBatchInterval: 30.0
)
```

## API Reference

### RelevaClient

`RelevaClient` is `@MainActor`-isolated. A method is `async throws` when the caller
needs the result or the failure back; a `sync` row below is fire-and-forget instead
— several of them (`setCart`, `setWishlist`, `refreshPushToken`, the banner/story
trackers) still reach the network, from a `Task` started internally rather than one
the caller awaits. See "What did *not* change" above for why. Nothing takes a
completion handler.

| Method | Kind | Description |
|---|---|---|
| `init(realm:accessToken:config:)` | sync | Initialize the SDK |
| `setDeviceId(_:)` | sync | Set unique device identifier |
| `getDeviceId()` | sync | Read the device identifier |
| `setProfileId(_:_:)` | sync | Set user profile ID (second param: skipMerge) |
| `getProfileId()` | sync | Read the profile ID |
| `setEndpointOverride(_:)` | sync | Override API endpoint at runtime |
| `setAppVersion(_:)` | sync | Set app version for NPS context |
| `setCart(_:)` | sync | Set shopping cart (syncs in the background) |
| `getCart()` | sync | Read the stored cart |
| `setWishlist(_:)` | sync | Set wishlist (syncs in the background) |
| `getWishlist()` | sync | Read the stored wishlist |
| `clearCartStorage()` | sync | Clear cart without API call |
| `clearWishlistStorage()` | sync | Clear wishlist without API call |
| `push(_:)` | `async throws -> RelevaResponse` | Send a push request |
| `trackScreenView(screenToken:productIds:categories:filter:)` | `async throws -> RelevaResponse` | Track screen view |
| `trackProductView(product:screenToken:)` | `async throws -> RelevaResponse` | Track product view |
| `trackSearchView(query:resultProductIds:screenToken:filter:)` | `async throws -> RelevaResponse` | Track search |
| `trackCheckoutSuccess(orderedCart:screenToken:)` | `async throws -> RelevaResponse` | Track checkout |
| `trackCustomEvent(_:screenToken:)` | `async throws -> RelevaResponse` | Track custom event |
| `registerPushToken(_:deviceType:)` | `async throws` | Register FCM token |
| `refreshPushToken()` | sync | Re-fetch via `pushTokenProvider` and re-upload if stale |
| `pushTokenProvider` | property | Closure the SDK calls on launch/foreground to get the current token |
| `enablePushEngagementTracking()` | sync | Enable push engagement tracking |
| `trackEngagement(userInfo:type:)` | sync | Track push engagement |
| `isRelevaMessage(userInfo:)` | sync | Check if notification is from Releva |
| `bannerImpression(_:)` | sync | Track banner impression |
| `bannerAction(_:action:)` | sync | Track banner action |
| `storyImpression(_:)` | sync | Track story impression |
| `storyAction(_:action:slideId:)` | sync | Track story action |
| `trackEvent(_:)` | sync | Fire NPS custom event trigger |
| `submitNpsResponse(token:score:comment:)` | `async throws` | Submit NPS response |
| `initializeInbox()` | sync | Initialize inbox service |
| `inbox` | property | Access InboxService singleton |

The banner and story impression/action methods stay synchronous because they are
called from SwiftUI view bodies and UIKit action handlers that cannot await; each
starts its own `Task` and reports failures through debug logging only.

## Async/Await

The tracking API is `async throws`, so it needs an async context. Inside a SwiftUI
view that is `.task { }`; anywhere else it is a `Task { }` or an enclosing `async`
function:

```swift
Task {
    do {
        let response = try await client.trackScreenView(screenToken: "home")
        print("\(response.recommenderCount) recommenders")

        try await client.registerPushToken(token, deviceType: .ios)
        try await client.push(request)
    } catch {
        print("Error: \(error)")
    }
}
```

The tracking methods are `@discardableResult`, so a call made purely for its
effect needs no `_ =`.

## Troubleshooting

### Common Issues

**Push notifications not working:**
- Verify push notification capability is enabled in Xcode
- Check that you're calling `registerForRemoteNotifications()`
- Ensure Firebase is properly configured with your APNs certificates
- Check device token is being registered with `client.registerPushToken()`
- Verify notification permissions are granted

**Rich notifications (images/buttons) not showing:**
- Confirm you've created the Notification Service Extension target
- Verify extension inherits from `RelevaNotificationServiceExtension` (NOT `UNNotificationServiceExtension`)
- Check the `RelevaNotificationExtension` product is listed under the extension target's "Frameworks and Libraries"
- Test with app in background (extensions don't run when app is in foreground)
- Verify `imageUrl` is a valid, publicly accessible HTTPS URL
- Check Xcode Console for "RelevaSDK" logs to see processing details

**Tracking not working:**
- Verify `enableTracking` is true in config
- Check network connectivity
- Enable debug logging to see requests
- Confirm realm and access token are correct

**Inbox not loading:**
- Ensure `initializeInbox()` is called after `setProfileId()`
- Check that the profile ID matches a user with inbox messages
- Verify the access token has inbox permissions
- Enable debug logging to see inbox API requests

**NPS survey not appearing:**
- Verify the survey is configured and active in the Releva dashboard
- Check that triggers match (e.g., `trackEvent()` with correct event name)
- The survey is suppressed for the rest of the session after being shown once
- Enable debug logging to see NPS trigger evaluation

**Session expiring too often:**
- Sessions expire after 24 hours by design
- Check device time settings

**Build errors about UIApplication in extensions:**
- Update to SDK version 1.0.0+ which uses runtime reflection
- No build flags or package configuration changes should be needed
- If you're still seeing errors, clean build folder (Cmd+Shift+K) and rebuild

### Debug Logging

Enable debug logging to see all SDK operations:

```swift
let config = RelevaConfig.debug()
// or
let config = RelevaConfig(enableDebugLogging: true)
```

This will show:
- Network requests and responses
- Notification processing
- Banner, story, and NPS trigger evaluation
- Inbox API calls and cache state
- Token registration

## Privacy Manifest

The SDK ships an Apple privacy manifest at `Sources/RelevaSDK/PrivacyInfo.xcprivacy`, declared as a resource on the `RelevaSDK` target so it is copied into the built product. Xcode picks it up automatically when you add the package — there is nothing to copy into your own project.

### What the SDK's manifest declares

**Required-reason API:** `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`. `StorageService` reads and writes its own `rlv_`-prefixed keys in `UserDefaults.standard` (device and profile IDs, session, cart, wishlist, push token, inbox cache, device counters). The SDK uses no other required-reason API.

**Collected data types**, all marked as linked to the user's identity (everything carries `profileId` / `deviceId`) and none marked as used for tracking:

| Type | What it is | Purposes |
| --- | --- | --- |
| User ID | the `profileId` you set via `setProfileId(_:)` | Product personalization, App functionality, Analytics |
| Device ID | the `deviceId` you set via `setDeviceId(_:)`, the FCM push token, and the session ID (a fresh UUID minted on every cold start and stored as `rlv_session_id`, but never read back on the next launch — it does not persist an identifier across launches) | Product personalization, App functionality, Analytics |
| Product Interaction | screen and product views, cart and wishlist contents, custom events, banner/story/NPS impressions and clicks | Product personalization, App functionality, Analytics |
| Search History | the query string you pass to `trackSearchView(query:...)` | Product personalization, App functionality, Analytics |
| Purchase History | order ID, products, quantities, prices and total from `trackCheckoutSuccess(...)` | Product personalization, App functionality, Analytics |
| Other User Content | the optional free-text `comment` on `submitNpsResponse(...)` | App functionality |

`Analytics` is on the five behavioural types because Releva's Customer Insights features (RFM scoring, cohort analysis, funnels, audience performance) are built on exactly those identifiers and events. It is deliberately **not** on Other User Content: the NPS comment is read individually by a marketer rather than aggregated into an audience measure.

Note that Device ID plus the Analytics purpose is precisely the combination App Store Connect's App Privacy questionnaire flags when asking whether data is used to track. It does not contradict `NSPrivacyTracking` being `false` — purpose and tracking are independent keys, and this SDK's tracking determination is documented above — but expect the question to come up when you fill in your own answers.

The SDK does **not** collect email addresses, phone numbers, names or postal addresses. It has not accepted profile attributes since v2.0.0; it identifies users solely by the `profileId` you set.

`NSPrivacyTracking` is `false` and `NSPrivacyTrackingDomains` is empty. Do not add Releva's API host to `NSPrivacyTrackingDomains` in your app's manifest either: the OS **blocks** requests to every domain listed there for users who have not granted App Tracking Transparency permission, which would break push registration, tracking and personalization for those users.

The `RelevaNotificationExtension` target has no manifest of its own. It uses no required-reason API and collects nothing — it renders the notification payload iOS already delivered and downloads the attachment image from the URL in that payload.

### What you still have to do yourself

**The SDK's manifest does not complete your app's privacy obligations.** It covers this SDK's own bundle and nothing else. You are still responsible for:

1. **Your App Store Connect App Privacy details.** These are a separate submission artifact that Apple does not derive from any manifest. Your answers must account for the data this SDK collects on your behalf — the table above is the input to that, not a substitute for it.
2. **Your own app's `PrivacyInfo.xcprivacy`.** Declare every required-reason API category your own code and your other dependencies use. In particular, if your app or an app extension uses `UserDefaults` anywhere, declare `NSPrivacyAccessedAPICategoryUserDefaults` in your app target's manifest as well; a category declared only in a linked SDK's manifest is not always enough to satisfy the upload check.
3. **Custom fields and custom events.** `withStringField(key:values:)`, `withCustomFields(_:)` and `trackCustomEvent(...)` send whatever you put in them. This SDK's manifest cannot describe data it does not choose. If you pass an email address, a postal address or anything else sensitive through a custom field, that collection is yours to declare.
4. **Firebase.** Push notifications go through `firebase-ios-sdk`, which carries its own privacy manifest and its own disclosures. Read them; they are not covered here.

Whether the SDK "tracks" in Apple's sense also depends on how your Releva account is configured — for instance whether conversions are forwarded to advertising networks. Confirm the answer for your own integration with Releva before you submit.

## Support

For issues, questions, or feature requests:
- GitHub Issues: https://github.com/Releva-ai/sdk-swift/issues
- Documentation: https://docs.releva.ai/ios-sdk
- Email: support@releva.ai

## License

MIT License - see LICENSE file for details
