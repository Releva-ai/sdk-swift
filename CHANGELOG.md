# Changelog

All notable changes to this project will be documented in this file.

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