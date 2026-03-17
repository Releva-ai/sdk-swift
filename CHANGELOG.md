# Changelog

All notable changes to this project will be documented in this file.

## [1.0.4] - 2026-03-16

### Added

- Banner/in-app messaging support with full Unlayer design rendering
  - Popup banners (centered dialog with overlay, full-screen support)
  - Bar banners (top/bottom overlay with close button)
  - Flyout banners (side panel from left/right)
  - Static banners (inline with content: afterbegin, beforeend, afterend, replace strategies)
- `BannerDisplayController` for reactive banner event streaming via Combine
- `BannerManagerService` for banner trigger logic (immediately, delay, scroll, cart/wishlist changes)
- `DesignRenderer` for converting Unlayer JSON designs to native SwiftUI views
  - Supports: image, text, heading, button, divider content types
  - Color parsing (hex, rgba), dimension parsing, edge insets
- `BannerDisplayView` SwiftUI view modifier for easy integration
- `bannerImpression()` and `bannerAction()` tracking methods on `RelevaClient`
- Banner response parsing in `RelevaResponse` (supports `[String: Any]` design JSON)
- `.bannerDisplay()` view modifier for SwiftUI integration

## [1.0.3] - 2026-03-16

### Fixed

- Fix push notification click tracking not registering on the backend
  - Callback URL was being prepended with the SDK base URL, producing an invalid URL
  - Changed from POST with JSON body to a simple GET request, matching what the backend expects
  - Callback URLs are now fired directly using URLSession without auth headers

## [1.0.2] - 2025-12-09

### Changed

- Downgraded Firebase/Messaging dependency from ~> 11.0 to ~> 10.0 for better compatibility

## [1.0.1] - 2025-12-05

### Added

- Added `skipMergeWithPreviousProfileId` parameter to `setProfileId()` method for proper logout handling
  - When `true`, clears merge profile IDs (prevents merging logged-in user profile with anonymous profile)
  - When `false` (default), continues normal merge behavior
  - Maintains backward compatibility with existing code

### Fixed

- Fixed `ProductRecommendation.mergeContext` type handling to support mixed value types from API
  - Now properly handles cases where API returns integers, booleans, or other types in mergeContext
  - Automatically converts all values to strings while preserving data
- Fixed profile merge edge cases to ensure merge IDs are properly persisted

### Changed

- Enhanced debug logging for profile ID changes to show merge behavior

## [1.0.0] - 2025-10-22

### Added

- Initial release of Releva SDK for iOS
- User identification with device ID and profile ID
- Cart and wishlist management
- Screen view tracking
- Product view tracking
- Search tracking
- Checkout success tracking
- Custom event tracking
- Push notification support with rich media
- Engagement tracking (delivered, opened, clicked)
- Advanced filtering system (simple and nested filters)
- Session management with 24-hour expiration
- Offline support with event queuing
- Product recommendations API
- Async/await support for all API methods
- Notification Service Extension for enhanced notifications
- Swift Package Manager support
- CocoaPods support
- Comprehensive documentation and examples

### Technical Details

- Minimum iOS version: 15.0
- Swift version: 5.7+
- Firebase Messaging integration (optional)
- UserDefaults for local storage
- URLSession for networking

### Migration Notes

- This SDK is a native Swift port of the Flutter SDK
- Banner/in-app messaging functionality has been excluded
- Uses UserDefaults instead of Hive for storage
- Manual screen tracking required (no NavigatorObserver equivalent)
