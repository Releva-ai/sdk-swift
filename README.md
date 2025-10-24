# Releva SDK for iOS

Native iOS SDK for integrating Releva's recommendation engine, push notifications, and user tracking capabilities into your iOS applications.

## Features

- 📊 **User Tracking & Analytics** - Track screen views, product views, searches, and custom events
- 🛒 **Cart & Wishlist Management** - Sync and track user shopping behavior
- 🔔 **Push Notifications** - Rich push notifications with images and custom actions
- 🎯 **Product Recommendations** - Get personalized product recommendations
- 🔍 **Advanced Filtering** - Complex product filtering with multiple conditions
- 💾 **Offline Support** - Events are queued and sent when connection is available
- 🔐 **Session Management** - Automatic 24-hour session handling

## Requirements

- iOS 15.0+
- Xcode 14.0+
- Swift 5.7+

## Installation

### Swift Package Manager

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

### CocoaPods

Add to your `Podfile`:

```ruby
pod 'RelevaSDK', '~> 1.0.0'

# For Notification Service Extension
target 'NotificationExtension' do
  pod 'RelevaSDK/NotificationExtension', '~> 1.0.0'
end
```

Then run:
```bash
pod install
```

## Quick Start

### 1. Initialize the SDK

```swift
import RelevaSDK

// In your AppDelegate or App initialization
let config = RelevaConfig.full() // or .pushOnly(), .trackingOnly()
let client = RelevaClient(
    realm: "your-realm",
    accessToken: "your-access-token",
    config: config
)

// Set user identification
client.setDeviceId(UIDevice.current.identifierForVendor?.uuidString ?? "")
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

### 3. Add Notification Service Extension (Optional but Recommended)

For rich push notifications with images:

1. File → New → Target
2. Select "Notification Service Extension"
3. Name it (e.g., "NotificationExtension")
4. Add the RelevaSDK to the extension target

In your extension's `NotificationService.swift`:

```swift
import UserNotifications
import RelevaSDK

class NotificationService: UNNotificationServiceExtension {
    // The SDK provides a complete implementation
    // Just inherit from RelevaSDK's NotificationService
}
```

## Core Features

### User Tracking

```swift
// Track screen view
client.trackScreenView(
    screenToken: "home",
    productIds: ["product-1", "product-2"],
    categories: ["electronics", "phones"]
)

// Track product view
let product = ViewedProduct(id: "product-123")
    .withStringField(key: "brand", values: ["Apple"])
    .withNumericField(key: "price", values: [999.99])

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
let event = CustomEvent(action: "add_to_cart")
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
        // Track screen view, "home" should be changed with the token used for home page
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

## Migration from Flutter SDK

If you're migrating from the Flutter SDK:

1. **Banner functionality is excluded** - The iOS SDK does not include banner/in-app messaging features
2. **Navigation** - Screen navigation tracking requires manual implementation (no NavigatorObserver)
3. **Storage** - Uses UserDefaults instead of Hive
4. **Push Notifications** - Native implementation using UNUserNotificationCenter

### Key Differences

| Flutter SDK | iOS SDK |
|------------|---------|
| `RelevaClient(realm, accessToken)` | Same API |
| `setDeviceId(id)` | Same API |
| `setProfileId(id)` | Same API |
| `setCart(cart)` | Same API |
| `trackScreenView()` | Same API |
| Banner support | Not included |
| NavigatorObserver | Manual tracking |
| Hive storage | UserDefaults |
| firebase_messaging | Native + Firebase |

## Troubleshooting

### Common Issues

**Push notifications not working:**
- Verify push notification capability is enabled
- Check that you're calling `registerForRemoteNotifications()`
- Ensure Firebase is properly configured
- Check device token is being registered

**Tracking not working:**
- Verify `enableTracking` is true in config
- Check network connectivity
- Enable debug logging to see requests

**Session expiring too often:**
- Sessions expire after 24 hours by design
- Check device time settings

### Debug Logging

Enable debug logging to see all SDK operations:

```swift
let config = RelevaConfig.debug()
// or
let config = RelevaConfig(enableDebugLogging: true)
```

## Support

For issues, questions, or feature requests:
- GitHub Issues: https://github.com/releva-ai/releva-ios-sdk/issues
- Documentation: https://docs.releva.ai/ios-sdk
- Email: support@releva.ai

## License

MIT License - see LICENSE file for details