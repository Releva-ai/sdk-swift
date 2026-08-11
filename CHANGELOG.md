# Changelog

All notable changes to this project will be documented in this file.

## [4.1.0] - 2026-08-11

### Added

- **UIKit presenters for banners and NPS surveys: `BannerPresenter(host:client:onLinkTap:)` and `NpsPresenter(host:onSubmit:onSkip:)`.** Both are `@MainActor public final class`es with a `start()` / `stop()` pair to bracket with the host's `viewWillAppear` / `viewWillDisappear`, and both hold the host weakly. Until now the only way to show a banner or a survey was `View.bannerDisplay(client:targetSelector:onLinkTap:)` or `View.npsDisplay(onSubmit:onSkip:)`, so a UIKit app had to stand up a `UIHostingController` wrapping an otherwise empty SwiftUI view just to get a modifier onto the screen. Neither presenter reimplements any rendering: they host the same SwiftUI views the modifiers do inside `UIHostingController`s. `BannerPresenter` owns a `BannerDisplayViewModel` — the same class the modifier drives — subscribes to its `@Published` banner state and mirrors that into UIKit, so impressions, clicks and dismissals are reported by the same code on both paths and cannot drift apart. A popup and a flyout are two slots in one hosted `BannerOverlayView` presented `.overFullScreen`, rather than a modal each: two banners arriving together then stack exactly as they do in SwiftUI, with no per-banner modal bookkeeping to go stale when dismissing one takes the other down with it. Both presenters present from `host.topMostPresentedViewController` (a new internal `UIViewController` extension, skipping anything mid-dismissal) so a banner or survey arriving while the app already has a modal up is shown over it instead of failing with "already presenting". Bar banners are the exception to the modal approach: a modal would black the whole screen out for a strip of chrome, so each screen edge gets a child view controller hosting a `BannerBarStackView` that is empty — and therefore zero-height and untouchable — until a bar for that edge arrives. Those two children are pinned to the host's `safeAreaLayoutGuide`, so rotation is Auto Layout's problem rather than the presenter's; on iOS 16 and up their height comes from `UIHostingController.sizingOptions = .intrinsicContentSize`, and below that, where `sizingOptions` does not exist, from a height constraint the presenter sets from `sizeThatFits(in:)` on each reconcile. That iOS 15 fallback re-measures when the banner set changes but not when the host's width changes, so a bar that appears in one orientation and is still up after a rotation can be mis-measured until the next banner event; it is not re-measured on rotation in this release.
- **A README "UIKit Integration" section**, covering all four surfaces a UIKit app needs and not just the two new presenters: banners and NPS through the presenters, stories by presenting `StoryViewerView` in a `UIHostingController`, and inbox messages by putting `InboxMessageView` in one — both pushed onto a `UINavigationController` and presented modally. It also shows subscribing to `StoryDisplayController.shared.storyPublisher` directly with Combine and tearing the subscription down, since a story arrives as a display event rather than through a presenter. Every snippet was written against the actual initialisers rather than from memory: that is what `StoryViewerView`'s new `public init` below exists for, and it is why the story sample calls `RelevaClient.storyImpression(_:)` explicitly — `StoryViewerView` reports slide views, slide clicks, completion and close, but not the story-level impression, which the SwiftUI `storyDisplay` path also leaves to its caller.
- **A `public init` on `StoryViewerView`.** The view was public and documented as the way to show a story, but its memberwise initialiser was internal, so no `UIHostingController` outside this package could actually construct one — the story path did not work from UIKit at all, whatever the README said. Its parameters and their meanings are unchanged; `onClose` is documented as the caller's cue to take the viewer off screen, because the view does not dismiss itself.
- **`BannerPresenterTests`, `NpsPresenterTests` and `BannerDisplayViewModelTests`**, driving each presenter through the display-controller singleton its production publisher comes from, with a `BannerTracker` spy in place of `RelevaClient` so no test performs network I/O. They cover: a popup reaching the screen as an `.overFullScreen` hosting controller with its impression counted; a popup and a flyout arriving together sharing one presented controller and counting two impressions; a bar banner going into a child view controller rather than a modal; a static banner being neither shown nor counted; the presentation target being the frontmost modal rather than the host underneath it; dismissing a popup, a flyout or a bar reporting `bannerClose`, taking a bar out of the stack and dropping a popup or flyout from the view model immediately; `stop()` not putting anything back on screen, removing the bar slots and ignoring later banners; the same banner re-delivered after a `stop()` / `start()` round trip not being counted a second time, since `viewModel.stop()` leaves `displayedBanners` populated; and for NPS, a survey presented as a `.pageSheet`, a second survey ignored while one is on screen, and a stopped presenter leaving no survey other than the one that was already up — which is what both the banner and NPS `stop()` cases assert, since whether the reference is released at once or held until UIKit confirms the dismissal is a branch of the source that this test host cannot pin down either way. What they deliberately do **not** assert on is UIKit having *finished* a presentation or a dismissal: modal transitions never complete in xcodebuild's generated SPM test host, which has no scene manifest and therefore no `UIWindowScene`, so `present`'s and `dismiss`'s synchronous bookkeeping is observable there but the transition that follows either is not, and neither presenter's dismiss-completion cleanup is exercised as a result. `PresentationTestSupport.makeVisibleWindow` documents that boundary in full.
- **SwiftLint now runs in CI, as a gate.** `.swiftlint.yml` has switched on 22 opt-in rules for a long time, but nothing ever executed it — `make lint` needs macOS and the workflow never called it. A new `SwiftLint` job in `.github/workflows/ci.yml` installs a pinned SwiftLint (0.65.0) from its GitHub release and runs `swiftlint lint`. It is a separate job from `iOS build and test`, so a lint failure and a compile failure can never be mistaken for one another and neither hides the other, and it touches neither the `.spm` package cache nor the package graph. `strict: true` is now set in `.swiftlint.yml` rather than passed as a `--strict` flag, so `make lint` cannot drift into being more lenient than CI. SwiftLint is *not* preinstalled on the `macos-latest` runner image, hence the explicit pinned install rather than relying on the image.

### Changed

- **The popup, flyout and bar chrome moved out of `BannerDisplayModifier` into an internal `BannerChrome`.** The modifier's `body` still assembles the same `ZStack`, but the views themselves are now static `@ViewBuilder` functions the presenter calls too — the alternative was a second renderer for the UIKit path, which is exactly how the two paths would start reporting different impressions and drawing different close buttons. The extracted code is unchanged apart from `bar` taking the safe-area inset it needs as a parameter, because the presenter's bars are already inside the safe area and the modifier's overlay bars are not. `BannerDisplayModifier`'s own signature and behaviour are untouched, as is `View.bannerDisplay(client:targetSelector:onLinkTap:)`; this release is additive for every existing SwiftUI integration.
- **`BannerDisplayViewModel.start` now takes a `BannerTracker` and an `overlayOnly` flag.** `BannerTracker` is a new internal protocol with the two methods banner display calls on `RelevaClient` (`bannerImpression`, `bannerAction`), which `RelevaClient` conforms to in an empty extension — its public surface is unchanged. It exists because `RelevaClient` builds its own `NetworkService` over `URLSession.shared` and has no injection point, so a test handing one to a view model or presenter would perform real network I/O. `overlayOnly` is what `BannerPresenter` passes: static and replace banners are laid out inline in the host's own content, which a presenter has nowhere to put, so they are dropped in `shouldDisplay` — that is, *before* `trackImpression`, not after, since counting an impression for a banner that is never drawn would be a false report. The SwiftUI modifier passes neither flag and behaves as before.
- **`NpsSurveyView` takes an `onClose` closure instead of reading `@Environment(\.dismiss)`.** `dismiss` only knows how to close a SwiftUI presentation, so the skip button and the two-second auto-dismiss after a thank-you did nothing when the view was hosted in a `UIHostingController` the presenter had presented. The modifier passes a closure that clears its `sheet(item:)` binding, which is what `dismiss` was doing there; the presenter passes one that dismisses the controller. `NpsSurveyView` is internal, so this is not a public API change.

### Fixed

- **Every force-unwrap and force-cast in `Sources/` is gone.** All twelve force-unwraps were the `x != nil && x!` shape — the bang guarded by a `!= nil` test in the same short-circuiting expression, so none of them could actually trap — and they are now the `??` idiom this codebase already used elsewhere: `(price ?? 0) > 0`, `!(imageUrl ?? "").isEmpty`, `(query ?? "").isEmpty`. `NpsManagerService.initialize` needed more than a substitution: `if self.suppressedThisSession || config == nil { return }` followed by `config!` became a single `guard !self.suppressedThisSession, let config = config else { return }`, the shape already used twice in that file. `CustomField.toDict()`'s `values as! [Date]` is now a conditional cast kept alongside its `T.self == Date.self` type test — the test still matters because array casts are element-wise, so an empty `[T]` casts to `[Date]` for any `T`, not just `T == Date`. No public signature changed and no payload changed.
- **`DesignRendererParsingTests`' 4-member helper tuple is a named `RGBAComponents` struct**, clearing the one `large_tuple` violation SwiftLint reports at error severity. The `components.red` / `.green` / `.blue` / `.alpha` call sites are unchanged. `DesignRenderer.parseBackgroundImage`'s 3-member return tuple is also a `large_tuple` violation, but it is public API, which this release does not change; it carries a targeted `swiftlint:disable:this` recording that reason.
- **The three force-unwraps in `Tests/` use `try XCTUnwrap`**, which this suite already prefers: `json.data(using: .utf8)!` in two `RelevaResponseTests` cases, and `SessionServiceTests`' `UserDefaults(suiteName:)!`, whose `setUp` becomes the `setUpWithError() throws` that `StorageServiceTests` and `SessionTests` already use for exactly this construction.

### Known limitations

- `BannerPresenter.stop()` leaves the view model's banner state as it was, so a later `start()` re-presents whatever was on screen without a second impression — the same behaviour the SwiftUI modifier's `@StateObject` already has across `onDisappear`, now stated on `stop()`'s doc comment. There is no `deinit` fallback: a presenter released while started (a host deallocated without a matching `viewWillDisappear`, or an app that forgets `stop()`) leaves any presented overlay on screen with nothing left to dismiss it — call `stop()` to avoid that. A `stop()` whose own dismissal UIKit declines, reachable when the host is popped or dismissed during the overlay's brief `.crossDissolve`, ends the same way if the presenter is never started again: `stop()` cancels the banner subscription before it dismisses, so only a later `start()` on that same presenter picks the overlay back up.
- Dismissing the overlay dismisses via `presentingViewController`, so anything the host app itself presented above the banner goes down with it — the standard trade-off of that approach, now called out at the call site rather than only implied.
- A `present` that UIKit declines rather than honours — it only logs — reaches the screen when the next banner or survey event arrives, not immediately. That is reachable when the frontmost controller's own transition is still in flight, for example during a fast tab switch. Neither presenter keeps a timer or a retry budget for it: both read their state back from UIKit on every reconcile, so an unpresented controller is dropped and re-presented at the next event, and anything sooner would mean waiting out an animated transition that no test in this package can exercise.
- A declined *dismissal* in `NpsPresenter` — the sheet is still `isBeingPresented` when `close` runs, reachable via `stop()` on a fast tab switch or a skip tapped during the sheet's own slide-up — is not retried the way a declined dismissal in `BannerPresenter` is: `present`'s guard treats `surveyController` as still on screen and returns, so every later survey in the session goes unshown until the user swipes the orphaned sheet away themselves. `BannerPresenter` avoids this for a dismiss declined *while it is running* — its `reconcile` re-issues that dismiss on the next banner event — and nothing plays that role for NPS in this release. A dismiss declined by `BannerPresenter.stop()` itself has no such recovery either, since `stop()` cancels the subscription first; that is the `stop()` case in the first bullet above rather than a difference between the two presenters. The same guard also drops a survey that arrives during an *ordinary* dismissal, not only a declined one — `presentingViewController` stays non-nil for the whole of the dismissal transition, `npsPublisher` is a `PassthroughSubject`, and the dismiss completion does not look for a pending survey, so that event is lost rather than deferred. That case is self-limiting, which is the material difference: `surveyController` is clear by the time the next survey arrives, so only the survey inside the transition window goes unshown.
- The iOS 15 bar-height fallback measures with `sizeThatFits(in:)` in the same run-loop turn the banner change was observed. Whether that sees the new content or the previous turn's needs a simulator to observe and is not verified here, consistent with this work originating on Linux with no Swift toolchain.

## [4.0.0] - 2026-08-11

### Changed

- **BREAKING: the open-ended JSON in the response models is now typed `JSONValue` instead of `[String: Any]`.** The affected properties are `InboxMessage.design`, `BannerResponse.cssStyles` / `.design` / `.meta`, `StorySlideResponse.design`, `ProductRecommendation.custom` / `.data` and `RecommenderResponse.meta` — every field whose shape the API, not this SDK, decides. `Any` cost two conformances at once: the enclosing types could not be `Sendable`, so no response could cross a concurrency boundary without an `@unchecked` escape hatch; and they could not be `Codable`, which is why the standard decoders dropped those fields outright (see below). Every converted type now declares `Sendable`, and only `Sendable` — `Equatable` is derivable on all of them as of this change, but nothing in the SDK compares whole models, and `RelevaResponse.==` is left exactly as it was rather than tightened into a synthesized one. `JSONValue` is a public recursive enum with `null` / `bool` / `int` / `double` / `string` / `array` / `object` cases, conforming to `Codable`, `Hashable` and `Sendable`. `int` and `double` are deliberately separate cases rather than one numeric case: a single `Double` would re-encode a JSON `3` as `3.0`, which is a silent wire-format change for anything that reads a payload and writes it back. Reads use accessors of the matching name (`stringValue`, `intValue`, `objectValue`, …) plus `subscript(String)` and `subscript(Int)`, so a design lookup collapses from a chain of `as? [String: Any]` casts to one optional chain. `JSONValue` is `ExpressibleBy{String,Integer,Float,Boolean,Array,Dictionary}Literal`, so dictionary literals still build a design without annotation; it is deliberately **not** `ExpressibleByNilLiteral`, which would make `parseColor(nil)` ambiguous between `JSONValue.null` and the absent optional. The `from(dict:)` factories still take `[String: Any]` and `toDict()` still returns it — they now bridge at the boundary via `[String: JSONValue](any:)` and `.anyValue` — so `InboxService`'s `JSONSerialization` round-trip and the persisted inbox state are unchanged on disk. The bridge maps numbers back to `NSNumber` so the factories' existing `as? NSNumber` / `as? Bool` reads see exactly what `JSONSerialization` gave them before, and it checks `CFGetTypeID(number) == CFBooleanGetTypeID()` on the way in, because a `CFBoolean` is otherwise indistinguishable from the numbers 0 and 1 once bridged to `NSNumber`. The README gains a "Migrating to 4.0.0" section with the old→new type of every changed property. The request payload is untouched: nothing the SDK sends changed, and `PrivacyInfo.xcprivacy` is unchanged because no data this SDK collects or transmits changed.
- **`RelevaResponse` now has one decoding path.** `init(from:)` decoded only the `Codable`-compatible fields, set `stories = []` and `nps = nil`, and `print`ed a warning naming `from(jsonData:)` as the method to call instead — so a plain `JSONDecoder().decode(RelevaResponse.self, from:)`, which is what any consumer would reach for and what `Codable` conformance advertises, silently returned half a response. `from(jsonData:)` in turn parsed banners, stories and NPS out of a *separate* `JSONSerialization` pass and merged them over a second, full `JSONDecoder` run, so every response was parsed twice and the two paths could disagree. Both are gone: `init(from:)` decodes those three keys as `JSONValue` and hands them to the same `from(dict:)` factories, and `from(jsonData:)` is now a one-line `JSONDecoder().decode(...)` kept for source compatibility. This also retires the internal `RawJSON` helper, whose only purpose was decoding banners into `Any`. Decoding is now complete, but `encode(to:)` is unchanged and still writes only `recommenders` and `push` — that asymmetry is intentional (these three fields are read-only API payloads the SDK never re-encodes) and is documented on the type and in the README rather than closed in this release.
- **BREAKING: `PushRequest` and the three tracking requests are `Sendable` value types.** `PushRequest` was a class that accumulated its payload in a `private var request: [String: Any]` — the last `[String: Any]` stored property left in `Sources` — and `ScreenViewRequest` / `SearchRequest` / `CheckoutSuccessRequest` were subclasses that applied themselves to `self` inside their own `init`, which is what forced `PushRequest` to stay non-final and kept the whole family off `Sendable`. All four are now structs. `PushRequest` holds its page context as `[String: JSONValue]`, but the product, the custom events and the page filter stay typed as `ViewedProduct`, `[CustomEvent]` and `AbstractFilter`, with `toDict()` still calling their own `toDict()` verbatim; routing those through `JSONValue` too was rejected because `JSONValue(any:)` normalises a whole-number `Double` to `.int`, so a `CartProduct.quantity` of `2.0` or a `CustomField<Double>` value would have started going out as `2` — exactly the silent wire-format change the separate `int` case exists to prevent. Nothing the SDK sends changed. The fluent builders keep their names and read identically in a chain, but each now returns a modified copy rather than `self`, and they are deliberately **not** `@discardableResult`: under value semantics a discarded result is an edit that was dropped, so a statement-style call is now a compiler diagnostic instead of an attribute silently missing from the payload. The three tracking requests no longer inherit; they conform to a new `PushRequestConvertible` protocol — a `pushRequest` that builds the payload plus a `validate()` requirement with a default implementation — and keep their `let` fields, their computed `orderId` / `orderValue` / `itemCount` and their `static` factories unchanged. `RelevaClient.push` (the completion-handler form, the private `incrementViews:` form and the `async` form) takes `any PushRequestConvertible` instead of `PushRequest`, so every `push` call site in `Sources` and every one documented in the README compiles unchanged — including one holding the request as the protocol type itself, such as a request queue or a `-> PushRequest` factory, which a generic `<Request: PushRequestConvertible>` parameter would have rejected outright, since Swift existentials don't self-conform. Converting at the call site instead — `push(request.pushRequest)` — was rejected for pushing that noise into every caller, consumers' included. `validate()` is a protocol *requirement* rather than only an extension member so that `SearchRequest`'s empty-query check and `CheckoutSuccessRequest`'s paid-cart check are still reached when the caller holds a `PushRequestConvertible`, which is the dynamic dispatch their `override` used to provide. Getting to `Sendable` also meant declaring it on everything the four hold: `Cart`, `CartProduct`, `ViewedProduct`, `CustomEvent`, `CustomEventProduct`, `CustomFields`, `CustomField` (conditionally, `where T: Sendable`, rather than constraining the generic parameter and changing its public signature), and the `AbstractFilter` protocol along with `FilterOperator`, `FilterAction` and `NestedFilterOperation` — a stored `AbstractFilter?` is only `Sendable` if the protocol refines it, and implicit inference does not apply to `public` types. Two dead branches went with the rewrite: `validate()` threw on an empty `events` array, which `customEvents([])` can never leave behind, and it contained an `if request["product"] != nil { }` with an empty body. Swift 6 language mode is **not** enabled by this change, and no measurement of its effect on strict-concurrency diagnostics is claimed. `PrivacyInfo.xcprivacy` is unchanged, because it describes the data transmitted and the payload is byte-identical.
- **`PushRequestTests` goes from 26 cases to 27 and keeps every assertion that still has a subject.** Two cases called a builder as a bare statement and now keep the returned copy — one binds the cleared request, the other folds the two calls into the chain it was already testing; the payload they assert on is unchanged. The one case that could not survive is `testBuildersReturnTheSameInstanceSoChainingAndStatementsAgree`, whose whole point was `XCTAssertTrue(returned === request)` — reference identity is not something a struct has, and the statement-style half of it is now a compile error rather than a behaviour to pin. It is replaced by two cases covering what value semantics promise in its place: a builder leaves its receiver untouched, and two chains branching off the same request do not see each other's page keys. `PushPayloadIdentityTests` needed no change at all, since it works on the raw dictionaries at the `NetworkService.buildPushPayload` seam, which is the strongest available statement that the wire format did not move.
- **BREAKING: `DesignRenderer`'s parsing helpers take `JSONValue?` rather than `Any?`.** `parseColor` is the one whose shape changed rather than just its parameter type: it is now `parseColor(_ value: JSONValue?)` for a value out of a design, plus `parseColor(css: String?)` for the colours that arrive already typed as `String` (story progress indicators, NPS appearance). Two overloads with the same argument label would make the pinned `parseColor(nil)` case ambiguous, so the string form takes an argument label instead. The 39 existing `DesignRendererParsingTests` are unchanged apart from dropping `as [String: Any]` coercions that no longer typecheck; none of their assertions were weakened.

### Fixed

- **`RecommenderResponse.meta` and `ProductRecommendation.custom` / `.data` were unconditionally discarded.** Their `init(from:)` assigned `nil` with a comment saying `[String: Any]` cannot be decoded by `Codable`, and `encode(to:)` skipped them with a matching note, so a caller reading a recommender's `meta` or a product's `custom` fields always got `nil` no matter what the API sent. They now decode and re-encode as `JSONValue`. Each field decodes with `try?`, not `try`, so a value of the wrong shape (`"meta": []` from a backend that serialises an empty map as an empty array, for instance) degrades to `nil` for that field rather than failing the whole `RelevaResponse` — matching the tolerance `RelevaResponse.decodeObjects` already applies to `banners`/`stories`/`nps`, and matching this field's own behaviour before this release.
- **`JSONValue(any:)` silently nulled two edge cases.** An already-typed `[String: JSONValue]` (or any `JSONValue`) passed to the public `init(any:)` matched `Any` and fell through to the "unrecognised → `.null`" default, nulling every leaf instead of passing the value through; a `JSONValue` short-circuit case now catches it first. Separately, `anyValue` mapped a non-finite `.double` (`.nan`/`.infinity`) straight to `NSNumber`, which fails `JSONSerialization.isValidJSONObject` — reachable only via a hand-built literal, not decoding, but `InboxService` serializes this output with `try?`, so it would have raised an uncatchable Objective-C exception rather than a Swift error; non-finite doubles now map to `NSNull`.

### Added

- `JSONValueTests`, covering the number fidelity that motivated the separate `int` case (a decode→encode round-trip is byte-compared against the original text, including the case where a whole-number `Double` in the source normalizes to `.int` and loses its `.0`), the accessors returning `nil` for a mismatched case rather than coercing, the subscripts returning `nil` rather than trapping on a type or index mismatch, the `JSONSerialization` bridge in both directions — including that a JSON boolean does not come back as the number 1, that a `JSONValue` passed into `init(any:)` by mistake passes through unchanged instead of being nulled, and that a non-finite `.double` becomes `NSNull` in `anyValue` so the bridge output always passes `isValidJSONObject`, which is what `InboxService` relies on when it persists inbox state.
- A `RelevaResponseTests` case pinning that plain `JSONDecoder` decoding now sees banners, stories and NPS, which is the regression guard on the hole described above.
- `RecommenderResponseTests` coverage that `meta` / `custom` / `data` survive a decode and a re-encode, replacing the three tests that pinned the old drop-on-decode behaviour, plus two cases pinning that a non-object `meta`/`custom`/`data` decodes to `nil` rather than throwing.
- A `RelevaResponseTests` case pinning the same tolerance one level up: a wrong-shape recommender `meta` degrades to `nil` for that field alone, and banners and NPS in the same envelope still decode — the failure mode the `try?` change actually guards against, not just the field-level effect.
- `TrackingRequestConversionTests`, twelve cases over `ScreenViewRequest`, `SearchRequest` and `CheckoutSuccessRequest`, which had no tests of their own before this release despite being what three of the five `track*` methods construct, plus the cart and wishlist auto-syncs. Moving their `init` side effects into a computed `pushRequest` is the part of this change with no existing guard, so the suite pins what each puts under `page` — including `SearchRequest`'s `filter` and `blocks` branches and the empty-array (as opposed to `nil`) `productIds` branch, which convert through the same `!isEmpty` guard as the `nil` case but are a different branch — that an all-nil `ScreenViewRequest` — the shape `RelevaClient` uses to sync a cart change without inflating the view counter — still converts to an empty page and sets no cart of its own, that a `CheckoutSuccessRequest` leaves its cart on the request for the context builder rather than in the payload, that a search with no results omits `ids` instead of sending an empty array, that `SearchRequest`'s and `CheckoutSuccessRequest`'s own `validate()` rules are still reached through a `PushRequestConvertible` rather than being shadowed by the protocol's default implementation, and that `RelevaClient.push` itself actually accepts all four concrete types held together as `any PushRequestConvertible` in one array — the case that exercises `push`'s existential parameter rather than only the types that satisfy it.

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
