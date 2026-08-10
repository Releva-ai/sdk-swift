# Changelog

All notable changes to this project will be documented in this file.

## [3.0.0] - 2026-08-10

### Removed

- **BREAKING — CocoaPods support removed; Swift Package Manager is now the only distribution channel.** `RelevaSDK.podspec` is deleted. The pod was never published to the CocoaPods trunk; the only way to consume it was a local-path `Podfile` entry (`pod 'RelevaSDK', :path => '../sdk-swift'`) against a clone of this repository, and no tagged release ever shipped that path — the last tag is `v1.0.4`, predating it. This is a major bump because the break is a source break, not merely a packaging one: under CocoaPods the root spec and the `NotificationExtension` subspec compiled into a single `RelevaSDK` module, so an extension that builds today against `import RelevaSDK` no longer compiles. **Migration:** remove the `RelevaSDK` / `RelevaSDK/NotificationExtension` entries from your `Podfile`, run `pod install`, then add `https://github.com/Releva-ai/sdk-swift.git` as a Swift package dependency and attach the `RelevaSDK` product to your app target and the `RelevaNotificationExtension` product to your Notification Service Extension target. Under SPM the extension base class lives in its own module, so `NotificationService.swift` must `import RelevaNotificationExtension` instead of `import RelevaSDK`. If your app also calls `Messaging.messaging()` directly (see the README's push setup), you now need to declare `firebase-ios-sdk` as a package dependency of your own app too — see `### Changed` below and the README Installation section.
- `Package.resolved` is no longer committed (it is now gitignored): it pinned Firebase 10.29.0, and for a library package it is not consulted by downstream consumers.

### Changed

- Raised the `firebase-ios-sdk` floor in `Package.swift` from `10.0.0` to `11.15.0`, which is what the removed podspec required (`Firebase/Messaging ~> 11.15`) and therefore what integrations were actually building against. This is a floor raise across a Firebase major version, not a cost-free bump: an app still pinned to Firebase 10.x that also declares `firebase-ios-sdk` directly (now necessary per the README) will hit a resolution conflict, not a silent upgrade, until it moves to 11.x too — see [Firebase's own iOS SDK release notes](https://firebase.google.com/support/release-notes/ios) for that migration (it requires Xcode 16.2+, which the Requirements section of the README now states). Firebase 11.15.0's own manifest declares an iOS 12 platform floor, below this package's iOS 15 floor, so there is no platform conflict with this package itself.

### Added

- **iOS CI.** `.github/workflows/ci.yml` runs on `macos-latest` for pull requests and pushes to `master`: builds the aggregate `RelevaSDK-Package` scheme (both library targets) for `generic/platform=iOS`, then runs the test suite on an iOS simulator resolved at runtime from the runner image. The scheme name and simulator are both discovered at runtime (`xcodebuild -list -json`, `xcrun simctl list devices`) rather than hardcoded.
- A test (`SDKVersionChangelogTests`) that pins `SDKVersion.current` against the top `CHANGELOG.md` heading, so CI now fails if the version constant and this file drift apart, as they did between `[2.0.0]` and the podspec.
- **Unit coverage for the request/response and storage layers**, 196 new tests across seven files: `FilterSerializationTests` (the encoded JSON shape of every `Filter` operator, nested AND/OR groups, value coercion), `PushRequestTests` (payload construction across the `PushRequest` builders and factories, alongside the existing `PushPayloadIdentityTests`), `NetworkServiceTests` (request construction, base-URL precedence between realm / `customEndpoint` / `setEndpointOverride`, headers, and success/error mapping, asserted against a `URLProtocol` stub — no test performs real network I/O), `StorageServiceTests` (per-key round-trips, overwrites, absent-value defaults and clearing, against an injected `UserDefaults` suite rather than `.standard`), `RecommenderResponseTests` (`ProductRecommendation` / `RecommenderResponse` decoding of realistically shaped payloads including nulls, missing optionals and unknown keys), `SessionTests` (`Core/Session.swift`'s 24-hour window and `SessionManager` persistence) and `DesignRendererParsingTests` (the pure colour/dimension/inset/HTML parsing helpers).
- **Code coverage in CI.** The test step now passes `-enableCodeCoverage YES -resultBundlePath TestResults.xcresult`. `scripts/coverage.sh` prints per-target and per-file line coverage from `xcrun xccov view --report --json` and fails if line coverage drops below the floor it's given; both the CI workflow and `make test` call it with the same `MIN_LINE_COVERAGE`, so the number a developer sees locally is the one that gates CI. The report is narrowed to this package's own shipped targets: `-enableCodeCoverage` instruments the whole build, so the raw xccov report also covers the Firebase dependency, and the test targets are excluded too. The coverage step and a `TestResults.xcresult` upload both run with `if: always()`, so a failing test run still reports a number and leaves the per-test failure detail downloadable.
- **A `Makefile`** with `build`, `test` and `lint` targets that wrap the same commands CI runs. `build` and `test` refuse to run off macOS with `iOS builds require macOS with Xcode; CI runs these on macos-latest`; there is deliberately no Docker or Linux-toolchain path.

### Fixed

- Corrected the repository URL in the README installation instructions and the Support section: the previously documented `github.com/releva-ai/releva-ios-sdk.git` does not exist, the package lives at `github.com/Releva-ai/sdk-swift.git`.
- The README's push-notification setup snippet calls `Messaging.messaging()` but only imported `UserNotifications`, so it did not compile as written; it now imports `FirebaseMessaging` too. The logout snippet in the profile-ID section, which makes the same call, now notes the same requirement.

## [2.0.0] - 2026-07-17

### Changed

- **BREAKING — profile attributes removed from the public API.** `trackCheckoutSuccess(...)`, `CheckoutSuccessRequest` (including its `withUserInfo`, `complete`, and `guestCheckout` factories, the `hasUserInfo`/`isRegisteredUser` properties and the email-format validation) and the `PushRequest.profile(email:phoneNumber:firstName:lastName:registeredAt:)` builder no longer accept `email`, `phoneNumber`, `firstName`, `lastName` or `registeredAt`. The SDK now identifies users solely by the `profileId` set via `setProfileId(_:)`; contact details and other profile attributes are never sent from the client. **Migration:** drop these arguments; use `CheckoutSuccessRequest(orderedCart:screenToken:)` / `CheckoutSuccessRequest.minimal(orderId:products:)` and `trackCheckoutSuccess(orderedCart:screenToken:)`.
- Aligned the podspec version with the SDK version constant (both now `2.0.0`; the podspec previously lagged at `1.0.4`).

## [1.2.0] - 2026-03-19

### Added

- **Lifecycle-based session tracking.** New `SessionService` uses `UIApplication` lifecycle notifications to count sessions based on foreground/background transitions (>30s threshold). Each new session generates a fresh `sessionId`. Push payload now includes `device.sessions`, `device.views`, and `device.firstSeenAt`.

### Fixed

- **Banner text color ignoring content-level `color` property.** Text and heading elements in banner designs now correctly read the Unlayer `color` field, with fallback to `textColor` then body default. Previously only `textColor` was checked, causing content with explicit `color` (e.g. white text on dark background) to render in the body default color (black).

## [1.1.0] - 2026-03-17

### Added

- **NPS Surveys** - Full NPS survey support with server-driven UI
  - `NpsConfig`, `NpsFollowUp`, `NpsThankYou`, `NpsAppearance`, `NpsTrigger` models
  - `NpsManagerService` for trigger evaluation (customEvent, appOpen, sessionCount, screenView)
  - `NpsDisplayController` for reactive NPS event streaming via Combine
  - `NpsDisplayView` SwiftUI view modifier with 3-step survey flow (score → follow-up → thank you)
  - Dark mode support, server-driven colors, button styles (pill/rounded/square)
  - Session-scoped suppression and cancel event support
  - `submitNpsResponse()` method on `RelevaClient` with silent retry
  - `trackEvent()` for firing NPS custom event triggers
  - `setAppVersion()` for NPS server-side version filtering

- **Stories** - Instagram/Facebook-style full-screen story viewer
  - `StoryResponse`, `StorySlideResponse` models
  - `StoryManagerService` for trigger logic (immediately, delay, scroll, cart/wishlist changes)
  - `StoryDisplayController` for reactive story event streaming via Combine
  - `StoryDisplayView` SwiftUI view modifier with queue-based sequential presentation
  - `StoryViewerView` full-screen viewer with progress bars, auto-advance, tap/swipe navigation
  - Slide content rendered via `DesignRenderer` (reuses banner rendering infrastructure)
  - End behaviors: dismiss, loop, stayOnLast
  - `storyImpression()` and `storyAction()` tracking methods on `RelevaClient`

- **App Inbox** - Persistent in-app messaging with cursor pagination
  - `InboxMessage`, `InboxState` models
  - `InboxService` singleton (ObservableObject) with:
    - Cursor-based pagination (refresh, loadMore)
    - Optimistic updates with rollback (markAsRead, markAllAsRead, deleteMessage)
    - Local cache persistence via UserDefaults
    - Stale cache detection (auto-refresh after 5 minutes)
    - App lifecycle awareness (refresh on foreground resume)
    - Silent push sync via `handleSyncSignal()`
    - Message lookup by `inboxMessageId` for push notification routing
  - `InboxMessageView` SwiftUI view for rendering message content via `DesignRenderer`
  - Six inbox API endpoints: fetchMessages, fetchUnreadCount, markAsRead, markAllAsRead, delete, trackAction
  - `initializeInbox()` and `inbox` accessor on `RelevaClient`

- **Endpoint Override** - Runtime API endpoint override for local development
  - `setEndpointOverride(_ url: String?)` on `RelevaClient`
  - Takes precedence over both realm-based URL and config `customEndpoint`

- **Notification Enhancements**
  - `isRelevaMessage()` now uses prefix matching (`RELEVA_*`) to support `RELEVA_INBOX_SYNC`
  - Silent push `inbox_sync` signal triggers automatic inbox refresh
  - `navigate_to_parameters` JSON is parsed and forwarded for inbox message routing

- **Response Parsing**
  - `RelevaResponse` now includes `stories: [StoryResponse]` and `nps: NpsConfig?`
  - Stories and NPS initialized from push response alongside banners

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
