# Changelog

All notable changes to this project will be documented in this file.

## [3.1.2] - 2026-08-11

### Fixed

- **Firebase 12 consumers could not resolve this package at all.** The `firebase-ios-sdk` dependency was declared as `from: "11.15.0"`, and `from:` is shorthand for `.upToNextMajor(from:)` — `>= 11.15.0, < 12.0.0` — so an app that declares `firebase-ios-sdk` itself (which the README now tells integrators to do) on any 12.x version got an unsatisfiable dependency graph, not a warning. The requirement is now the explicit range `"11.15.0"..<"13.0.0"`, so Firebase 11 and 12 both resolve. The alternative, moving the floor to `from: "12.0.0"`, was rejected: this package's floor was only raised to 11.15 in `[3.0.0]`, and nothing here needs Firebase 12 — the sole Firebase API it compiles against is `Messaging.serviceExtension().populateNotificationContent(...)` in `RelevaNotificationExtension`, which is unchanged across both majors (`RelevaSDK` itself imports no Firebase module; the `Messaging.messaging()` mentions in `RelevaClient` are doc comments about what the host app must wire up). No public API and no behaviour changes, and the target-level `.product(name: "FirebaseMessaging", ...)` declarations needed no edit — a product dependency carries no version of its own.

### Changed

- **The README no longer names a single Xcode floor**, because with two Firebase majors in range there isn't one: SPM resolves the newest `firebase-ios-sdk` a consumer's own constraints allow, and Firebase raises its toolchain floor over time, including within the 12.x series. Requirements now refers the reader to Firebase's own iOS release notes for the floor of the version they land on, and records that capping to `"11.15.0"..<"12.0.0"` remains a supported way to stay on Xcode 16.2. The one toolchain pair either file still states is `firebase-ios-sdk` 11.15 needing Xcode 16.2, which is safe to write down because 11.15 is a frozen release; Firebase's floors for the *active* 12.x series are deliberately left to the release notes, since those move on Firebase's schedule rather than this package's. The iOS floor is unaffected — `firebase-ios-sdk` 12.x declares iOS 15, the same as this package. The Installation snippets widen to the same range for the dependency the integrator declares themselves, since `from: "11.15.0"` there resolves fine but silently pins them to Firebase 11.

## [3.1.1] - 2026-08-11

### Fixed

- **A data race in `NetworkService.sendEngagementEvents`.** The fan-out over the deduplicated callback URLs tracked its outcome in a `var allSucceeded` captured by every `URLSession` completion handler, and those handlers run concurrently on the session's delegate queue, so N callbacks wrote the same variable with no synchronisation. Only `false` was ever written, and `DispatchGroup`'s `leave()`/`notify()` pair orders the final read, so the observed result was usually right — but unsynchronised concurrent writes are undefined behaviour under the language memory model regardless, and Swift 6's strict concurrency rejects them outright (`mutation of captured var 'allSucceeded' in concurrently-executing code`). The flag now lives in a small `NSLock`-guarded `CallbackOutcome` object rather than being fixed by annotating the race away with `nonisolated(unsafe) var allSucceeded` or a bare `@unchecked Sendable` on the old captured `var`. `CallbackOutcome` itself is `@unchecked Sendable`, which is the correct and separate use of that conformance: every access to its state already goes through the lock, so the annotation states real synchronisation instead of suppressing the compiler's check for the absence of any — needed because `URLSession`'s completion handler is `@Sendable`, so capturing a non-`Sendable` type there is itself a strict-concurrency error even after the lock is in place. Behaviour is unchanged: the completion still yields `.success(true)` only when every callback succeeded and `.failure(.networkError("Failed to send some events"))` otherwise, on the main queue, once.

### Added

- **Coverage for `sendEngagementEvents`' failure path**, which had none: one callback failing at the transport level, one returning a >= 400 status, several failing at once (the concurrent-write path the race lived on, which also pins that a failing callback does not stop its siblings), an unparseable callback URL being skipped while the rest of the batch still fires, and a batch of nothing but unparseable URLs still completing exactly once — `group.notify` with no `enter()` fires immediately, and the tests' expectations reject over-fulfilment, so a second completion call fails them. The existing dedup test already covered the all-succeed case.

### Changed

- **The eight sub-second inverted expectations in `StoryManagerServiceTests` and `NpsManagerServiceTests` are now deterministic barriers.** They assert an event does *not* arrive, so a timeout can only get less reliable as the runner gets slower — a wrongly-published event landing at 0.4 s passes a 0.3 s window — while costing 3.8 s of every run. Story publication is synchronous when `initialize(...)` is called on the main thread, as XCTest calls it, so those tests now assert directly on what was received. NPS publication is asynchronous along a fixed path (the manager's serial queue, the main queue, the `triggerDelaySeconds` timer, then those two again), so those tests send a marker down the same path and wait for it: every stage is FIFO, and the marker's own timer is scheduled with the same delay as the trigger under test, so when the marker lands, a survey that was going to be published already has been. `NpsManagerService` gains an internal `drainPendingWork(_:)` test seam for this rather than widening `queue` itself to `internal`; `queue` stays `private`, so the module keeps the compiler-enforced guarantee that `NpsManagerService` is the sole enqueuer onto it. The one thing neither form can observe is a trigger whose own delay is still counting down (the two `testDispose` cases, at 60 s), and each says so at the assertion.
- `StoryManagerServiceTests.testDeduplication` loses a fake assertion along with its sleep: the `noMore` inverted expectation it created had no sink attached, so nothing could ever fulfil it and the wait was a 0.3 s sleep that would have passed whatever the code did. The real check is the received-story assertion beside it, which now also pins that the story was published at all.

## [3.1.0] - 2026-08-11

### Added

- **An Apple privacy manifest** at `Sources/RelevaSDK/PrivacyInfo.xcprivacy`, declared as `resources: [.copy("PrivacyInfo.xcprivacy")]` on the `RelevaSDK` target so it reaches the built product rather than only the repository. Without it, an app embedding this SDK cannot satisfy Apple's required-reason API rules at submission. It declares `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1` (`StorageService` reads and writes its own `rlv_`-prefixed keys in `UserDefaults.standard` — the suite is `.standard` because `RelevaClient` calls `StorageService()` with no argument, not because `init(userDefaults:)` forbids one, so `1C8F.1` would have to join the reasons if that call site ever passed an App Group suite; `C56D.1` does not apply either way), and six collected data types, all marked `Linked` and none marked `Tracking`: User ID (`profileId`), Device ID (`deviceId`, the FCM push token, and the session ID — a fresh UUID minted on every cold start and never read back on the next launch, so it identifies a session rather than the device), Product Interaction (screen and product views, cart, wishlist, custom events, banner/story/NPS impressions and clicks), Search History (`trackSearchView(query:)`), Purchase History (`trackCheckoutSuccess`) and Other User Content (the free-text `comment` on `submitNpsResponse`). The five behavioural types carry `ProductPersonalization` + `AppFunctionality` + `Analytics` as purposes (Analytics signed off by Releva on 2026-08-11: Customer Insights — RFM scoring, cohort analysis, funnels, audience performance — is built on exactly these identifiers and events); Other User Content carries `AppFunctionality` alone, because the NPS free-text comment is read individually by a marketer rather than aggregated into an audience measure. Email address, phone number, name and physical address are deliberately **not** declared — the `[2.0.0]` entry below removed the only API that accepted contact details, so declaring them would make every host app's App Store disclosure wrong. `NSPrivacyTracking` is `false` and `NSPrivacyTrackingDomains` is empty; the latter is not an oversight, because the OS blocks requests to every domain listed there for users who decline the App Tracking Transparency prompt, and none of the hosts the SDK talks to is an ad network or tracking host (its own API endpoint — `<realm>.releva.ai` by default, or whatever the public `RelevaConfig.customEndpoint` points at — plus, in the extension, the attachment URL carried in the push payload). `RelevaNotificationExtension` gets no manifest of its own: it uses no required-reason API and collects nothing in its own right.
- `PrivacyManifestTests`, which reads the manifest out of the resource bundle it actually ships in and pins that it parses as a plist, that the `UserDefaults` reason is exactly `CA92.1` and that no other required-reason category is declared, that the six collected types are present with `Linked` / `Tracking` / `Purposes` exactly as above, that `NSPrivacyTracking` is `false` and `NSPrivacyTrackingDomains` is still empty, and — as a regression guard on the v2.0.0 promise that contact details never leave the client — that no contact-information type (including physical address) is declared. A plist typo is otherwise invisible until App Store review.
- A README "Privacy Manifest" section covering what the manifest declares and, at equal length, what it does **not** do for the integrator: it does not fill in App Store Connect's App Privacy details, does not cover the app's own required-reason API use, does not describe whatever the app chooses to put in custom fields, and does not cover Firebase.

### Changed

- Adding a resource to the `RelevaSDK` target makes SwiftPM generate a `RelevaSDK_RelevaSDK.bundle` and a `Bundle.module` accessor for that target. This is additive for consumers of both library products. `Bundle.module` is internal to the target it is generated for, and therefore unreachable from the test target even under `@testable import`, which is why the new internal `PrivacyManifest.url` exists inside `RelevaSDK`.

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
- **Code coverage in CI.** The test step now passes `-enableCodeCoverage YES -resultBundlePath TestResults.xcresult`. `scripts/coverage.sh` prints per-target and per-file line coverage from `xcrun xccov view --report --json` and fails if line coverage drops below a 27.0% floor (the suite measures 27.74%); both the CI workflow and `make test` call the same script, and the floor lives in one place inside it so the two callers cannot drift apart. The report is narrowed to this package's own shipped targets: `-enableCodeCoverage` instruments the whole build, so the raw xccov report also covers the Firebase dependency, and the test targets are excluded too. The coverage step and a zipped `TestResults.xcresult` upload both run with `if: !cancelled()`, so a failing test run still reports a number and leaves the per-test failure detail downloadable, without also spending runner time on a cancelled one.
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
