# Releva SDK for iOS

Native iOS SDK for integrating Releva's recommendation engine, push notifications, and user tracking capabilities into your iOS applications.

## Features

- 📊 **User Tracking & Analytics** - Track screen views, product views, searches, and custom events
- 🛒 **Cart & Wishlist Management** - Sync and track user shopping behavior
- 🔔 **Push Notifications** - Rich push notifications with images and custom actions
- 🔍 **Advanced Filtering** - Complex product filtering with multiple conditions
- 💾 **Offline Support** - Events are queued and sent when connection is available
- 🔐 **Session Management** - Automatic 24-hour session handling
- 🎯 **Product Recommendations** - Get personalized product recommendations

## Requirements

- iOS 15.0+
- Xcode 14.0+
- Swift 5.7+

## Installation

### Using CocoaPods

Add to your `Podfile`:

```ruby
target 'YourApp' do
  # Make sure you have cloned sdk-swift repository one directory outside of the Application - https://github.com/Releva-ai/sdk-swift

  pod 'Firebase/Core', '~> 11.0'

  # Local Releva SDK
  pod 'RelevaSDK', :path => '../sdk-swift'
  
  # For Notification Service Extension
  target 'NotificationExtension' do
    pod 'Firebase/Messaging', '~> 11.0'
    pod 'RelevaSDK/NotificationExtension', :path => '../sdk-swift'
  end
end
```

Then run:
```bash
pod install
```

### Using Swift Package Manager

Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/releva-ai/releva-ios-sdk.git", from: "1.0.0")
]
```

Or in Xcode:
1. File → Add Package Dependencies
2. Enter: `https://github.com/releva-ai/releva-ios-sdk.git`
3. Select version: 1.0.0 or later


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
    let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    client.registerPushToken(token)
    client.enablePushEngagementTracking()
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

#### Step 2: Add SDK to Extension's Podfile

Update your `Podfile`:

```ruby
target 'YourApp' do
  # Make sure you have cloned sdk-swift repository one directory outside of the Application - https://github.com/Releva-ai/sdk-swift

  pod 'Firebase/Core', '~> 11.0'

  # Local Releva SDK
  pod 'RelevaSDK', :path => '../sdk-swift'
  
  # For Notification Service Extension
  target 'NotificationExtension' do
    pod 'Firebase/Messaging', '~> 11.0'
    pod 'RelevaSDK/NotificationExtension', :path => '../sdk-swift'
  end
end
```

Run:
```bash
pod install
```

#### Step 3: Inherit from SDK's Base Class

In your extension's `NotificationService.swift`, replace the entire file with:

```swift
import UserNotifications
import RelevaSDK

class NotificationService: RelevaNotificationServiceExtension {
    // That's it! No additional code needed.
    // The SDK handles all rich notification processing automatically.
}
```

**Done!** Your app now supports:
- ✅ Push notifications with images
- ✅ Custom action buttons
- ✅ Automatic click tracking
- ✅ Deep link handling (both internal and external URLs)
- ✅ Screen navigation within your app

> **Note**: The SDK uses runtime reflection to safely handle UIApplication APIs. This means it works out-of-the-box in both your main app and the extension without any build configuration.

### Navigation Types Supported

The SDK supports two types of navigation from push notifications:

**1. Screen Navigation** (`target: "screen"`):
```json
{
  "target": "screen",
  "navigate_to_screen": "/cart"
}
```
Posts a `RelevaNavigateToScreen` notification that your app can observe.

**2. URL Navigation** (`target: "url"`):
```json
{
  "target": "url",
  "navigate_to_url": "https://example.com"
}
```
- **Internal deep links** (e.g., `myapp://...`): Posts `RelevaNavigateToURL` notification for your app to handle
- **External URLs** (e.g., `https://...`): Opens in Safari or appropriate app

## Core Features

### User Tracking

```swift
// Track screen view
client.trackScreenView(
    // Token should be changed with the one you have for home page inside Releva's admin panel (UUID)
    screenToken: "home",
    productIds: ["product-1", "product-2"],
    categories: ["electronics", "phones"]
)

// Track product view
let product = ViewedProduct(id: "product-123")
    .withStringField(key: "brand", values: ["Apple"])
    .withNumericField(key: "speakersCount", values: [2])

client.trackProductView(
    product: product,
    screenToken: "product_detail"
)

// Track search
client.trackSearchView(
    query: "iPhone",
    resultProductIds: ["product-1", "product-2", "product-3"],
    screenToken: "search_results"
)
```

### Cart Management

```swift
// Create cart products
let product1 = CartProduct(id: "sku-123", price: 29.99, quantity: 2)
let product2 = CartProduct(id: "sku-456", price: 49.99, quantity: 1)

// Set active cart
let cart = Cart.active([product1, product2])
client.setCart(cart)

// Track checkout success
let orderedCart = Cart.paid([product1, product2], orderId: "order-789")
client.trackCheckoutSuccess(
    orderedCart: orderedCart,
    userEmail: "user@example.com",
    userFirstName: "John",
    userLastName: "Doe"
)
```

### Wishlist Management

```swift
let wishlistProducts = [
    WishlistProduct(id: "product-1"),
    WishlistProduct(id: "product-2")
]

client.setWishlist(wishlistProducts)
```

### Custom Events

```swift
let event = CustomEvent(action: "selectedColor")
    .withProduct(id: "product-123", quantity: 1)
    .withTag("promo")
    .withCustomFields(customFields)

client.trackCustomEvent(event)
```

### Advanced Filtering

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

// Apply filter to screen view
client.trackScreenView(
    screenToken: "category_listing",
    filter: complexFilter
)
```

### Get Recommendations

```swift
// Build request
let request = PushRequest()
    .screenView("home")
    .locale("en_US")
    .currency("USD")

// Send request
client.push(request) { result in
    switch result {
    case .success(let response):
        // Process recommendations
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
```

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

## Async/Await Support

The SDK supports modern Swift async/await patterns:

```swift
// Using async/await
Task {
    do {
        // Track screen view, "home" should be changed with the token used for home page in Releva's admin panel
        let response = try await client.trackScreenView(screenToken: "home")

        // Register push token
        let success = try await client.registerPushToken(token)

        // Send custom request
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
- Check the extension is included in your Podfile with Firebase/Messaging
- Run `pod install` after adding the extension
- **CRITICAL**: Notification payload must include `"mutable-content": 1` in the `aps` section
- Test with app in background (extensions don't run when app is in foreground)
- Verify `imageUrl` is a valid, publicly accessible HTTPS URL
- Check Xcode Console for "RelevaSDK" logs to see processing details
- Example payload:
  ```json
  {
    "aps": {
      "alert": { "title": "Test", "body": "Message" },
      "mutable-content": 1
    },
    "click_action": "RELEVA_NOTIFICATION_CLICK",
    "imageUrl": "https://example.com/image.jpg",
    "button": "View"
  }
  ```

**Tracking not working:**
- Verify `enableTracking` is true in config
- Check network connectivity
- Enable debug logging to see requests
- Confirm realm and access token are correct

**Session expiring too often:**
- Sessions expire after 24 hours by design
- Check device time settings

**Build errors about UIApplication in extensions:**
- Update to SDK version 1.0.0+ which uses runtime reflection
- No build flags or Podfile modifications should be needed
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
- UIApplication availability (in extensions vs main app)
- Token registration

## Support

For issues, questions, or feature requests:
- GitHub Issues: https://github.com/releva-ai/releva-ios-sdk/issues
- Documentation: https://docs.releva.ai/ios-sdk
- Email: support@releva.ai

## License

MIT License - see LICENSE file for details