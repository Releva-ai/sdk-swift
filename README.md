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

- iOS 15.0+
- Xcode 16.2+ (required by `firebase-ios-sdk` 11.15)
- Swift 5.7 language mode or later (the package declares `swift-tools-version: 5.7`)

## Installation

Swift Package Manager is the only supported distribution channel. The package
exposes two library products:

- `RelevaSDK` — add to your app target.
- `RelevaNotificationExtension` — add to your Notification Service Extension
  target, if you want rich push notifications.

`firebase-ios-sdk` (11.15.0 or newer) is resolved automatically as a dependency,
but SPM only attaches package *products* to targets that ask for them. The push
notification setup below calls `Messaging.messaging()` directly from your own
`AppDelegate`, so your app target also needs to depend on `FirebaseMessaging`
(and `FirebaseCore`, which it requires) explicitly — see below.

### In a `Package.swift` manifest

Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/Releva-ai/sdk-swift.git", from: "3.0.0"),
    // Required because the push setup below calls Messaging.messaging() from
    // your own code: SPM only lets a target use products from packages this
    // manifest declares directly, so a transitive resolve is not enough.
    .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "11.15.0")
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
3. Dependency Rule: "Up to Next Major Version", starting from `3.0.0`
4. Add the `RelevaSDK` product to your app target
5. Add `https://github.com/firebase/firebase-ios-sdk.git` as a second package
   dependency (Dependency Rule: "Up to Next Major Version", starting from
   `11.15.0`) and add its `FirebaseMessaging` and `FirebaseCore` products to your
   app target — the push-notification setup below calls `Messaging.messaging()`
   from your own code, and the "Choose Package Products" sheet for `sdk-swift`
   only offers this package's own products (`RelevaSDK`, `RelevaNotificationExtension`).
6. For rich push notifications, also add the `RelevaNotificationExtension` product
   to your Notification Service Extension target — see
   [Add Notification Service Extension for Rich Notifications](#3-add-notification-service-extension-for-rich-notifications)

This SDK does not set up Firebase itself: you still need a `GoogleService-Info.plist`
in your app target and a `FirebaseApp.configure()` call (typically in
`application(_:didFinishLaunchingWithOptions:)`, before the push setup below)
from the standard Firebase iOS setup.

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
        _ = try await client.registerPushToken(fcmToken, deviceType: .ios)
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
            _ = try await client.registerPushToken(fcmToken, deviceType: .ios)
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

Most tracking — screen views, product views, search, checkout, recommendations — is sent through a single API: build a `PushRequest` using the fluent builder, then hand it to `client.push(...)`. The builder methods can be chained in any order on the same request.

```swift
// Track a screen view (home page, listing page, etc.)
let request = PushRequest()
    // Token should be changed with the one you have for the page inside Releva's admin panel (UUID)
    .screenView("home")
    .pageProductIds(["product-1", "product-2"])
    .pageCategories(["electronics", "phones"])
    .locale("en_US")
    .currency("USD")

client.push(request) { result in
    switch result {
    case .success(let response):
        // Process recommendations returned for this page
        for recommender in response.recommenders {
            print("Recommender: \(recommender.name)")
            for product in recommender.response {
                print("- \(product.name): $\(product.price)")
            }
        }
    case .failure(let error):
        print("Error: \(error)")
    }
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

client.push(productRequest) { _ in }

// Track a search
let searchRequest = PushRequest()
    // Token should be changed with the one you have for search page inside Releva's admin panel (UUID)
    .screenView("search_results")
    .search("iPhone")
    .pageProductIds(["product-1", "product-2", "product-3"])

client.push(searchRequest) { _ in }
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
client.trackCheckoutSuccess(orderedCart: orderedCart, screenToken: "checkout_success") { _ in }
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

client.trackCustomEvent(event)
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

client.push(request) { _ in }
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

```swift
ContentView()
    .npsDisplay(onSubmit: { token, score, comment in
        client.submitNpsResponse(token: token, score: score, comment: comment)
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

All mutations use optimistic updates — the UI updates instantly, and reverts on API error:

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
| `design` | `[String: Any]` | Unlayer design JSON, ready to render via `InboxMessageView`. |
| `read` | `Bool` | Whether the user has read this message. |
| `createdAt` | `Date` | When the message was delivered. Messages are sorted newest-first. |
| `inboxMessageId` | `Int` | ID of the source message template. Use for push notification routing. |

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

| Method | Description |
|---|---|
| `init(realm:accessToken:config:)` | Initialize the SDK |
| `setDeviceId(_:)` | Set unique device identifier |
| `setProfileId(_:_:)` | Set user profile ID (second param: skipMerge) |
| `setEndpointOverride(_:)` | Override API endpoint at runtime |
| `setAppVersion(_:)` | Set app version for NPS context |
| `setCart(_:)` | Set shopping cart |
| `setWishlist(_:)` | Set wishlist |
| `clearCartStorage()` | Clear cart without API call |
| `clearWishlistStorage()` | Clear wishlist without API call |
| `push(_:completion:)` | Send a push request |
| `trackScreenView(screenToken:productIds:categories:filter:completion:)` | Track screen view |
| `trackProductView(product:screenToken:completion:)` | Track product view |
| `trackSearchView(query:resultProductIds:screenToken:filter:completion:)` | Track search |
| `trackCheckoutSuccess(orderedCart:screenToken:completion:)` | Track checkout |
| `trackCustomEvent(_:screenToken:completion:)` | Track custom event |
| `registerPushToken(_:deviceType:completion:)` | Register FCM token |
| `refreshPushToken()` | Re-fetch via `pushTokenProvider` and re-upload if stale |
| `pushTokenProvider` | Closure the SDK calls on launch/foreground to get the current token |
| `enablePushEngagementTracking()` | Enable push engagement tracking |
| `trackEngagement(userInfo:type:)` | Track push engagement |
| `isRelevaMessage(userInfo:)` | Check if notification is from Releva |
| `bannerImpression(_:)` | Track banner impression |
| `bannerAction(_:action:)` | Track banner action |
| `storyImpression(_:)` | Track story impression |
| `storyAction(_:action:slideId:)` | Track story action |
| `trackEvent(_:)` | Fire NPS custom event trigger |
| `submitNpsResponse(token:score:comment:completion:)` | Submit NPS response |
| `initializeInbox()` | Initialize inbox service |
| `inbox` | Access InboxService singleton |

## Async/Await Support

The SDK supports modern Swift async/await patterns:

```swift
// Using async/await
Task {
    do {
        let response = try await client.trackScreenView(screenToken: "home")
        let success = try await client.registerPushToken(token)
        let result = try await client.push(request)
    } catch {
        print("Error: \(error)")
    }
}
```

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

| Type | What it is |
| --- | --- |
| User ID | the `profileId` you set via `setProfileId(_:)` |
| Device ID | the `deviceId` you set via `setDeviceId(_:)`, and the FCM push token |
| Product Interaction | screen and product views, cart and wishlist contents, custom events, banner/story/NPS impressions and clicks |
| Search History | the query string you pass to `trackSearchView(query:...)` |
| Purchase History | order ID, products, quantities, prices and total from `trackCheckoutSuccess(...)` |
| Other User Content | the optional free-text `comment` on `submitNpsResponse(...)` |

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
