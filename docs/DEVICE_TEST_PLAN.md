# Releva Swift SDK 5.0.0 — device test plan

Manual verification of `sdk-swift` on a real iPhone using the `example-swift` harness app before the client handover. The app's own quality is out of scope; it exists to trigger SDK behaviour.

**162 scenarios**: 57 × P0 (must pass before handover), 81 × P1 (should pass), 24 × P2 (nice to have or documented limitation). Each row names the SDK version the behaviour landed in, so the 1.0.x rows are a regression pass and everything from 1.0.3 onward is the untested surface.

**Status after 29 run(s)**: 77 pass, 2 fail, 17 pass with caveat, 66 not yet run. Details per row in the Result column and in section 5.

## 1. What was and was not tested before

| Author | Period | Versions | Device-tested |
|---|---|---|---|
| Georgi Keranov | Oct 2025 – Jan 2026 | 1.0.0 – 1.0.2: core tracking, cart/wishlist, push token, rich push extension, engagement callbacks | Yes |
| Yavor Stoychev, Stancho Yordanov | Mar 2026 | 1.0.3 – 1.2.0: push click fix, banners, stories, NPS, inbox, endpoint override, lifecycle sessions | No |
| Yavor Stoychev | Jul – Aug 2026 | 2.0.0 – 5.0.0: profileId-only identity, SPM-only + Firebase 12, privacy manifest, typed models, Sendable requests, SwiftLint, UIKit presenters, async/await API | No (CHANGELOG: written with no Mac or simulator) |

## 2. Prerequisites and fixtures

- iPhone on iOS 16+ (iOS 15 device optional for UIK-10), Xcode 26.x, the app in the **Debug** configuration. SDK logs exist only in Debug (`RelevaConfig.debug()` under `#if DEBUG`).
- `ShoppingAppSwift/GoogleService-Info.plist` for Firebase project `releva-248016`, bundle `com.releva.ShoppingAppSwift`. APNs auth key uploaded to that Firebase project. The app entitlement is `aps-environment = development`, so pushes go through **sandbox APNs**; the domain's Firebase account in the admin must be able to reach this app.
- A test domain in the Releva admin (EU realm) with: its **Access Token** (Settings → General; not the Secret Key); a Page whose token is `5ebbee0e-854a-4620-b654-bad4ca46bda6` (the only screen token the app sends); a real push campaign (test pushes write no stats); Firebase credentials configured for the domain.
- Fixtures to create before section J–M: one banner block per displayType (popup, bar top, bar bottom, flyout left, flyout right, static ×4 strategies with cssSelector `#home-content`) and per trigger (immediately, delaySeconds, scrollPercentage, cartChanged, wishlistChanged); one `showAlways` banner; three stories (endBehavior dismiss / loop / stayOnLast) with 3 slides each; NPS surveys as described in section L; an inbox campaign (`platforms: [ios, appInbox]`) and an inbox-only one (`[appInbox]`). All fixtures `running`/`active`: the SDK never sends `mode: debug`, so nothing switched off will be returned.
- Backend access: admin profile timeline (fastest), ClickHouse and Postgres for the queries in Appendix D.
- Tools on the Mac: Xcode console for `RelevaSDK:` lines; Console.app filtered by process `NotificationExtension` for the extension; optionally Proxyman/Charles to see the raw requests.

## 3. Read before testing

### Harness facts

- Credentials are entered at runtime in **Settings** (access token, realm, endpoint override, profile ID). The SDK is off until token and profile ID are set; Save & Apply re-initialises without relaunch.
- Only Home sends a page token. Cart, Checkout and Success send `screenToken: nil`, so the backend writes **no pageView** for them (TRK-02).
- Banners are hosted on Home only (selector `#home-content`). Stories and NPS are attached app-wide.
- Deep links must be `myapp://consumer.app/{home|cart|checkout|product/<id>|inbox|inbox/<id>}`. The scheme is **not** registered in the shipping Info.plist, so Safari links never open the app; only push-driven navigation works.
- Product IDs you will see in the backend are `1`–`4` (sample products) unless Firestore holds other data.

### SDK features the app never calls (rows marked with a snippet id need Appendix A temp code)

`trackSearchView`, `setProfileId(_, false)` (merge), the `PushRequest` builder (`locale`, `currency`, `pageProductIds`, `pageCategories`, filters), `RelevaResponse.recommenders`, `trackEvent(_:)` (NPS custom trigger), `setAppVersion`, `pushTokenProvider`/`refreshPushToken`, `RelevaConfig.trackingOnly/pushOnly/minimal`, `BannerPresenter`, `NpsPresenter`, `StoryViewerView`, `EngagementTrackingService.getStatistics/flush`, `getDeviceId/getProfileId/getCart/getWishlist`.

### Harness bugs that produce false SDK failures

1. **Double banner init**: `AppState.swift:332` re-initialises banners the SDK already initialised. Could produce duplicate impressions; did not reproduce in run 1 (one impression per banner). Keep counting `Banner impression tracked` lines per token.
2. **`trackEngagement(.opened)` on every remote delivery**, including silent pushes (`ShoppingAppSwiftApp.swift:248`) → spurious callback GETs.
3. **Two permission prompts** can race (app and SDK both request).
4. **Checkout is fire-and-forget right before navigation**; a dropped purchase on fast backgrounding is app timing.
5. ~~`FirebaseAppDelegateProxyEnabled=false` was in an orphaned plist~~ fixed on 2026-09-02: the key now lives in the shipping Info.plist.
6. **Inbox list crashes** when a message preview contains HTML: `InboxView.stripHtml` runs `NSAttributedString(.html)` inside a view update (run 4, SIGABRT). Use the regex fallback.
7. ~~Checkout deep link blank screen~~ fixed 2026-09-03 (deferred path push).
8. **NavigationPath crash** when an inbox push arrives on top of a pushed screen (run 6): mixing `navigationDestination(isPresented:)` with path pushes. Fixed 2026-09-03 by moving Inbox/Settings/checkout/product to one path-based `AppRoute` enum.

### SDK ⇄ backend mismatches found while writing this plan

1. **Engagement events** (PUSH-03, PUSH-06): the SDK fires delivered, opened and clicked to the same `callbackUrl`, the backend records every hit as `pushNotificationClick`; a foreground delivery counts as a click. The GET carries the default CFNetwork user agent (no `User-Agent` set in `NetworkService.fireEngagementCallback`), and `click-tracker.js:66` drops UA `unknown`, so clicks may not be recorded at all.
2. **Test pushes never record clicks** (`campaign = {}` → no campaignId). Stats rows need a real campaign.
3. **Token-less screen views write no pageView** (TRK-02). Expected, but the client integration guide must say so.
4. **Story stats** (STO-08): SDK sends `storyId = token`; admin stats aggregate on numeric `story.id`.
5. **NPS opens** (NPS-11): backend counts `npsOpen`; SDK never sends it.
6. **Action button** (PUSH-05): resolved in run 3, the extension-registered `RELEVA_DYNAMIC` category renders the button and yields `.clicked`.
7. **Bot filter** (SET-04): resolved in run 1, the backend parses `RelevaSDK-iOS/5.0.0` as a browser, not a bot.
8. **Firebase proxy vs SwiftUI** (TOK-02): with `FirebaseAppDelegateProxyEnabled` left at its default, Firebase's swizzling under `@UIApplicationDelegateAdaptor` swallowed the APNs token callback and push never registered. Setting it to `NO` in the shipping Info.plist fixed it. The SDK README must state this for SwiftUI integrators.

### Recording results

Mark each row ☐ → ✅ / ❌ / ⚠️ (works with a caveat) and write the caveat in the last column. Attach the `Request body:` log line for any ❌. The companion web page keeps the same rows with checkboxes and notes.

## 4. Scenarios

### A. Setup and configuration

Everything here must pass before any other section is meaningful. SET-04 is the single most important row in the document.

| ID | Prio | Since | Scenario | Precondition | Steps | Expect on device / in log | Expect in backend | Result |
|---|---|---|---|---|---|---|---|---|
| SET-01 | P0 | 3.0 / 5.0 | Clean build and run on device | Fresh clone of example-swift, GoogleService-Info.plist in ShoppingAppSwift/, iPhone connected, Debug scheme. | Open ShoppingAppSwift.xcodeproj, let SPM resolve, build and run scheme ShoppingAppSwift on the iPhone. Also build scheme NotificationExtension. | Package.resolved shows sdk-swift 5.0.0 and firebase-ios-sdk 12.x. Both targets compile with no errors. App launches. | — | ✅ Run 1: app + extension built and ran on the iPhone with sdk-swift 5.0.0 / Firebase 12.18.0. |
| SET-02 | P0 | 1.0 | SDK stays off without credentials | Fresh install or Settings fields cleared. | Settings → clear Access Token → Save & Apply. | Alert says SDK disabled. No `RelevaSDK: Initialized` log. No `Sending POST request` lines while browsing. | No new profile appears in admin. | ✅ Run 1: 'Releva SDK not initialized' at launch, no SDK requests until Settings were saved. |
| SET-03 | P0 | 1.0 | Enable via Settings without relaunch | Valid access token for the test domain (dashboard → Settings → General). Realm empty for the EU deployment. | Settings → enter Access Token and a fresh Profile ID (e.g. `ios-qa-YYYYMMDD`) → Save & Apply → go to Home. | Logs: `RelevaSDK: Initialized with realm ''`, `Device ID set to '<uuid>' (changed: true)`, `Profile ID set to '…' (first time, no merge needed)`, `Push engagement tracking enabled`. Then `Sending POST request to https://releva.ai/api/v0/push` and `Response status code: 200`. | Admin → Profiles: search the profile ID; it exists within ~1 min. | ✅ Run 1: Initialized with realm '', profile rado-ios-spark-0209202614, Push engagement tracking enabled, /push 200 after the domain was enabled. |
| SET-04 | P0 | 1.0 | Backend accepts the SDK user agent (bot filter)<br>_Blocking for the whole plan._ | SET-03 passed. | Open Home once. Wait 1 min. | `Response status code: 200` for the push request. | Admin profile timeline (`GET …/profiles/events?id=`) shows a `pageView` with pageToken 5ebbee0e-854a-4620-b654-bad4ca46bda6. If the response is 200 but NO event appears, the backend UA parser is treating `RelevaSDK-iOS/5.0.0` as a bot and every event is dropped (`event-dispatcher.js:117`). Stop and escalate; nothing else can be verified until fixed. | ✅ Run 1: pageView present in the timeline; backend parsed the UA as browser 'RelevaSDK-iOS', platform 'unknown', tags Mobile/iPhone. Not a bot. |
| SET-05 | P0 | 1.0 | Wrong access token is reported, not crashed<br>_The domain Secret Key produces the same 400. Do not confuse the two._ | SDK enabled. | Settings → replace Access Token with a random UUID → Save → open Home. | `Response status code: 400`; error contains `Domain with the provided access token cannot be found.` (SDK surfaces it as `serverError(400, …)`). App keeps working. | Nothing written. | ✅ Run 14: token changed to an invalid one in Settings → POST /push returns 400 {"message":"The access token you provided is invalid."}; SDK surfaces serverError(400, body) without retrying, app keeps running; valid token restored and tracking resumed. |
| SET-06 | P0 | 3.0 | Wrong realm host | Valid EU token. | Settings → Realm `asia-southeast2` → Save → Home. Then clear realm → Save. | With wrong realm: `Sending POST request to https://asia-southeast2.releva.ai/api/v0/push` then 400 with the same 'cannot be found' message. After clearing: back to `https://releva.ai` and 200. | Nothing written for the wrong realm. | ✅ Run 14: realm set to 'us' → requests go to https://us.releva.ai, DNS fails, SDK retries 3 times about a second apart, then reports networkError("A server with the specified hostname could not be found."). No crash; realm '' restored and tracking resumed. Note: an unknown realm host fails at DNS, so the backend's 400 'Domain … cannot be found' only appears with a valid host and wrong token (SET-05). |
| SET-07 | P1 | 1.1 | Endpoint override precedence | A reachable HTTPS endpoint you control (ngrok to a local magellan-api or a request-bin). | Settings → API Endpoint Override `https://<host>` → Save → Home. Then clear it → Save → Home. | `Endpoint override set to 'https://<host>'`; requests go to `https://<host>/api/v0/push`. After clearing: `Endpoint override cleared` and requests return to the realm URL. | Your endpoint receives the POST with `Authorization: Bearer <token>`, `User-Agent: RelevaSDK-iOS/5.0.0`, `X-Platform: iOS`. | ☐ |
| SET-08 | P1 | 1.0 | Release build tracks with logging off | Scheme edited to Release configuration. | Run Release build → Home. | No `RelevaSDK:` log lines at all. | A new `pageView` still lands in the profile timeline. | ☐ |
| SET-09 | P2 | 1.0 | Config presets (temp code S1) | Snippet S1 pasted into a Debug-only button. | Re-create the client with `.trackingOnly()`, then `.pushOnly()`, then `.minimal()` and repeat SET-03 actions. | `.trackingOnly()`: track* work, `registerPushToken` is a silent no-op (no `/appPush/tokens` request). `.pushOnly()`: track* return `RelevaResponse.empty()` with no network. `.minimal()`: same as pushOnly plus no banners/stories/NPS. | Only trackingOnly writes events. | ☐ |
| SET-10 | P2 | 1.0 | Invalid config values are accepted silently<br>_Document as known behaviour for the client, not a device bug._ | S1 variant with `requestTimeoutInterval: 0`. | Create client with timeout 0, open Home. | Requests fail with timeouts; no validation error is raised because `RelevaConfig.validate()` is never called by `RelevaClient.init`. | — | ☐ |

### B. Identity and sessions

Identity fields go under `context.profile.id`, `context.deviceId`, `context.mergeProfileIds`; sessions come from `SessionService` (30-minute background debounce).

| ID | Prio | Since | Scenario | Precondition | Steps | Expect on device / in log | Expect in backend | Result |
|---|---|---|---|---|---|---|---|---|
| ID-01 | P0 | 1.0 | Device ID persists across restarts | SDK enabled, app has run once. | Kill the app, relaunch, open Home. Inspect the request body log. | `Device ID set to '<same uuid>' (changed: false)`. Body has `deviceIdChanged: false`. | ClickHouse `devices FINAL` has exactly one row for this deviceId. | ✅ Run 1: 'Device ID set to BB7A5E46-… (changed: false)' on reinit; deviceIdChanged false in every body. |
| ID-02 | P0 | 1.0 | Fresh install sends deviceIdChanged: true | Delete the app (wipes UserDefaults) and reinstall. | Configure Settings, open Home. | Body has a NEW `deviceId` and `deviceIdChanged: true`. | New `devices` row; profile row is written (profile write only happens when `deviceIdChanged` or `profileChanged` is true). | ✅ Run 2: after reinstall a new deviceId BD2EA943-… replaced BB7A5E46-…, firstSeenAt reset to 11:17:06Z, sessions restarted at 1. First-launch body not captured; changed:false seen on launch 3. |
| ID-03 | P0 | 1.0.1 | Profile change without merge (the app's path, logout semantics) | Profile A active. | Settings → Profile ID `B` → Save → Home. | `Profile ID changed to 'B' (skip merge = true)`. Body: `profile.id: B`, `profileChanged: true`, no `mergeProfileIds`. | Profiles A and B both exist as separate profiles; A's events stay on A. | ✅ Run 1: 'Profile ID changed … (skip merge = true)', no mergeProfileIds sent (logout semantics). Run 18: the previous user's cart/wishlist stayed in the SDK context because the harness never reloaded the new user's data; fixed in the harness. Run 19: switch 0609→0209 → 'switched to user …0209: cart 0, likes 1' → setCart([]) (cartChanged true) and setWishlist([prod_005]) (wishlistChanged true) synced; switch back → cart [prod_005 ×2] and wishlist [prod_002, prod_005] restored for 0609; token re-bound each time. README: after login/logout the app must hand the SDK the new user's cart and wishlist. |
| ID-04 | P0 | 1.0.1 | Profile change WITH merge (temp code S2) | Profile B active with some events. Snippet S2. | Call `setProfileId("C", false)` then open Home. Open Home again. | `Profile ID changed from 'B' to 'C' (merge enabled)` and `Merge profile IDs stored: ["B"]`. First body: `mergeProfileIds: ["B"]`, `profileChanged: true`. Second body: no `mergeProfileIds` (cleared after success). | `profile-repository.js:1354`: B is unknown to Postgres (anonymous) so `mergeProfiles` runs. Within a few minutes: `profiles FINAL` has C only (B tombstoned), `profile_identity_map` maps B→C, B's pageViews appear on C's admin timeline. | ☐ |
| ID-05 | P1 | 1.0.1 | Merge IDs survive a failed push | S2 available. | Airplane mode ON → `setProfileId("D", false)` → open Home (fails) → airplane OFF → open Home. | First push logs retries then `networkError`; `rlv_merge_profile_ids` is kept; the next successful body still carries `mergeProfileIds: ["C"]`. | Merge C→D happens on the later request. | ☐ |
| ID-06 | P0 | 1.2 | Session ID is stable within a run and new after cold start | SDK enabled. | Home → Cart → Home (compare `sessionId` in the three bodies). Kill and relaunch, open Home. | Same `sessionId` (lowercase UUID) in one run; different one after relaunch; `device.sessions` increments by 1. | Events in the timeline share the sessionId; banner `sessionInterval` and NPS `sessionCount` use `device.sessions`. | ✅ Run 1: sessionId stable across ~30 requests. Run 2: cold start gave a new sessionId 4a42b0e0-… and device.sessions 3. |
| ID-07 | P1 | 1.2 | Background debounce: <30 min keeps the session, >30 min starts one<br>_The debounce threshold is internal; there is no way to shorten it from the app, so this row needs the real wait._ | SDK enabled. | Background the app for 2 min → foreground → Home. Then background 31+ min → foreground → Home. | After 2 min: same `sessionId`, same `device.sessions`. After 31 min: new `sessionId`, `sessions` +1. | — | ☐ |
| ID-08 | P1 | 1.2 | firstSeenAt is set once and never changes | Fresh install from ID-02. | Inspect `device.firstSeenAt` on the first push, then on a push after a relaunch the next day. | ISO-8601 timestamp, identical on every request. | Used by NPS `minDaysSinceFirstContact` gating. | ⚠️ Run 1: firstSeenAt 2026-09-02T10:52:32Z identical on every request. Next-day check pending. |
| ID-09 | P1 | 1.2 | views increments only on real screen/product views | SDK enabled, cart has one item. | Home (views=n) → Product 1 (n+1) → Add to cart (auto-sync body) → Home (n+2). | The cart auto-sync body carries `device.views` unchanged (n+1). Screen and product views increment it. | Backend accepts and discards `views` and `sdkVersion`; informational only. | ✅ Runs 7–12 (log review): device.views increments by one per screen-view POST (e.g. 176→177→178→179) and nothing else: cart/wishlist syncs with changed:false send no request, token registration and engagement callbacks leave it untouched. |
| ID-10 | P2 | 1.1 | setAppVersion appears as device.version (temp code S3) | S3. | Call `setAppVersion("1.2.3")`, open Home. | Body `device.version: "1.2.3"`. | Used by NPS `appVersionMin/Max` (see NPS-07). | ☐ |
| ID-11 | P2 | 2.0 | No contact details ever leave the device | Checkout form filled with name/email/phone. | Complete a checkout, inspect every `Request body:` line of the session. | No `email`, `phoneNumber`, `firstName`, `lastName` anywhere; identity is `profile.id` only. | Privacy manifest declares no contact-info collection; this row is the proof. | ✅ Run 1: no email/phone/name in any request body, including checkout. |

### C. Screen, product, search and custom events

All of these are `POST /api/v0/push`. The schema is `$$strict`: an unknown key anywhere in `context` is a 400, so a 400 in this section is an SDK bug.

| ID | Prio | Since | Scenario | Precondition | Steps | Expect on device / in log | Expect in backend | Result |
|---|---|---|---|---|---|---|---|---|
| TRK-01 | P0 | 1.0 | Home screen view with a page token | Page with token 5ebbee0e-854a-4620-b654-bad4ca46bda6 exists in the admin. | Open Home. | Body `page.token: 5ebbee0e-854a-4620-b654-bad4ca46bda6`, 200. | Timeline: `pageView` with that pageToken. | ✅ Run 1: page.token sent; 'Viewed Page · Homepage' in timeline. |
| TRK-02 | P0 | 1.0 | Screen view with nil token writes no pageView<br>_Client guide must say: every screen needs a Page token or a `pageUrl` matching a Page pathname._ | SDK enabled. | Open Cart tab, then Checkout. | Bodies have no `page.token` and no `page.url`; 200; `device.views` increments. | NO `pageView` event is written (`event-dispatcher` requires a resolved Page). Expected behaviour, not a bug. | ✅ Run 1: Cart/Checkout views sent with empty page, 200, and no Viewed Page event was written. Behaves as documented. |
| TRK-03 | P0 | 1.0 | Product view with custom fields | SDK enabled. | Home → tap product 1. | Body `product.id: "1"`, `product.custom.string.category/description`, `product.custom.numeric.rating/mrp/discount`. | Timeline: `productView` with `products[0].id = 1`. | ✅ Run 1: 'Viewed Product' for prod_002 with category/description/rating/mrp/discount. Shown as 'Product: unknown' because prod_002 is not in the domain feed. |
| TRK-04 | P0 | 1.0 | Custom event with product and custom field | Product detail open. | Tap a colour swatch. | Body `events: [{action: "selectedColor", products: [{id}], custom: {string: {color: ["…"]}}}]`. | Timeline: event with action `selectedColor`. | ✅ Run 1: 'Custom Event: selectedColor' with custom.string.color and products[prod_002]; backend attached bannerBlockId/bannerId/segmentId attribution from the earlier banner click. |
| TRK-05 | P0 | 1.0 | Search view (temp code S4) | S4. | Call `trackSearchView(query: "shoes", resultProductIds: ["2"], screenToken: HOME)`. | Body `page.query: "shoes"`, `page.ids: ["2"]`, `page.token`. 200. | Timeline: `pageView` carrying the query (search analytics). | ✅ Harness had no trigger; run 15 rebuild added Return in the Home search field. Run 16: 'Nike' → POST /push with page {token Home, query "Nike", ids [prod_001]} → 200 'Tracked search view - query: Nike, results: 1'; 'Did' → ids [prod_002]. Check the profile timeline for the search event. |
| TRK-06 | P1 | 1.0 | Empty search query is rejected before the network | S4. | Call `trackSearchView(query: "")`. | Throws `missingRequiredField`; no `Sending POST request` line. | — | ☐ |
| TRK-07 | P1 | 1.0 | Search with a filter | S4 variant with `SimpleFilter.priceRange(minPrice: 10, maxPrice: 100)`. | Call trackSearchView with `filter:`. | Body `page.filter` is a JSON object; 200. | 200 proves the filter shape passes the strict schema. | ☐ |
| TRK-08 | P1 | 1.0 / 4.0 | Full PushRequest builder (temp code S5) | S5. | Push a request with `locale`, `currency`, `pageCategories`, `pageProductIds`, `pageBlocks(tags:)`, `NestedFilter.and(...)`. | All keys present under `page`; 200. | A 400 here names the unknown key in its message; report it as an SDK wire-format bug. | ☐ |
| TRK-09 | P1 | 1.0 / 4.0 | Response models decode (recommenders, meta, custom) | A recommender configured on the Home page. Temp code S6 to log the response. | Open Home via S6. | Log shows `recommenderCount > 0`, `allProducts.count > 0`, `recommenders[0].meta != nil` (4.0 fix), `banners.count`, `stories.count`, `nps` presence. No `Failed to decode response`. | Recommender impressions are NOT sent by the SDK; nothing to verify server-side. | ☐ |
| TRK-10 | P2 | 2.0 | Response userId is not adopted | Profile ID set in Settings. | Open Home twice. | The second body still sends the Settings profile ID, not the canonical `userId` the response returned. | Documented decision (CHANGELOG 2.0.0). | ☐ |

### D. Cart and wishlist

`setCart`/`setWishlist` persist locally and, after the first-ever set, send an empty ScreenViewRequest with the cart/wishlist in `context`.

| ID | Prio | Since | Scenario | Precondition | Steps | Expect on device / in log | Expect in backend | Result |
|---|---|---|---|---|---|---|---|---|
| CART-01 | P0 | 1.0 | First-ever cart set on a fresh install does not auto-sync | Fresh install (ID-02). | Product 1 → Add to Cart. | `Cart updated with 1 products (changed: true)` but NO `Cart changes synced to backend` (first set is suppressed by `rlv_cart_initialized`). | The cart reaches the backend with the NEXT screen view: that body has `cart.products` and `cartChanged: true`; timeline shows `cartCreate`/`cartAdd`. | ✅ Run 1: first setCart after install logged 'changed: true' with no auto-sync; the cart then rode on the next screen view (cartChanged true) → Cart Created / Cart Item Added / Cart Updated. |
| CART-02 | P0 | 1.0 | Second add auto-syncs | Cart already has one item. | Product 2 → Add to Cart. | `Cart changes synced to backend`. Body: `cart.products[{id, price, quantity, custom.string.size/color}]`, `cartChanged: true`, empty `page`, `device.views` unchanged. | Timeline: `cartAdd` for product 2. | ✅ Run 6: second-ever add (prod_001) → 'Cart changes synced to backend' with cart.products[price 129.99, qty 1, size/color custom], cartChanged true, empty page. |
| CART-03 | P0 | 1.0 | Quantity change, remove, clear | Cart with two items. | Cart → + on item 1 → trash on item 2 → Clear. | Three sync requests: quantity 2; one product; empty `products: []`. | Timeline: `cartUpdate`, `cartRemove`, then removes for the rest. Redis cart snapshot empty. | ✅ Run 16: add prod_002 (qty 1) → sync with cartChanged true; qty + → payload qty 2.0; add prod_003 → 2 products; remove prod_002 → 1 product; clear → empty products with cartChanged true. Each step one POST /push, size/color custom fields present. Check timeline for cartAdd / cartUpdate / cartRemove. |
| CART-04 | P0 | 1.0 | Cart survives restart and the first set after restart syncs | Cart with items. | Kill app, relaunch → badge shows count → add one more item. | Cart badge correct on launch. Add logs `Cart changes synced to backend` immediately (flag persisted, so no suppression this time). | `cartAdd` event. | ✅ Runs 6–7 (log review): after the order the SDK still held prod_001 as the active cart on the next cold launch, i.e. the cart survived the restart; the app's first setCart (empty) after the restart went out with cartChanged:true. Since then every launch logs 'Cart updated with 0 products (changed: false)' and sends nothing. |
| CART-05 | P0 | 5.0 | Two rapid setCart calls each send their own payload | Cart empty. | On Product 1 tap Add to Cart twice as fast as possible. | Two `Sending POST request` lines; the first body has quantity 1, the second quantity 2 (the payload is pinned at the call site; 5.0 `preparePush`). | Timeline: `cartAdd` then `cartUpdate`. | ✅ Run 18: five fast taps on Add to Cart → four POST /push with quantity 2, 3, 4, 5 (one tap produced an identical cart and was skipped as changed:false); responses arrived out of order and each payload kept its own quantity. Check the timeline for cartAdd + cartUpdate. |
| CART-06 | P0 | 1.0 | Wishlist add and remove | SDK enabled. | Home → heart on product 3 → heart again. | `Wishlist updated with 1 products (changed: true)`; body `wishlist.products[{id, custom}]`, `wishlistChanged: true`. Then products empty. | Timeline: `wishlistAdd`, then `wishlistRemove`. | ✅ Run 17: heart on prod_003, then prod_005 → each a POST /push with wishlistChanged true and the product fields → 200. Run 18: heart on prod_004 → 3 products; un-heart prod_004 → 2 products, wishlistChanged true → 200; un-heart prod_003 → 1 product → 200. Check the timeline for wishlistAdd / wishlistRemove. |
| CART-07 | P1 | 1.0 | Unchanged cart does not sync | Cart has items. | Open Cart, change nothing, navigate away and back. | No `Cart changes synced` line; screen-view bodies carry `cartChanged: false`. | No cart events. | ✅ Runs 7–12 (log review): setCart/setWishlist with an unchanged cart log changed:false and send no POST /push. |
| CART-08 | P1 | 1.0 | Checkout does not sync the emptied cart | Cart with items. | Place Order. | Only the checkout request is sent; the local cart is cleared but no empty-cart sync follows (app design, `AppState.swift:483`). | Backend cart snapshot is replaced by the paid cart; no `cartRemove` events. | ⚠️ Runs 17–18: after Place Order only the checkout request went out (cartPaid true) and no empty-cart sync followed, as designed in the harness. Side effect to decide with the CTO: the SDK keeps the ordered products as its stored cart, so every later screen view (run 17 08:14:26) and the first screen views of the next launch sent the paid products as an active cart with cartPaid false, until the app's first setCart replaced it (then 'Cart updated with 0 products (changed: true)' → a cartRemove at launch). Either the SDK clears its cart after a successful checkout push, or the README tells apps to call setCart([]) right after trackCheckoutSuccess. |
| CART-09 | P2 | 1.0 | Cart totals helpers | S5 scratch. | Build a `Cart` with two products and log `itemCount`, `totalQuantity`, `totalPrice`. | Values correct. | — | ☐ |

### E. Checkout

`trackCheckoutSuccess` sends the paid cart in `context.cart` with `cartPaid: true` and `orderId`.

| ID | Prio | Since | Scenario | Precondition | Steps | Expect on device / in log | Expect in backend | Result |
|---|---|---|---|---|---|---|---|---|
| CHK-01 | P0 | 1.0 | Place order | Cart with two items, checkout form filled. | Place Order. | Body `cart.cartPaid: true`, `cart.orderId: <uuid>`, products with price and quantity, `cartChanged: true`. 200. Success screen shown. | Timeline shows the purchase (paid cart) with the orderId; revenue appears in the domain dashboard. | ✅ Run 1: order 732B9E0D-…; Run 6: order 592C6D15-… with cartPaid true, orderId, product prod_001 → 200. Run 17: order 469E5176-… with two products (prod_003 qty 1, prod_005 qty 3, colours) → cartPaid true → 200 'Tracked checkout success'. |
| CHK-02 | P0 | 2.0 | No profile attributes on checkout | As CHK-01. | Inspect the checkout request body. | No email/name/phone keys anywhere. | — | ✅ Run 1: checkout body has no profile attributes. |
| CHK-03 | P1 | 1.0 | Checkout validation (temp code S7) | S7. | Push `CheckoutSuccessRequest` with an empty product list, then with `Cart.active(...)` (unpaid). | Both throw `missingRequiredField` before any request. | — | ☐ |
| CHK-04 | P1 | 1.0 | Order placed then app backgrounded immediately | Cart with items. | Tap Place Order and swipe to the home screen within a second. | `Sending POST request` appears; response may or may not arrive. Reopen: no crash. | If the purchase is missing this is app timing (fire-and-forget before navigation), not an SDK fault. | ☐ |

### F. Push token registration

The SDK never touches the APNs token. The app forwards the FCM token to `registerPushToken`, which posts to `/api/v0/appPush/tokens`.

| ID | Prio | Since | Scenario | Precondition | Steps | Expect on device / in log | Expect in backend | Result |
|---|---|---|---|---|---|---|---|---|
| TOK-01 | P0 | 1.0 | Permission prompt | Fresh install. | Launch, configure Settings. | System notification prompt appears; accept. A second prompt may appear (app and SDK both request; harness issue). | — | ✅ Run 1: permission granted. |
| TOK-02 | P0 | 1.0 | FCM token registered | Permission granted, SDK enabled. | Launch or Save in Settings. | Logs: app prints APNs token; `Registering push token for ios...`; `Sending POST request to …/api/v0/appPush/tokens` with `{pushToken, deviceType: "ios", deviceId, profileId}`; `Response status code: 202`; `✓ Successfully registered push token for ios`. | CH `device_app_push_tokens FINAL`: row with platform `ios`, this deviceId/profileId. Timeline: `pushNotificationSubscribe` with tag `device_ios`. Dashboard push-subscriber count +1. | ✅ Run 3 (after setting FirebaseAppDelegateProxyEnabled=NO in the shipping Info.plist): 'APNS Device Token received' → FCM token → POST /appPush/tokens {pushToken, deviceType ios, deviceId, profileId} → 202 → 'Successfully registered push token for ios'. Runs 1–2 failed only because Firebase's app-delegate proxy swallowed the APNs callback under SwiftUI's UIApplicationDelegateAdaptor; not a network issue after all. |
| TOK-03 | P0 | 1.0 | Token re-registered after profile change | TOK-02 passed. | Settings → new Profile ID → Save. | A new `/appPush/tokens` POST with the new profileId. | New row in `device_app_push_tokens FINAL` under the new profileId; the old one remains (append-only table). | ✅ Runs 14/16 failed for two harness reasons (AppDelegate cast nil under SwiftUI, no pushTokenProvider) and one SDK reason: the 24 h throttle compared only the token and the upload time, so the new profile never got the token. Fixed on the branch (the SDK remembers the profile of the last upload; setProfileId triggers a refresh when a provider is set). Run 18: switch to rado-ios-spark-0609202614 → 'refreshPushToken - profile changed since the last upload, re-registering' → POST /appPush/tokens with the new profileId → 202. |
| TOK-04 | P1 | 5.0 | 24-hour refresh throttle (temp code S8) | S8 sets `pushTokenProvider`; the app never does, so without S8 you only see `refreshPushToken skipped - pushTokenProvider not set`. | With S8: background and foreground the app twice. | `refreshPushToken - token unchanged and uploaded recently, skipping`. No new POST. | No new token row. | ⚠️ Not exercisable with this harness: the app calls registerPushToken itself on every launch (202 each time) and never sets pushTokenProvider, so the SDK's 24-hour refresh throttle ('refreshPushToken skipped - pushTokenProvider not set') never runs. Also harness-side: the first registration attempt on each launch fails with 'No APNS token specified' because the app asks Firebase before the APNs token arrives; the retry after the token succeeds. Both belong in the README as integration guidance. |
| TOK-05 | P1 | 1.0 | Rotated FCM token | TOK-02 passed. | Delete and reinstall the app, configure, launch. | New FCM token registered (new deviceId too, since UserDefaults were wiped). | New row. The old token row is tombstoned (`deleted=1`) only after a campaign send bounces on it. | ☐ |
| TOK-06 | P1 | 1.0 | registerPushToken before setDeviceId (temp code S9) | S9 creates a throwaway client. | Call `registerPushToken("x", deviceType: .ios)` without `setDeviceId`. | Throws `missingRequiredField`; log `ERROR - Cannot register push token without deviceId. Call setDeviceId() first.` | No request. | ☐ |
| TOK-07 | P1 | 1.0 | Permission denied | Fresh install. | Deny the prompt, configure Settings. | Observe whether an FCM token is still obtained and registered (FCM can mint a token without APNs authorisation). | If a row exists, pushes will be 'delivered' by FCM but never shown; document for the client. | ☐ |
| TOK-08 | P0 | 1.0 | Admin test push reaches the device<br>_Test pushes create the inbox delivery but write NO send/click events; use a real campaign for stats rows._ | TOK-02 passed. Admin access. | Admin → Push notifications → send test (`testPushNotification`, platform ios, sendTo = the profile ID). | Notification arrives on the device. | API 204. 400 means no token found for the profile (registration failed). 502 means Firebase credentials for the domain are rejected. | ✅ Run 3: admin test push (iOS content: subject, body, image URL, button 'Shop now'; target URL myapp://consumer.app/home) arrived on the device within seconds. |

### G. Push receipt and engagement tracking

The SDK owns `UNUserNotificationCenter.delegate` after `enablePushEngagementTracking()`. Engagement is reported by a plain GET to the payload's `callbackUrl`, which the backend records as a single event type `pushNotificationClick`.

| ID | Prio | Since | Scenario | Precondition | Steps | Expect on device / in log | Expect in backend | Result |
|---|---|---|---|---|---|---|---|---|
| PUSH-01 | P0 | 1.0 | Background delivery | App in background, real campaign or test push. | Send push. | Lock-screen/banner notification with the iOS title and body from the admin content. | Campaign stats: Sent 1, Delivered 1 (FCM accepted). Test pushes write nothing. | ✅ Run 3: image push on the Home screen. Run 7: plain QA-P9 push delivered in the background with title/body, badge 1, category REQUIRE_INTERACTION, no actions, no attachment (system log). |
| PUSH-02 | P0 | 1.0 | Foreground delivery is shown and tracked as delivered | App open on Home. | Send push. | Banner with sound shows while the app is open (SDK `willPresent` returns banner+sound+badge). Within 30 s: `Firing callback URL: https://tr-<domainId>.…/api/v0/click?i=…&p=…` and `Callback URL response: 200` (delivered events are batched, not immediate). | See PUSH-06: this GET is recorded as `pushNotificationClick` if recorded at all. | ✅ Run 3–8: willPresent fires for every Releva push in the foreground and tracks delivered; deliveries are batched ('Sending 2 engagement events' → two callback GETs, both 200). |
| PUSH-03 | P0 | 1.0.3 | Tap opens the app and reports opened<br>_Mismatch 1: the SDK sends the GET with the default CFNetwork user agent (no `User-Agent` set in `fireEngagementCallback`). `click-tracker.js:66` drops UA `unknown`. If the log says 200 but no event appears, this is the cause and must be fixed on one side before handover._ | Real campaign (not a test push), app in background. | Tap the notification. | App comes to foreground; immediately `Firing callback URL …` and `Callback URL response: 200`; navigation per target. | Timeline: `pushNotificationClick` with `products[0].campaignId`. Campaign stats Clicks +1. | ✅ Run 14, admin: campaign QA-C1 shows Sent 1, Delivered 1, Clicks 1 after the tap on the device. The backend accepts the SDK's callback GET (default URLSession User-Agent) and records pushNotificationClick. No SDK User-Agent change needed. |
| PUSH-04 | P0 | 1.0 | Cold launch from a push | App force-quit. | Send push, tap it. | App launches; after SDK init the callback fires; navigation happens. | `pushNotificationClick` recorded (subject to mismatch 1). | ✅ Runs 7, 9, 10, 11: cold launch from a notification tap bootstraps the process, registers the token (202) and fires the callback GET 200 within about half a second, every time; from run 11 the deep link is honoured too (DL-08). |
| PUSH-05 | P0 | 1.0 | Action button reports clicked<br>_Mismatch 6: whether the button renders at all is unverified._ | Push with `button` text configured (admin btnText). | Long-press / pull down the notification; tap the 'Open' action. | Action button is visible (category `RELEVA_DYNAMIC` from the extension); tap fires the callback with type clicked (`actionIdentifier == RELEVA_ACTION_BUTTON`). | Same `pushNotificationClick` event; backend cannot tell opened from clicked. | ✅ Run 3+4: action button visible and tap yields RELEVA_ACTION_BUTTON → clicked. Nit in run 4: the action label showed 'Shop now' although the payload button was 'Shop now [PUSH-05]'; the RELEVA_DYNAMIC category title from the first push appears to be reused. SDK should re-register the category with the new text. |
| PUSH-06 | P0 | 1.0 | Delivered is counted as a click (over-count) | PUSH-02 done with a real campaign. | Check the profile timeline after a foreground delivery you did NOT tap. | — | If a `pushNotificationClick` exists for a mere delivery, mismatch 1 is confirmed: one callbackUrl, one backend action. Decide with the CTO whether the SDK should stop sending `.delivered` or the backend should distinguish. | ❌ Run 14, admin: campaign QA-C2 (delivered in the foreground, never tapped) shows Clicks 1 \| 100%. The SDK fires the same callbackUrl for delivered, opened and clicked, and the backend counts every hit as pushNotificationClick, so foreground deliveries inflate click stats. Decision for CTO + backend: either the SDK stops calling the URL for delivered, or it appends an event type the click tracker filters on. (If QA-C2 was tapped after all, this row flips to pass; tell me.) |
| PUSH-07 | P0 | 1.0 | Non-Releva notification suppressed in foreground<br>_Expected SDK behaviour. Confirm the client accepts it; otherwise it is a change request._ | Firebase console → Cloud Messaging → test message to the device FCM token. | Send while app is in foreground; then while in background. | Foreground: NOT shown (SDK returns `[]` for non-Releva payloads). Background: shown by iOS as usual. | — | ☐ |
| PUSH-08 | P1 | 1.0 | Offline tap is queued and retried | Airplane mode ON, push already on the lock screen. | Tap it. Wait. Airplane OFF. | `Callback URL failed: …`; within 30 s of reconnecting: `Firing callback URL` and `Callback URL response: 200`. | Event lands late but lands. | ✅ Run 17: airplane mode, tap on the QA-P7 inbox push → 'Tracked as opened' → callback GET failed 'The Internet connection appears to be offline' → 'Failed to send engagement events', event kept pending; retried at +4 s (failed again); after the network came back the batch timer fired the callback → 200 'Successfully sent 1 engagement events' (30 s later). Navigation to the inbox message worked offline from the cache. |
| PUSH-09 | P1 | 1.0 | Pending events survive a restart | As PUSH-08 but kill the app while offline. | Relaunch online. | Callback fires shortly after launch (events reloaded from `rlv_pending_engagement_events`). | Event lands. | ✅ Run 5 (incidental): the previous session ended with one engagement event still pending (the crash); on the next launch the SDK logged 'Loaded 1 pending engagement events' and fired the callback (200). Same mechanism as an offline tap. |
| PUSH-10 | P1 | 1.0 | Badge | Push delivered. | Look at the app icon. | Badge shows 1 (`aps.badge = 1`). The app never clears it (harness). | — | ✅ Run 13: aps.badge=1 on every Releva push; the app icon shows the badge (tester), SpringBoard log 'Badge can be set … badgeNumber: 1'. The harness does not clear it on open, which is app-side. |
| PUSH-11 | P1 | 1.1 | Silent inbox-sync push | Campaign with platforms `[appInbox]` only, app in background or foreground. | Send. | No visible notification. App log shows `didReceiveRemoteNotification`; inbox refreshes (INB-10). The app also fires `trackEngagement(.opened)` for this silent push (harness bug) → a spurious callback GET. | Silent pushes write no delivery events; the spurious click is app-side. | ⚠️ Run 9: silent push reached didReceiveRemoteNotification in the foreground; harness now forwards it to the inbox service. Run 14, admin: campaign QA-C4 Delivered 1 / Clicks 0 as expected. Device-side inbox refresh from the silent push still to be observed in the log. |
| PUSH-12 | P1 | 1.0 | Campaign stats reconcile | One real campaign to the test profile; PUSH-01..05 done. | Admin → campaign stats for today. | — | Sent, Delivered and Clicks match what the device did, allowing for mismatch 1 and 6. | ⚠️ Run 14, admin: QA-C1, C3, C5 each show Sent 1 / Delivered 1 / Clicks 1 matching one device tap; QA-C4 (silent) Delivered 1 / Clicks 0. Counts reconcile except that a foreground delivery also counts as a click (PUSH-06). |
| PUSH-13 | P2 | 1.1 | isRelevaMessage prefix match | Releva push and a Firebase console push. | Observe the app's `isRelevaMessage` log for each. | true for `click_action` starting with `RELEVA_` (incl. `RELEVA_INBOX_SYNC`), false for the console push. | — | ☐ |
| PUSH-14 | P1 | 1.0 | SDK owns the notification delegate | Debug build. | Launch; read the app's 1-second-after-init debug line. | It reports the delegate is the SDK's `NotificationService`. If not, foreground handling and tap tracking will fail. | — | ✅ Run 2+3: app printed 'Delegate is NotificationService (SDK)' after init; run 3 confirmed willPresent and didReceive both reached the SDK. |

### H. Rich notifications (Notification Service Extension)

`RelevaNotificationServiceExtension` runs in the `NotificationExtension` target. Watch its logs in Console.app filtered by process `NotificationExtension`.

| ID | Prio | Since | Scenario | Precondition | Steps | Expect on device / in log | Expect in backend | Result |
|---|---|---|---|---|---|---|---|---|
| EXT-01 | P0 | 1.0 | JPEG image attachment | Push with public https `imageUrl` (.jpg). | Send, pull down the notification. | Image shown in the expanded notification. | — | ✅ Run 3: JPEG from storage.googleapis.com. Run 4: placehold.co JPG. Run 8: QA-P15 picsum.photos random photo, two sends showed two different photos (screenshots). |
| EXT-02 | P1 | 1.0 | PNG, GIF, WebP images | Three pushes. | Send each. | Each renders; GIF may be static. | — | ✅ Run 8: PNG and GIF attach and display. WebP (QA-P12) showed text only because UNNotificationAttachment accepts JPEG/PNG/GIF only. Run 9, after the SDK-branch fix (extension transcodes other formats to JPEG): WebP push displays its image (screenshot). HEIC/HEIF go through the same path, not device-tested. |
| EXT-03 | P0 | 1.0 | Title and body from the extension | Push with distinct iOS subject/body. | Send. | Text matches the admin content exactly (extension overrides title/body when `click_action == RELEVA_NOTIFICATION_CLICK`). | — | ✅ Run 3: title 'Test push image' and body match the admin iOS content. |
| EXT-04 | P0 | 1.0 | Broken image URL | `imageUrl` returning 404. | Send. | Notification still delivered with text only; no crash in Console. | — | ✅ Run 8: QA-P13 with https://httpbin.org/status/404 → text-only notification, extension did not crash, callback 200. |
| EXT-05 | P1 | 1.0 | Slow or huge image | `imageUrl` > 10 MB or on a throttled host. | Send. | Delivered within ~30 s via `serviceExtensionTimeWillExpire` best attempt (text only). | — | ✅ Run 8: QA-P14 with https://httpbin.org/delay/45 → notification arrived text-only after the wait (serviceExtensionTimeWillExpire best attempt). |
| EXT-06 | P0 | 1.0 | Exactly one notification per push<br>_The extension calls `contentHandler` from both the FCM populate path and its own path; this row proves iOS tolerates it._ | Any rich push. | Send 3 pushes. | 3 notifications, no duplicates; Console shows no warning about the content handler being called twice. | — | ✅ Run 3–9: exactly one notification per push. Run 7 system log showed iOS 'Ignoring additional replacement content replies' because the extension replied twice. Run 9 (SDK branch, Firebase populate only for non-Releva pushes): system log shows one 'Received replacement content' and no ignore error; extension runtime 0.02 s for a text push. |
| EXT-07 | P1 | 1.0 | Dynamic category when a button is present | Push with `button`. | Expand the notification. | 'Open' action visible (see PUSH-05). | — | ✅ Run 3: 'Shop now' action visible on expand; tap yields RELEVA_ACTION_BUTTON. |
| EXT-08 | P1 | 1.0 | Non-Releva push through the extension | Firebase console test with an image, app in background. | Send. | Extension leaves title/body alone; whether FCM's populate attaches the image is observed and recorded. | — | ☐ |

### I. Deep links from push

The SDK routes on `target`. The app expects `myapp://consumer.app/<path>` and screen names `home`, `cart`, `checkout`, `product/<id>`, `inbox`, `inbox/<id>`.

| ID | Prio | Since | Scenario | Precondition | Steps | Expect on device / in log | Expect in backend | Result |
|---|---|---|---|---|---|---|---|---|
| DL-01 | P0 | 1.1 | target=screen → cart | Push `mobileTarget=screen`, `mobileTargetScreen=cart`. | Tap from background. | App opens on Cart. App log shows the `RelevaNavigateToScreen` notification with `screen: cart`. | — | ✅ Run 4: QA-P2 target=screen cart → SDK 'Navigating to screen: cart' → RelevaNavigateToScreen → app opened the Cart tab (screenshot). |
| DL-02 | P0 | 1.1 | target=screen → product/1 | `mobileTargetScreen=product/1`. | Tap from background. | Product 1 detail opens; a `productView` is tracked. | Timeline `productView` shortly after the click. | ✅ Run 5: QA-P3 with screen product/prod_001 → SDK routed → app opened the Nike Air Max detail (screenshot) and tracked productView prod_001. The earlier product/1 fixture correctly showed 'Product not found' (id not in the catalogue). |
| DL-03 | P0 | 1.1 | target=screen → checkout and home | Two pushes. | Tap each. | Checkout opens; Home resets the stack. | — | ✅ Run 6: checkout target from the Test button. Run 12: tester reports the product target push now navigates as well (no log captured for it). |
| DL-04 | P0 | 1.1 | navigate_to_parameters parsed | `mobileTargetKV` = `[{key: promo, value: SUMMER}]`. | Tap. | App log prints `parsedParameters: ["promo": "SUMMER"]` alongside the raw JSON string in `parameters`. | — | ✅ Run 11: navigate_to_parameters {"promo":"SUMMER","source":"qa"} arrived on the tap and the SDK also delivers it parsed as parsedParameters; the harness logs the raw string. |
| DL-05 | P0 | 1.1 | target=url with https | `mobileTarget=url`, `mobileTargetUrl=https://releva.ai`. | Tap. | SDK opens Safari itself ~0.1 s after the tap. | — | ✅ Run 4: QA-P6 target=url https://releva.ai → SDK 'Opening external URL' → Safari opened releva.ai (screenshot). Callback 200. |
| DL-06 | P0 | 1.1 | target=url with app scheme | `mobileTargetUrl=myapp://consumer.app/cart`. | Tap. | `RelevaNavigateToURL` posted; app opens Cart. (Safari cannot open `myapp://` because the scheme is not registered in the shipping plist; only this path works.) | — | ✅ Run 3: target=url with navigate_to_url myapp://consumer.app/home → SDK 'Detected internal deep link, posting to app' → RelevaNavigateToURL → app handled 'home'. Worked from a foreground tap and from the action button. |
| DL-07 | P0 | 1.1 | target=inbox opens the message | Campaign with platforms `[ios, appInbox]`. | Tap. | `RelevaNavigateToInbox` with `inboxMessageId`; app opens the inbox detail for that message and marks it read. | PG `inboxMessageDeliveries.read = true`; event `inboxMessageRead`. | ✅ Run 12 (app in the foreground): QA-P7 tap → SDK: inbox sync signal, target inbox, parsedParameters inboxMessageId 8 → harness opened the message detail directly (route resolves the campaign-level id via getMessageById), design rendered, POST /inbox/messages/{id}/read 202. Callback GET 200. |
| DL-08 | P0 | 1.1 | Cold-start variants | App force-quit. | Repeat DL-01, DL-05, DL-07 from a cold start. | Same navigation after launch (app defers until the SDK is initialised). | — | ✅ Run 11 (app force-quit, QA-P2 tapped from the lock screen): SDK handled the tap 20 ms after launch, target=screen cart, harness opened the Cart tab, callback GET 200. Fix chain: SDK keeps the last navigation request (pendingNavigation / consumePendingNavigation), harness registers its observers in AppState.init and replays a missed request on appear. Run 10 had shown the same tap landing on Home. |
| DL-09 | P1 | 1.1 | Foreground variants | App open. | Repeat DL-01 and DL-07 with the app in foreground; tap the banner. | Same navigation. | — | ✅ Run 4: all taps were done with the app in the foreground (willPresent then didReceive); navigation worked for cart, product, unknown screen, url and inbox. |
| DL-10 | P1 | 1.1 | Unknown screen name | `mobileTargetScreen=doesnotexist`. | Tap. | SDK posts the notification; the app ignores it without crashing. | — | ✅ Run 4: QA-P5 screen doesnotexist → SDK posted the screen, app logged 'Unknown path' and stayed put; no crash. |

### J. Banners (SwiftUI modifier)

Fixtures: one banner block per displayType and trigger, attached to the Home page, `running`, segment 'everyone'. Page config is cached 60 s but banner saves bust it. The app initialises banners twice (harness bug), so count impressions in the SDK log (`Banner impression tracked for <token>`), not only in the admin.

| ID | Prio | Since | Scenario | Precondition | Steps | Expect on device / in log | Expect in backend | Result |
|---|---|---|---|---|---|---|---|---|
| BAN-01 | P0 | 1.0.4 | Popup, trigger immediately | Popup banner block on Home. | Open Home. | Popup renders the Unlayer design; log `Banner impression tracked for <blockToken>`; `Sending POST request to …/api/v0/impressions` 200. | Timeline `bannerImpression` with `bannerBlockId = <blockToken>`; banner stats impressions +1 (+2 if the harness double-init fires; note it). | ✅ Runs 1–6: centred card. Run 21: under the navigation bar → overlay window. Run 23: card stretched to full height → fixed. Run 25: cold start impression without display (screen detached from the window) → fixed. Run 26 (device + log): cold start shows the popup with the image in place; log reads 'attached view model' → 'showing window (…)' → impression; close → 'hiding window' + bannerClose 202. Screenshot 10:29. Open with CTO: impression is sent when queued, not when drawn. |
| BAN-02 | P0 | 1.0.4 | Popup, delaySeconds 5 | Trigger delaySeconds = 5. | Open Home, count. | Appears ~5 s later. Leaving Home before 5 s cancels it. | Impression only when shown. | ✅ Run 20: block f34a090d-… switched to a delay trigger; screen view at 08:51:30, impression at 08:51:40 → the banner appeared after the configured delay and was counted once. |
| BAN-03 | P0 | 1.0.4 | Bar top with close | Bar banner, displayPosition top. | Open Home → tap X. | Bar under the safe area; close removes it; log `Banner action 'bannerClose' tracked`. | Timeline `bannerClose`; Redis suppression set → reopening Home does not return this banner (unless `showAlways`). | ❌ Run 20: bar under the status bar, own white frame, small X. Run 21: bar under the navigation bar (title and cart button on top). Run 22 (overlay window): the bar is above the app's bars now, but the overlay window came up in LIGHT appearance over the dark app — the status-bar strip was white with dark status-bar text — and the strip took Unlayer's default body colour (#F7F8F9). Fixed on the branch: the overlay window copies the app window's light/dark style; the strip takes the first row's or first column's colour, else the system background of the current theme. Tracking (bannerClick / bannerClose) was correct in every run. Re-test: top bar with a dark strip and white status-bar text above the title. |
| BAN-04 | P0 | 1.0.4 | Bar bottom | displayPosition bottom. | Open Home. | Bar above the tab bar / home indicator. | Impression. | ⚠️ Run 21: bottom bar edge to edge with the X in the corner, tap on the strip closed it (bannerClose 202). With the overlay window it will now cover the tab bar like the web bottom:0 bar; confirm that is wanted and that the home-indicator strip takes the row colour. |
| BAN-05 | P0 | 1.0.4 | Flyout left and right | Two flyout blocks. | Open Home. | Side panels slide in from the configured side; close works. | Impressions and closes. | ⚠️ Run 26: flyout rendered as a full-height sheet with the X under the status bar → rebuilt to the web spec (bottom-anchored content-sized panel, 20 pt side margin, no overlay). Run 27: with the 600 px design capped only to the screen the panel filled the width and height and read as a popup at the bottom. Now capped to 72 % of the width and 60 % of the height so the docking side is visible and tall designs scroll inside; snapshot + contract tests pass. Re-test left and right after rebuild. Design guidance: a flyout made for a corner (narrow, short) looks best, as on the web. |
| BAN-06 | P0 | 1.0.4 | Static banners: afterbegin / beforeend / afterend / replace | Four static blocks with cssSelector `#home-content`. | Open Home. | Inline placement matches the strategy; `replace` hides the grid. Impression on display. | Impressions. | ✅ Run 2: block f34a090d-… is configured Static / After / #home-content in the admin (screenshot). SDK appended it below the Home content, edge to edge above the tab bar, no close button, persistent while Home is shown: exactly the static afterend contract. Other three strategies not yet run. |
| BAN-07 | P0 | 1.0.4 | Static banner with a non-matching selector | cssSelector `#other`. | Open Home. | Not rendered, no impression. | No event. | ☐ |
| BAN-08 | P0 | 1.0.4 | scrollPercentage 50 | Trigger scrollPercentage 50. | Open Home, scroll halfway. | Appears when the grid passes 50 %. | Impression. | ☐ |
| BAN-09 | P0 | 1.0.4 | cartChanged and wishlistChanged triggers | Two blocks with those triggers. | Open Home → Product 1 → Add to cart → back to Home. Then heart a product on Home. | Banner appears after the cart/wishlist change (`RelevaClient.setCart` calls the SDK's own `BannerManagerService.onCartChanged`). | Impression. | ☐ |
| BAN-10 | P1 | 1.2 | Full-screen popup and background image | Popup with full-screen option and a background image. | Open Home. | Covers the screen; image renders with the configured fit. | — | ⚠️ Run 6: a tall portrait image in a popup is capped to the screen height and scrolls inside the card (web parity). Run 23: with the card-height fix a tall design gets the capped scrolling card and a short one a compact card; the image filling a too-tall card was masking the height bug. Decide with the CTO: keep scroll (as web) or scale-to-fit on phones. |
| BAN-11 | P1 | 1.2 | Content-level text colour | Banner with white text (`color`) on a dark background. | Open Home. | Text is white, not body-default black (1.2.0 fix). | — | ☐ |
| BAN-12 | P0 | 1.0.4 | Link tap reports click and navigates | Popup with a button linking to `myapp://consumer.app/cart` and another to `https://releva.ai`. | Tap each. | `Banner action 'bannerClick' tracked`; app navigates / Safari opens. | Timeline `bannerClick`; banner attribution row; suppression set. | ✅ Run 1: bannerClick 202 on every tap; myapp://consumer.app/cart navigated. https link did nothing because of the app handler (fixed in HomeView.swift after run 1). Run 2: tap sent bannerClick 202 and opened the browser (Chrome, the default). Bar/static banner stays on screen after the link tap by design; a popup dismisses itself. |
| BAN-13 | P1 | 1.0.4 | Dedupe within a session | Popup banner. | Home → Cart → Home. | Banner does not reappear (already displayed this init) or reappears only if the backend returned it again and the SDK's displayed set was reset; record what happens. | Count impressions. | ⚠️ Run 1: repeat Home visits did not re-show or re-count the bar banner. Run 2: after visiting Cart and returning, the bar banner was displayed and counted again (impressions at 14:20:23 and 14:20:34). Dedupe lives with the Home view's state, so a tab switch that recreates Home re-shows it. Comparable to a web page reload; decide if acceptable. |
| BAN-14 | P1 | 1.0.4 | showAlways vs one-time | One block `showAlways`, one normal; both closed once. | Reopen Home. | showAlways returns; the other does not (`banner/click/<domainId>/<bannerId>/p:<deviceId>` key). | — | ✅ Run 5: the 'Fullscreen banner' (fd4de9a7-…, showUntilClick) that was clicked in run 2 is no longer returned for this device; 'Carousel banner' (aa275c11-…) still returns after a close, so it is showAlways or reentrable. Suppression after click works as designed; a clicked banner reappears only with showAlways/reentry or a new device id. |
| BAN-15 | P1 | 1.2 | sessionInterval | Block with sessionInterval 2. | Cold start twice. | Shown only when `device.sessions % 2 == 0`. | — | ☐ |
| BAN-16 | P1 | 1.0.4 | Dark mode and rotation | Any popup and bar. | Toggle dark mode; rotate. | Legible in both; bar re-lays out. | — | ⚠️ Dark mode: the device ran in dark mode for runs 5–12 and popups, static blocks and the inbox rendered with their design colours (screenshots). Rotation not tested yet. |
| BAN-17 | P1 | 1.0.4 | Banner without a design is ignored | Block with html only (design null) or displayType custom. | Open Home. | Nothing rendered, no impression, no crash. | No event. | ☐ |
| BAN-18 | P1 | 1.0.4 | Two banners at once | Popup + bar both immediate. | Open Home. | Both render; closing one leaves the other. | Two impressions. | ✅ Run 14: two banners returned for Home (4652 popup, 4654 carousel). The second showed only after the first was closed, each with its own impression and bannerClose. |
| BAN-19 | P2 | 1.0.4 | leaveIntent never fires on mobile | Block with leaveIntent. | Use the app. | Never shown (documented). | — | ☐ |
| BAN-20 | P2 | 1.0.4 | Banners on token-less screens<br>_Client guide item._ | Block attached to a Cart page in the admin. | Open Cart. | Never returned: the request has no page token, so no Page resolves. | — | ☐ |

### K. Stories

Stories are returned in the push response and shown one at a time in a full-screen cover. All story tracking goes to `/api/v0/push/events`.

| ID | Prio | Since | Scenario | Precondition | Steps | Expect on device / in log | Expect in backend | Result |
|---|---|---|---|---|---|---|---|---|
| STO-01 | P1 | 1.1 | Story, trigger immediately | Running story with 3 slides on Home. | Open Home. | Full-screen viewer; `Sending POST request to …/api/v0/push/events` with `action: storyImpression`, 202. | Timeline `storyImpression` with `products[0].storyId`. | ✅ Run 5: story ae643a37-… shown full screen on Home (screenshots), storyImpression → /push/events 202. |
| STO-02 | P1 | 1.1 | Auto-advance and progress bars | Slides with durationSeconds 3. | Watch. | Advances every 3 s; bars fill; `storySlideView` per slide. | Events per slide. | ✅ Run 5: three slides with progress bars, storySlideView for slide ids 1, 2, 4 (auto-advance and taps). |
| STO-03 | P1 | 1.1 | Tap and swipe navigation, close | Story open. | Tap right, tap left, swipe down. | Next/previous slide; close sends `storyClose`. | `storyClose`; Redis `story/view/…` key set → not shown again. | ✅ Run 5: X closed the viewer → storyClose 202. Tap/swipe navigation produced the slide views. |
| STO-04 | P1 | 1.1 | Slide link tap | Slide with a link to `myapp://consumer.app/product/2`. | Tap. | `storySlideClick` with slideId; viewer closes; product 2 opens. | `storySlideClick` event and story attribution. | ☐ |
| STO-05 | P1 | 1.1 | Completion and end behaviours | Three stories: dismiss, loop, stayOnLast. | Let each play out. | `storyComplete` sent once; then dismisses / loops / stays on last slide respectively. | One `storyComplete` per story. | ☐ |
| STO-06 | P1 | 1.1 | Two stories queue sequentially | Two running stories. | Open Home. | Second starts after the first closes; two impressions. | — | ⚠️ Run 5: a duplicate storyImpression fired immediately after every storyClose with no slide view: three Home screen views at launch each returned the story and the display queue kept every copy. Fixed on the SDK branch (token dedupe in StoryDisplayViewModel.enqueue); re-test. |
| STO-07 | P1 | 1.1 | Story with zero slides is skipped | Story with no slides. | Open Home. | Nothing shown, no impression. | — | ☐ |
| STO-08 | P1 | 1.1 | Story stats in admin | STO-01..05 done. | Admin → story stats. | — | Mismatch 4: the SDK sends `storyId = story token`, the stats aggregate on numeric `story.id`. Record whether impressions/clicks show up. If 0 while events exist in the timeline, backend fix needed. | ☐ |
| STO-09 | P1 | 1.1 | Delay trigger | Story with delaySeconds 5. | Open Home. | Appears after 5 s. | — | ☐ |

### L. NPS surveys

The backend picks at most one eligible survey per push response. Fixture: survey `active`, platforms `[ios]`, trigger screenView on the Home page name (or sessionCount 1), no segment.

| ID | Prio | Since | Scenario | Precondition | Steps | Expect on device / in log | Expect in backend | Result |
|---|---|---|---|---|---|---|---|---|
| NPS-01 | P1 | 1.1 | Survey appears on the configured trigger | Fixture above. | Open Home. | Sheet appears after `triggerDelaySeconds`. | Response body contained `nps`. | ✅ Run 1: survey appeared on Home. |
| NPS-02 | P1 | 1.1 | Score → follow-up → thank-you → submission | Survey open. | Pick 9, answer follow-up, submit. | Follow-up text is the promoter variant (≥9); thank-you shows and auto-dismisses after 2 s; `Sending POST request to …/api/v0/nps/<token>/submissions` 202. | Admin → NPS → submissions lists it; timeline `npsSubmission` with score 9, category promoter; PG `npsSubmissionStates.answeredAt` set; profile custom fields `nps_score`, `nps_category`. | ⚠️ Run 1: score 5 → POST /nps/306ad716-…/submissions 202; event npsSubmission with score 5, npsCategory detractor (correct for ≤6), npsId 1. The profile snapshot at 10:59 shows empty custom fields, so nps_score/nps_category on the profile are not visible yet; check PG npsSubmissionStates and the CH profile row. |
| NPS-03 | P1 | 1.1 | Passive and detractor branches | Reset frequency (delete `npsSubmissionStates` row) between runs. | Score 7, then 3 on a new session. | Follow-up variants passive / detractor. | Categories recorded accordingly. | ⚠️ Run 1: score 5 → detractor (category confirmed in the event). Run 16: score 8 and run 18: score 7 → 202 each (passive). Verify npsCategory passive in the timeline; the follow-up text variants were not compared on screen. |
| NPS-04 | P1 | 1.1 | Skip and session suppression | Survey open. | Tap Skip. Navigate around. | No request. Survey does not return this session. After a cold start it can return (unless frequency policy blocks). | — | ⚠️ Run 14: Skip dismissed the survey; nothing is sent (correct). Suppression for the rest of the session and reappearance in a new session not yet verified. |
| NPS-05 | P1 | 1.1 | Frequency policy | Survey `onceEver` answered in NPS-02. | Cold start, open Home. | No survey. | `npsSubmissionStates` blocks it; `cooldownUntil` for cooldown policies. | ☐ |
| NPS-06 | P1 | 1.1 | customEvent trigger and cancelOnEvents (temp code S10) | Survey with trigger customEvent `qa_nps`, cancelOnEvents `qa_cancel`, delay 5 s. S10. | Call `trackEvent("qa_nps")`. Repeat and call `trackEvent("qa_cancel")` within 5 s. | First: survey after 5 s. Second: suppressed for the session. | — | ☐ |
| NPS-07 | P1 | 1.1 | sessionCount trigger | Trigger sessionCount minSessions 2. Fresh install. | First session: Home. Cold start: Home. | Not on session 1; shows on session 2. | — | ☐ |
| NPS-08 | P2 | 1.1 | appVersion and platform gating | appVersionMin 2.0.0; S3 sets 1.2.3. Second survey with platforms [android]. | Open Home. | Neither shows. Set version 2.5.0 → the first shows. | — | ☐ |
| NPS-09 | P2 | 1.1 | Appearance | Survey with custom colours, dark variant, pill buttons. | Toggle dark mode. | Colours and button style match the config in both modes. | — | ☐ |
| NPS-10 | P1 | 5.0 | Submit while offline | Airplane mode. | Submit a score. | Up to 4 attempts (~4 s of backoff), then an error is logged by the app's onSubmit task; no crash; thank-you still shows (submission is fire-and-forget in the app). | No submission recorded; document. | ☐ |
| NPS-11 | P2 | 1.1 | Admin 'Opens' column | NPS-01 done. | Admin → NPS scores. | — | Mismatch 5: the backend counts `npsOpen`, the SDK never sends it, so Opens = 0. Known gap. | ☐ |
| NPS-12 | P2 | 1.1 | followUpRequired | Survey with followUpRequired true. | Try to submit without a comment. | Submit disabled until a comment is entered. | — | ☐ |

### M. App inbox

`InboxService.shared` talks to `/api/v0/inbox/*` with `userId = profileId`. Updates are optimistic with rollback. Errors are swallowed: a 401 looks like an empty inbox.

| ID | Prio | Since | Scenario | Precondition | Steps | Expect on device / in log | Expect in backend | Result |
|---|---|---|---|---|---|---|---|---|
| INB-01 | P1 | 1.1 | List loads and badge shows unread count | ≥3 inbox messages delivered to the profile (campaign with appInbox, or `testInboxMessage`). | Launch, look at the Inbox tab badge, open Inbox. | `GET …/api/v0/inbox/unread-count?userId=<profileId>` 200; badge = count. `GET …/inbox/messages?userId=…&limit=20` 200; list shows title, preview, time, unread dot. | PG `inboxMessageDeliveries` rows for this userId. | ✅ Run 12: list loads on open (GET /inbox/messages limit=20 + unread-count, both 200) and the tab badge follows the unread count. |
| INB-02 | P1 | 1.1 | Pagination | >20 messages. | Scroll to the bottom. | Second GET with `cursor=`; no duplicate rows; `hasMore` false at the end. | — | ✅ Run 12: with more than 20 messages the list requested the next page (GET …&cursor=eyJ… 200) and appended it. Tester note: it loads as a page, not an endless scroll. |
| INB-03 | P1 | 1.1 | Pull to refresh | Inbox open. | Pull down. | Two parallel GETs (messages + unread-count); spinner ends. | — | ✅ Run 12: pull to refresh re-fetches messages and unread count. |
| INB-04 | P1 | 1.1 | Open message marks it read | Unread message. | Tap it. | Dot disappears instantly; `POST …/inbox/messages/<id>/read` 202; unread count −1. | PG `read = true`, `readAt` set; timeline `inboxMessageRead`; campaign stats 'Inbox reads' +1. | ✅ Run 12: opening a message sends POST /inbox/messages/{id}/read 202 and the unread count drops; also exercised by the push-opened message (DL-07). |
| INB-05 | P1 | 1.1 | Mark all read | Several unread. | Toolbar 'Mark All Read'. | All dots clear; `POST …/inbox/messages/read-all` 202; badge 0. | All rows `read = true`. | ✅ Run 12: Mark all read → POST /inbox/messages/read-all 202, list updates. |
| INB-06 | P1 | 1.1 | Delete from list and from detail | Two messages. | Swipe-delete one; open the other and tap trash. | Rows vanish; `DELETE …/inbox/messages/<id>` 204. | PG `status = 'deleted'`; timeline `inboxMessageDelete`. | ✅ Run 4+5: swipe/detail delete → DELETE /inbox/messages/<id> → 204 for three messages. Backend status=deleted still to be checked. |
| INB-07 | P1 | 1.1 / 5.0 | Rollback on failure | Airplane mode ON, one unread message cached. | Open Inbox → tap the unread message. | Optimistic read applies, then reverts to unread when the request fails; no crash. | Row unchanged. | ☐ |
| INB-08 | P1 | 1.1 | Cached inbox offline after cold start | Inbox loaded once. Airplane mode ON. | Kill, relaunch, open Inbox. | Cached list and count appear (restored from `rlv_inbox_*`). | — | ✅ Run 15: airplane mode, cold launch → the cached inbox list is shown, no request attempted, no crash. (Pull to refresh offline ends quietly because the SDK swallows fetch errors; the list keeps the cache.) |
| INB-09 | P1 | 1.1 | Stale refresh on foreground | Inbox loaded. | Background >5 min, foreground. | GETs fire again (`refreshIfStale`). | — | ☐ |
| INB-10 | P1 | 1.1 | Silent push sync | App in foreground on Home. | Send an appInbox-only campaign. | Badge increments without opening Inbox; opening Inbox shows the new message without pull-to-refresh. | — | ☐ |
| INB-11 | P1 | 1.1 | Message rendering and link action | Message with image, text and a button to `myapp://consumer.app/product/3`. | Open it; tap the button. | `InboxMessageView` renders the design; `POST …/inbox/messages/<id>/action` 202; product 3 opens. | Timeline `inboxMessageClick` with `devicePlatform: ios`; campaign stats 'Inbox clicks' +1. | ⚠️ Run 6: message button sent inboxMessageClick 202 and opened the product. Run 12: the design renders (heading, text, button) and the button navigates. Run 17 offline: the message rendered from the cache and the button navigated, but POST /inbox/messages/{id}/action went out with no network and was silently dropped (inbox errors are swallowed, no queue), so that inbox click is lost. Only push engagement events are queued offline; note for the README / CTO. |
| INB-12 | P1 | 1.1 | Profile change reloads the inbox | Two profiles with different inboxes. | Settings → switch Profile ID → Inbox. | Old list cleared; new GETs with the new userId. | — | ✅ Run 15 fail: after a profile switch the old user's inbox stayed with no request (un-scoped UserDefaults cache restored with its fetch time). Fixed on the branch (cache tagged with its owner profile, cleared and refetched on change, setProfileId forwards to the inbox). Run 16: GET /inbox/messages and /unread-count for the new profile fired right after the switch, and again for the original profile on the switch back; the cached list stayed available in airplane mode. |
| INB-13 | P2 | 1.1 | Wrong token shows an empty inbox | Invalid access token. | Open Inbox. | Empty state, no error (documented limitation). | — | ☐ |
| INB-14 | P2 | 1.1 | Expired messages are hidden | Message with `expiresAt` in the past. | Refresh. | Not listed. | — | ☐ |

### N. UIKit presenters

The example app is SwiftUI, so these need a scratch `UIViewController` (temp code S11) pushed from a Debug-only Settings button. All 4.2.0 code, never run on a device.

| ID | Prio | Since | Scenario | Precondition | Steps | Expect on device / in log | Expect in backend | Result |
|---|---|---|---|---|---|---|---|---|
| UIK-01 | P1 | 4.2 | BannerPresenter shows a popup | S11 host with `BannerPresenter(host:client:onLinkTap:)`, `start()` in viewWillAppear. Popup fixture returned for the request S11 makes. | Push the scratch controller. | Popup presented `.overFullScreen`; one `Banner impression tracked` line. | One `bannerImpression`. | ☐ |
| UIK-02 | P1 | 4.2 | Popup and flyout together | Both fixtures. | Push the scratch controller. | Both in one overlay; two impressions; dismissing one keeps the other. | Two impressions. | ☐ |
| UIK-03 | P1 | 4.2 | Bar in a child controller | Bar fixture. | Push; rotate. | Bar pinned to the safe area edge, correct height; re-lays out on rotation (iOS 16+). | — | ☐ |
| UIK-04 | P1 | 4.2 | Banner arrives while a modal is up | S11 presents a modal then triggers the request. | Run. | Banner shows above the modal (topMostPresentedViewController). | — | ☐ |
| UIK-05 | P2 | 4.2 | stop() then start() re-presents without a second impression | Popup on screen. | Pop the controller (stop), push again (start). | Same popup returns; no second `Banner impression tracked` line (documented limitation). | — | ☐ |
| UIK-06 | P1 | 4.2 | Close reports bannerClose and takes app modals down | Popup up, then present an alert from the host. | Tap the banner's X. | `Banner action 'bannerClose'`; the alert is dismissed too (documented trade-off). | `bannerClose` event. | ☐ |
| UIK-07 | P1 | 4.2 | NpsPresenter | S11 with `NpsPresenter(host:onSubmit:onSkip:)`; NPS fixture. | Trigger; skip once; trigger on a new session; submit. | Page sheet; skip closes it; submit calls onSubmit (S11 forwards to `submitNpsResponse`) → 202. | Submission recorded. | ☐ |
| UIK-08 | P1 | 4.2 | StoryViewerView in a UIHostingController | S11 story branch. | Present. | Viewer works; S11 calls `storyImpression` manually; slide events fire; `onClose` dismisses. | Events. | ☐ |
| UIK-09 | P2 | 4.2 | Static banners dropped on UIKit path | Static fixture. | Run S11. | Not shown and NOT counted. | No impression. | ☐ |
| UIK-10 | P2 | 4.2 | iOS 15 bar height | An iOS 15 device, if any. | UIK-03 on it; rotate. | Height correct on first show; may be stale after rotation until the next banner event (documented). | — | ☐ |

### O. Resilience, retries and threading

5.0.0 moved the network layer to async/await and off the main actor. Nothing here was ever observed on a device.

| ID | Prio | Since | Scenario | Precondition | Steps | Expect on device / in log | Expect in backend | Result |
|---|---|---|---|---|---|---|---|---|
| RES-01 | P1 | 5.0 | Offline browsing | Airplane mode ON. | Home → Product → Add to cart → Cart. | `Request failed, retrying... (2 attempts left)`, `(1 attempts left)`, then `networkError`; UI never blocks; no crash; cart still works locally. | Nothing written; nothing queued except engagement events. | ✅ Run 15: airplane mode → screen views retried 3 times about a second apart then threw networkError("The Internet connection appears to be offline."); token registration failed with the same message; app kept working and recovered when online. Run 17 confirmed for product view, custom event and screen view: each retried 3× then failed; those events are not queued and are lost (by design, only push engagement is queued). Improvement for CTO: skip the retries when the error is notConnectedToInternet. |
| RES-02 | P1 | 5.0 | 5xx retry timing | Endpoint override pointing at a local server that returns 500. | Open Home. | `Server error 500, retrying...` twice with ~2 s gaps, then `serverError(500, …)`. | Server log shows 3 attempts. | ⚠️ Run 14: retry timing observed on a network error (DNS): 4 attempts at ~1.07 s intervals, then the error is thrown. 5xx path not exercised (needs an endpoint override to a server returning 500). |
| RES-03 | P1 | 5.0 | Timeout | Local server that sleeps 60 s. | Open Home. | Fails after ~30 s per attempt (`requestTimeoutInterval`). | — | ☐ |
| RES-04 | P1 | 5.0 | Backgrounded mid-request | Slow server. | Open Home and immediately background; foreground later. | Request completes or fails cleanly; no crash. | — | ☐ |
| RES-05 | P1 | 5.0 | Rapid navigation stress | SDK enabled, banners configured. | Home ↔ Cart 20× fast; open 5 products quickly. | No UI hitch; no Xcode purple runtime warnings (Main Thread Checker, actor isolation); responses arrive in order or are discarded. | Timeline shows the views. | ☐ |
| RES-06 | P1 | 4.2 / 5.0 | Memory with repeated banners and stories | Popup + story fixtures. | Open/close 20×. | Memory gauge returns to baseline; no leak growth. | — | ☐ |
| RES-07 | P1 | 5.0 | Task cancellation | Slow server. | Leave a screen while its request is in flight. | No crash; error is a `RelevaError`, never a bare `CancellationError`. | — | ☐ |
| RES-08 | P2 | 4.0 | Response decoding tolerance | Normal use across all sections. | Grep the session log. | No `Failed to decode response` lines. If one appears, capture the body; 4.0 made `meta/custom/data` tolerant but the envelope may still fail. | — | ☐ |

### P. Privacy manifest and release hygiene

Items that only matter when the client ships.

| ID | Prio | Since | Scenario | Precondition | Steps | Expect on device / in log | Expect in backend | Result |
|---|---|---|---|---|---|---|---|---|
| REL-01 | P2 | 3.1 | Privacy manifest is in the built app | Debug build in DerivedData. | `find ~/Library/Developer/Xcode/DerivedData -path '*ShoppingAppSwift.app*' -name PrivacyInfo.xcprivacy` | A copy inside `RelevaSDK_RelevaSDK.bundle`. | — | ✅ Run 13: the built app contains RelevaSDK_RelevaSDK.bundle/PrivacyInfo.xcprivacy alongside the Firebase manifests. The extension module ships no resource bundle, so none is expected in the appex. |
| REL-02 | P2 | 3.1 | Archive validation | Distribution signing available. | Product → Archive → Validate. | No ITMS-91053 'missing API declaration' warning attributable to RelevaSDK. | — | ☐ |
| REL-03 | P2 | 5.0 | SDK version on the wire | SET-07 endpoint or log. | Inspect a request. | `User-Agent: RelevaSDK-iOS/5.0.0`, `device.sdkVersion: "5.0.0"`, `options.client.version: "5.0.0"`. | — | ✅ Runs 1–12: every /push body carries device.sdkVersion 5.0.0 and options.client.version 5.0.0; the User-Agent header is not visible in the app log and would need a proxy or the server log. |
| REL-04 | P2 | 5.0 | README migration snippets compile | Scratch Swift file in the app. | Paste the README 'Migrating to 5.0.0' before/after samples. | The 'after' samples compile against 5.0.0. | — | ☐ |
| REL-05 | P2 | 3.1.2 | Package resolves with Firebase 11 and 12 | Empty consumer package. | Depend on sdk-swift 5.0.0 plus firebase-ios-sdk pinned to 11.15.x; then to 12.x. | Both graphs resolve. | — | ⚠️ Firebase 12.18.0 resolves and builds with the SDK on Xcode 26 (all runs). Firebase 11 not tried. |

## 5. Run log

### Run 1 — first device session (2026-09-02)

iPhone via Xcode, Debug build, Wi-Fi with APNs apparently blocked. Domain 758 (EU realm), profile rado-ios-spark-0209202614, device BB7A5E46-0D44-43B3-8BB8-21F75DE49D19, session 7fa697ef-2569-4d20-b4df-6ed06b737786.

- Backend accepts the SDK: events land, UA parsed as browser RelevaSDK-iOS / platform unknown, not a bot (SET-04). The first requests got 402 'Domain is disabled' until the domain was switched on; not an SDK issue.
- Tracking core verified: page view with token, product view, custom event, cart create/add/update, checkout with orderId, banner impression and click, NPS submission, inbox GETs.
- Push registration failed before the SDK was involved: iOS never delivered an APNs token, so Messaging.token() never resolved and /appPush/tokens was never called. Suspect network (IPv6 no-route, TCP timeouts in the same log). Retest on cellular.
- Banner external links do nothing in the app: the banner onLinkTap only knows myapp:// URLs; the story handler in ContentView.swift already opens http(s) in Safari. Fix the harness (4 lines) before testing http banners.
- Harness bug 1 (double banner init) did NOT reproduce: exactly one impression per banner. Downgraded to 'watch for it'.
- Post-checkout, every later request still carries the purchased products as the active cart (cartPaid false, cartChanged false). Backend ignores it, payload is misleading. Design question for the CTO: clear on trackCheckoutSuccess, or document setCart(Cart.empty()) after purchase.
- 'Profile Merged' event at 13:59 without the SDK sending mergeProfileIds; the profile also has name/email/phone. Something backend/admin-side merged it. Understand before running ID-04.
- Custom events (trackCustomEvent) increment device.views like screen views do (10→14 across five selectedColor taps). Not wrong, but 'views' is not 'screen views'.
- Product events show 'Product: unknown' because prod_00x IDs are not in the domain's feed. Cosmetic; use feed IDs for nicer timelines.
- Cart custom field size sent as an empty string (app sends size even when none picked). App-side noise.

### Run 2 — reinstall, same profile, banner link fix applied (2026-09-02)

Fresh install (UserDefaults wiped), profile rado-ios-spark-0209202614, new device BD2EA943-C831-4B18-936F-D203ECFF416C, log captured on launch 3 (session 4a42b0e0-…, sessions 3). Same Wi-Fi as run 1.

- Push root cause confirmed: Firebase logged 'Declining request for FCM Token since no APNS Token specified'. iOS never delivered the APNs token (no didRegister, no didFail). Not SDK, app or Firebase; APNs blocked on this network. Firebase send side verified complete (dev + prod APNs auth keys on the Shopping App Swift entry, same project as the domain). Retest on cellular/hotspot before any push row.
- The block named 'Bar Banner' is configured Static / After / #home-content in the admin, and the SDK rendered it exactly so: below the Home content, no close, persistent (BAN-06 pass). No Bar-type block exists yet, so BAN-03/BAN-04 are still not run. Popup close works and records bannerClose.
- Bar and static banners stay on screen after a link tap by design; popups dismiss on link tap (BannerChrome). Question for the CTO whether a 'redirect' bar should dismiss. Banner https link now opens the browser after the HomeView fix (BAN-12 pass).
- Banner shown again with a new impression after a tab switch recreated the Home view (BAN-13 caveat).
- Reinstall behaved as expected: new deviceId, firstSeenAt reset, sessions restarted; cold start minted a new sessionId (ID-02, ID-06 pass). The notification delegate check passed (PUSH-14).
- SDK nit (later downgraded, see run 3): on this launch setCart/setWishlist reported changed:true for an empty cart/wishlist, so the first screen view carried cartChanged/wishlistChanged true. Harmless; not reproduced on later launches.
- 'Subscribed' / 'subscriptionsChanged' events at 14:22:40 have no counterpart in the app log: admin/backend side.
- refreshPushToken is skipped on every foreground because the app never sets pushTokenProvider (TOK-04 needs snippet S8).

### Run 3 — push working after disabling the Firebase app-delegate proxy (2026-09-02)

Same install and profile as run 2 (device BD2EA943-…, sessions 6). Harness change: FirebaseAppDelegateProxyEnabled = NO added to ShoppingAppSwift/Info.plist (the shipping plist; the key had only existed in an orphaned root Info.plist).

- Root cause of the missing APNs token was Firebase's app-delegate proxy swizzling under SwiftUI's @UIApplicationDelegateAdaptor, not the network: with the proxy disabled the token arrived on the first launch. INTEGRATION GUIDE ITEM: the SDK README push section must tell SwiftUI integrators to set FirebaseAppDelegateProxyEnabled=NO and set Messaging.messaging().apnsToken manually (the example app already does the manual part).
- Full push chain verified with an admin test push: APNs token → FCM token → /appPush/tokens 202; delivery on the Home screen with image thumbnail; foreground willPresent tracked as delivered; expanded notification shows the image and the 'Shop now' action; tap → opened, action button → clicked (RELEVA_ACTION_BUTTON, category RELEVA_DYNAMIC); callback GETs returned 200; target=url deep link navigated the app.
- Engagement dedupe: delivered + opened for the same push are collapsed into one callback GET (same URL). Backend-side counting still needs a real campaign (test pushes have no campaign id) and the user-agent question is still open.
- The 'changed: true on every launch' cart nit from run 2 did not recur in runs 3+ (changed: false); it appears only when no cart had been stored yet. Downgraded to cosmetic.
- First registerPushToken attempt on launch fails with 'No APNS token specified' because the app asks Firebase before APNs answers; the retry after didRegister succeeds. Expected ordering, harmless log noise.

### Run 4 — deep-link and inbox test pushes (QA-P1…P7 via the admin Test button) (2026-09-03)

Same install (device BD2EA943-…, sessions 12). All pushes sent with the Test button while the app was in the foreground; no campaigns yet.

- Deep links: target=screen (cart, product/1, checkout, unknown), target=url (external), target=inbox all reached the app through the right SDK path with parameters parsed. SDK side of DL-01..05, DL-07, DL-09, DL-10 is done.
- Two app-side failures, both harness bugs: (1) product/1 → 'Product not found' because Firestore ids are prod_001…prod_006 (fixture now says product/prod_001); (2) checkout → SwiftUI 'no matching navigationDestination' → blank screen with a warning icon.
- CRASH in the harness: the second inbox push made InboxView.stripHtml call NSAttributedString(data:options:.html) during a SwiftUI view update → 'AttributeGraph precondition failure: setting value during update' → SIGABRT. Not SDK. Fix: strip tags with the regex fallback only (no HTML importer in body).
- Inbox message detail rendered empty (title + date only). InboxMessageView renders the Unlayer design; if the fixture was authored as html only, nothing is drawn. Check the message in the admin; SDK bug only if a design exists and still renders blank.
- SDK nits: (a) didReceive logs 'Is Releva notification: false' for Releva pushes that have no button (category stays REQUIRE_INTERACTION, only click_action marks them) while willPresent says true; tracking and navigation still ran, so log-only inconsistency. (b) The RELEVA_DYNAMIC action title did not update when the button text changed between pushes ('Shop now' shown for 'Shop now [PUSH-05]').
- Backend nit: navigate_to_parameters is sent as {"":""} when no key/values are configured; harmless.
- PUSH-06 evidence: an untapped foreground delivery fires its callback alone after ~30 s.
- Inbox device side verified: list, unread dot, open → read 202, delete 204, inbox_sync handled on a visible push.

### Fixes applied before run 5 (harness + one SDK branch) (2026-09-03)

example-swift working tree (uncommitted) and sdk-swift branch improvement/device-qa-fixes (one commit per fix). The app now consumes the SDK as a LOCAL package (../sdk-swift) so SDK changes show up on the phone; switch back to the GitHub package before the client handover.

- Harness: InboxView.stripHtml no longer uses the NSAttributedString HTML importer (regex + entity decode) → the inbox list crash is gone.
- Harness: checkout and product deep links now switch the tab first and push the navigation path on the next main-actor turn, so SwiftUI finds the String destination (DL-02, DL-03 re-test).
- Harness: InboxMessageDetailView logs the message design keys, body.rows count and the design JSON on open, to diagnose the blank body (INB-11).
- Harness: the launch log lists the Firestore product ids ('Loaded N products (deep-link ids: prod_001, …)'); the product route is myapp://consumer.app/product/<that id>.
- SDK (branch improvement/device-qa-fixes, BannerChrome.swift): popup close button moved inside the safe area (top inset = max(safe area, 12) + 8, trailing 16), enlarged to 36 pt with a 44 pt hit target, a subtle shadow and an accessibility label; bar close button now sits 8 pt inside the bar instead of being offset outside it; all close buttons get the 44 pt hit target. Visual reference: the native Spark app popup X. For the CTO to review before it goes into a release.
- Fixture change: QA-P3 targets product/prod_001; inbox button targets product/prod_003; story slide button targets product/prod_002.

### Run 5 — harness fixes verified, inbox renders, stories (2026-09-03)

Same install (device BD2EA943-…, sessions 13–15), app built against the local SDK branch improvement/device-qa-fixes. Test pushes QA-P3 (old and corrected) and QA-P7; stories and banners on Home.

- Harness fixes hold: no inbox crash (two messages opened and deleted), product deep link with product/prod_001 navigates, launch log lists the Firestore ids.
- Inbox body renders (heading, image, text, button). Two SDK rendering nits: HTML entities in Unlayer text are shown raw ('&rarr;'); nothing else. The earlier blank body in run 4 is not reproducible; treat as fixture timing.
- Stories work end to end: impression, slide views, close, progress bars, X. One SDK bug found and fixed on the branch: duplicate storyImpression after each close because the queue kept every copy of the same story (no dedupe by token).
- 'Fullscreen banner does not load' is the backend suppression working: that showUntilClick popup was clicked in run 2 on this device, so it is not returned again. Use a showAlways copy or a fresh install to see it.
- Popup chrome: the new close X (branch) shows at the top-right inside the safe area; the popup itself was still edge to edge because the SDK ignored popupWidth/borderRadius/popupBackgroundColor from the design. Rewritten on the branch as a centred, design-sized card with a scrolling body only when the content is taller than the screen (matches the web renderer and the native Spark card). Needs a visual re-check.
- Pending engagement events survive a restart (PUSH-09 evidence).

### Run 6 — checkout deep link, inbox click, popup card (2026-09-03)

Same install (sessions 18–19), app on the SDK branch with the popup card + story dedupe. Test pushes QA-P4 and QA-P7; a real add-to-cart and order.

- Checkout deep link now reaches Checkout (DL-03 pass); add to cart auto-synced (CART-02); second order placed (CHK-01).
- Inbox message button → /action 202 + product navigation (INB-11 pass). Fixture note: the inbox button must point to product/prod_003; product/3 showed 'Product not found'.
- HARNESS CRASH #2: 'SwiftUI/NavigationPath.swift:211: Fatal error: attempting to remove 1 items from path with 0 items' when an inbox push arrived while the stack held path-based routes. Cause: ContentView mixed navigationDestination(isPresented:) for Inbox/Settings with path-based pushes in the same NavigationStack. Fix: single AppRoute enum, everything path-based.
- Popup card (SDK branch) renders as a centred rounded card with the X inside (screenshots). Open questions raised by the tester: the overlay dim is faint (the design says rgba(0,0,0,0.1); the native Spark app uses a darker overlay, set it in the banner design's Popup → Overlay background), and a tall image is cut at the card bottom and scrolls (design-driven height, same as web). Decision for the CTO: scroll vs scale-to-fit.
- After a purchase the SDK keeps the purchased items as the active cart until the app sets a new cart; on the next launch the app's empty cart produced 'changed: true' and an empty-cart sync. Reinforces the post-checkout design question.
- 'Fullscreen banner' returned again this run after being suppressed, so its type/reentry was changed in the admin between runs; impressions and bannerClose both recorded.

### Run 7 — cold launch from a plain push (system log) (2026-09-03)

Console.app device log filtered on com.releva.ShoppingAppSwift; app force-quit; QA-P9 plain push via the Test button; tap after ~30 s.

- Cold launch from a notification tap works: process bootstrapped for the response action, SDK initialised, token re-registered (202), engagement callback GET 200 within ~0.5 s of launch, screen views sent (PUSH-04 pass).
- Extension: iOS logs 'Ignoring additional replacement content replies' on every Releva push, i.e. the SDK's notification extension calls contentHandler twice (once via FCM populate, once itself). No user-visible effect; should be fixed in RelevaNotificationServiceExtension.
- Plain push (no image, no button) renders with badge 1 and no actions; categories registered at launch: 4.

### Run 8 — rich-push image formats and failure cases (QA-P10…P15) (2026-09-03)

Same install (sessions 22). Test button, app mostly in the foreground.

- PNG and GIF attachments display; a 404 image and a 45 s image both degrade to text with no crash; picsum random photo differs per send.
- WebP shows text-only: iOS attachments accept only JPEG/PNG/GIF. SDK branch: the extension now transcodes any other format to JPEG before attaching (also covers HEIC/HEIF).
- Category behaviour clarified: pushes the extension processes get RELEVA_DEFAULT (or RELEVA_DYNAMIC with a button); the 'Is Releva notification: false' log on earlier runs came from pushes where the category stayed REQUIRE_INTERACTION. SDK branch: the tap log now tests click_action like willPresent does.
- SDK branch also fixes: the extension replied twice to iOS (now once: Firebase populate only for non-Releva pushes); the stale action label (Set.insert never replaced the existing RELEVA_DYNAMIC category, now removed before insert); Unlayer HTML entities such as &rarr; are decoded in banner/inbox text.
- Fixtures: the Test button cannot send an App-Inbox-only push (no iOS content), so PUSH-11/INB-10 need campaign QA-C4; inbox cold-start (app killed, tap inbox push) is covered by campaign QA-C3 or a QA-P7 test with the app force-quit.

### Run 9 — fixes verified: WebP, single extension reply, cold launches, silent inbox push (2026-09-03)

Rebuilt with SDK branch improvement/device-qa-fixes. Test button pushes; two cold launches from the lock screen; one silent inbox push while in the foreground.

- QA-P12 WebP now displays (EXT-02 pass). System log shows the extension replying once, no 'Ignoring additional replacement content replies' (EXT-06 pass).
- Cold launch from a push works repeatedly; the inbox push on cold start opened its message directly (mark-as-read 202 followed the launch).
- Silent inbox push arrives in the foreground but the harness never forwarded it to the SDK inbox service and tracked a spurious 'opened'. Harness fixed: didReceiveRemoteNotification now calls InboxService.shared.handleSyncSignal() for inbox_sync pushes and tracks nothing. INB-10 (badge/list refresh) to be confirmed on the rebuilt app.
- QA-P1 re-sent with a changed button text: the new label is set in the extension process; confirm on device by long-pressing the notification (PUSH-05).
- SDK/README note: silent inbox pushes need host-app wiring, the SDK cannot see them without the app forwarding didReceiveRemoteNotification.

### Run 10 — campaigns sent; cold-launch redirect does not navigate (2026-09-03)

Campaigns QA-C1…C5 sent from the admin; pushes tapped from the lock screen with the app force-quit (system log).

- Cold launch from a deep-link push lands on Home: the SDK's NotificationCenter post fires before the app registers its observers, so the navigation is lost (DL-08). Warm and background taps were unaffected in earlier runs because the observers already existed.
- SDK branch: NotificationService now keeps the last navigation request (pendingNavigation) and RelevaClient exposes consumePendingNavigation(); the three posts go through one helper. README must tell integrators to drain it after setting up navigation.
- Harness: navigation observers now register in AppState.init and replay the buffered request once registered.
- Correction to run 9: the inbox message did not open by itself on cold start; the mark-as-read followed manual taps. DL-08 was never passing.
- Campaign stats (PUSH-03/06/12, INB-04, STO-08) to be read from the admin once the campaign sends have settled.

### Run 11 — cold-launch redirect fixed; SDK logs visible in Console.app (2026-09-04)

Rebuilt with the SDK branch (pending navigation, os_log). Console.app filter: Subsystem contains 'releva.'.

- Cold launch from QA-P2 opened the Cart tab (DL-08 pass); the SDK handled the tap 20 ms after launch and the harness observers were already registered.
- The deep link was handled twice: once live, once from the replay of the buffered request. Harness now clears the SDK buffer when an observer handles the live post; the replay only covers a request that no observer saw.
- Three screen views without a page token were sent at launch (Cart tab appearing plus the double deep-link handling); expected to drop with the fix above. Harness-side, not SDK.
- SDK debug logging now goes through os_log (subsystem ai.releva.sdk, categories sdk/extension) so device logs can be read in Console.app without Xcode; harness logs under com.releva.ShoppingAppSwift.

### Run 12 — inbox section: push-to-message, list, pagination, mark read, mark all read (2026-09-04)

App in the foreground, many QA-P7 sends; Xcode console.

- QA-P7 tap opened the message directly with inboxMessageId 8 and marked it read (DL-07 pass). Inbox list, pagination (cursor page after 20 messages), pull to refresh, mark read on open and mark all read all pass.
- Every foreground QA-P7 delivery is tracked and its callback fires (batches of 2, 4, 5 events all 200). The inbox_sync flag on the tapped push also triggers a refresh.
- Xcode shows every line twice since the os_log change (stdout and unified log both reach the debugger). Helpers now log only through os_log.
- Main-thread hangs of 0.4–0.7 s at launch with the debugger attached: the harness pretty-prints the inbox design JSON and the SDK logs full request bodies. Debug-only noise, worth trimming before the client sees the sample app.

### Run 13 — badge check and a review of all logs against the open rows (2026-09-04)

No new device session except the badge check; results below come from re-reading runs 1–12 and the build output.

- PUSH-10 badge confirmed on the device.
- Promoted from earlier evidence: ID-09 views counter, CART-04 cart persistence across restart, CART-07 unchanged cart does not sync, REL-01 privacy manifest in the built app, REL-03 SDK version on the wire.
- Caveats added: TOK-04 throttle cannot run in this harness (explicit registration each launch, no pushTokenProvider); BAN-16 dark mode fine, rotation untested; REL-05 Firebase 12 only.
- Everything else still open needs a new device session; see the list in section 5.

### Run 14 — campaign stats, wrong token/realm, profile switch, NPS skip, carousel banner (2026-09-04)

Admin campaign cards for QA-C1…C5; device session with Settings changes.

- Campaign stats: clicks are recorded from the SDK callback (PUSH-03 pass, no User-Agent change needed). But QA-C2, delivered and never tapped, shows 1 click: deliveries count as clicks (PUSH-06 fail, needs an SDK or backend decision).
- Wrong token → 400 surfaced, no retry; wrong realm → DNS failure after 4 attempts, error surfaced. Both without a crash (SET-05, SET-06 pass).
- Profile switch did not re-register the push token: harness bug (AppDelegate cast under SwiftUI is nil) plus no pushTokenProvider. Fixed in the harness; SDK README note.
- Carousel banner (4654): with loop off, the first slide cannot step back and the last cannot step forward (by design); autoplay only if the design enables it. Two SDK fixes on the branch: the tap overlay covered the whole image so image links were unreachable (now only the outer thirds navigate), and a missing/zero image dimension gave a NaN aspect ratio, the likely source of the 24 CoreGraphics 'invalid numeric value' errors in this log.
- Two banners on Home show one after the other with separate impressions (BAN-18 pass). NPS skip sends nothing (NPS-04 partial).

### Run 15 — profile switch vs inbox, airplane mode (2026-09-04)

Settings profile switch and back; airplane mode with a cold launch; Console.app log.

- Profile switch left the previous user's inbox in place with no fetch (INB-12 fail). SDK cache is not profile-scoped and the restored fetch time defeats the stale check. Fixed on the branch; setProfileId now also tells the inbox.
- Offline: cached inbox shown after a cold launch (INB-08 pass); tracking retries then surfaces a clear error, no crash (RES-01 pass).
- Harness: search field now sends trackSearchView on Return (TRK-05 was untestable before).

### Run 16 — rebuild: profile switch, search, carousel, cart (2026-09-04)

Rebuilt with the run-15 fixes; profile switch and back; search with Return; carousel banner 4654; cart add/qty/remove/clear; NPS score 8; Console.app log.

- Inbox now follows the profile: fetch for the new user right after the switch and again on the switch back; cached list still shown in airplane mode (INB-12 pass).
- Search tracking works from the Home field: query and matching product ids in page (TRK-05 pass).
- Push token still not re-bound to the new profile — this time the SDK throttle skipped it ('token unchanged and uploaded recently'). Fixed on the branch: the throttle now also compares the profile of the last upload, and setProfileId calls refreshPushToken when a provider is set (TOK-03 fail → re-test).
- Carousel banner swipes and the outer tap zones step between slides; image link tap and bannerClick 202 → cart (BAN-12). Six CoreGraphics 'invalid numeric value' lines remained while it rendered: the page-style TabView under a bare aspectRatio is measured with no width. Now sized explicitly from the available width; re-check the log after rebuild.
- Cart quantity/remove/clear each synced once with the right payload (CART-03 pass). NPS score 8 submitted (passive branch).

### Run 17 — offline push tap, wishlist, checkout (2026-09-04)

Airplane mode: tap on an inbox push, open the message, tap its button; back online: hearts on two products, cart, order. Old build (token fix not yet installed). Console.app log.

- Offline push tap: opened event kept pending through two failed callback attempts and delivered once the network was back (PUSH-08 pass). Inbox navigation and message rendering worked from the cache.
- Offline tracking: product view, colour event and screen view each retried 3× then failed and were dropped; the inbox button's action POST was dropped silently. Only push engagement is queued offline (RES-01 confirmed, INB-11 caveat).
- Wishlist: two hearts each synced with wishlistChanged true and the product fields (CART-06 add; remove pending).
- Checkout with two products and quantity 3 → cartPaid true, orderId → 200 (CHK-01).
- refreshPushToken still logged the old 'uploaded recently, skipping' text: this log is from the build before the profile-aware throttle fix, so TOK-03 is still open.

### Run 18 — rebuild: token re-bind, rapid cart taps, wishlist remove, carousel (2026-09-04)

Rebuilt with the profile-aware token throttle and carousel sizing; profile switch; five fast Add to Cart taps; hearts on/off; NPS 7; Console.app log.

- Profile switch re-registered the push token for the new profile (TOK-03 pass).
- Carousel banner rendered with no CoreGraphics 'invalid numeric value' lines (fix confirmed).
- Five fast Add to Cart taps → separate payloads with quantity 2, 3, 4, 5 (CART-05 pass). Wishlist add and remove each synced (CART-06 pass).
- Previous user's cart and wishlist carried over to the new profile: harness never reloaded the new user's data; fixed in the harness, README note for integrators (ID-03 caveat).
- After an order the SDK keeps the paid products as its cart until the next setCart, so later screen views send them as an active unpaid cart (CART-08 caveat, CTO decision).

### Run 19 — profile switch with user data reload (2026-09-04)

Rebuilt harness (reloads the Firestore user on a profile switch); hearts on/off as both users; switch 0609 → 0209 → 0609.

- Cart and wishlist now follow the profile: each switch reloaded the user's Firestore data and synced it (cartChanged / wishlistChanged true). Both users happened to like prod_002, so the heart on that card looks unchanged (ID-03 pass).
- Token re-bound to each profile on every switch (TOK-03 confirmed twice more).
- Minor: the cart auto-sync that fires first on a switch still carries the previous wishlist snapshot with wishlistChanged false; the wishlist sync follows within the same second. Harmless.

### Run 20 — banner types: delay, bar top and bottom (2026-09-04)

Block f34a090d-… reconfigured as delay popup, then bar top, then bar bottom; screenshots.

- Delay trigger works: impression 10 s after the screen view (BAN-02 pass).
- Bar banner chrome did not match the web: top bar drew under the status bar with the X on the clock, an extra white frame around the design, smaller X than the popup. Link tap and close were tracked correctly. Reworked on the branch to the web spec: full-width edge-to-edge design, body colour background, status-bar inset, popup-style X, tap on the strip closes (BAN-03/04 caveat, re-test).
- Spec check (magellan-sdk-js render.js): a bar has no dimmed overlay and clicks on the page around it do nothing; only the popup closes on an outside click. Mobile behaviour for outside taps is a product decision.
- Bar and popup carousel showed at the same time (bar above, popup below), each tracked separately.

### Run 21 — bar rework check (2026-09-04)

Rebuilt with the first bar rework; bar top, bar bottom, carousel popup; screenshots.

- Bottom bar looks right (edge to edge, X in the corner, tap on the strip closes). Top bar: the status-bar strip showed the design's white body colour instead of the banner's blue.
- Real finding: overlay banners were drawn inside the modified view, so the SwiftUI navigation bar sat on top of them. The 'Shop' title and the cart button rendered over the bar and the popup and stayed tappable. Fixed on the branch: popup, flyout and bar are hosted in a pass-through window above navigation and tab bars; static banners stay inline.
- Outside-tap question: per the web SDK only the popup closes on an outside click; a bar has no overlay. Kept that way; CTO can decide otherwise.

### Run 22 — overlay window check (2026-09-04)

Rebuilt with the overlay window; bar top, bar bottom, carousel block as a top bar; screenshots.

- Fixed: bar and popup now sit above the navigation and tab bars; the title and cart button no longer draw over them.
- Regression: the overlay window came up in light appearance over the dark app — white status-bar strip and dark status-bar text — and the strip used Unlayer's default body colour. Fixed: the window mirrors the app window's light/dark style, the strip follows the first row/column colour or the system background.
- The 'popup' screenshots were the carousel block configured as a top bar: a portrait design as a bar covers most of the screen, which is what a bar with that content does. The popup itself is unchanged apart from being centred in the whole screen; re-test it.
- Note for CTO: the bottom bar now covers the tab bar (web bottom:0 behaviour). Decide whether phones should keep the tab bar visible.

### Run 23 — popup reference check (2026-09-04)

Reference screenshots: the SDK popup on 2026-09-03 22:51 (card with margins, dim, X inside) and Spark's own native popup. No new device run yet.

- Target look for the popup is the 22:51 card: 16 pt side margins, design corner radius, dim overlay, X inside the card. The window move put the popup's card geometry over the whole screen, so a tall card could reach under the status bar; the card is now centred inside the safe area again while the dim still covers everything.
- Added simulator snapshot tests (BannerOverlaySnapshotTests, opt-in via RLV_SNAPSHOT_DIR) that render the popup, top bar and bottom bar chrome over a fake dark app, so chrome changes can be checked without a device.
- Snapshot found the real popup bug: the card stretched to the full available height (blank card above and below the design) because of a frame(maxHeight:) that grows to the offered height. Fixed; the popup snapshot now matches the reference card. Bars snapshot correctly: coloured strip under the status bar / home indicator, X in the corner.

### Run 24 — popup regressions on the device (2026-09-04)

Tester report on the overlay-window build: bar OK; popup impression at launch without a banner on screen; popup without side margins.

- Bar banners work on the device (BAN-03/04 to confirm with screenshots).
- New bug from the window move: popup impression tracked at cold start with nothing drawn — the window was only created on Home's appear and needs a connected scene. Now also created on scene activation and when the first banner arrives; BannerOverlay log lines added (BAN-01 fail).
- Popup margins: resolved — the screenshots were the carousel block configured as a Bar, which by spec is a full-width strip. The tester confirmed the popup looks right on the device. A bar shows whatever design it carries; a portrait carousel as a bar covers most of the screen (product question, not a rendering bug).
- Popup opened with an empty image area that filled in a split second later: images were loaded only once the card was on screen. Overlay banners now prefetch the design's images (1.5 s cap) before showing and the impression is tracked at that moment; images are cached in memory (commit on the branch, re-test).

### Run 25 — cold start popup not shown (log) (2026-09-04)

Cold start with the image-prefetch build; Console log with the BannerOverlay lines.

- Window created at launch (scene state foregroundInactive), popup queued, impression POSTed, no 'showing window' line: the Home screen had been detached from the overlay window by a spurious onDisappear during launch. Fixed: a live screen re-attaches when a banner arrives; attach/detach now logged.
- Open for CTO: bannerImpression is sent when the SDK queues the banner, not when it is drawn. Every 'queued but hidden' case (detached screen, screen left before display) over-counts.

### Run 26 — cold-start popup confirmed, flyout chrome (2026-09-04)

Rebuilt with the re-attach fix; cold start; block fd4de9a7-… as flyout left/right; Console log with BannerOverlay lines.

- Cold start: popup shown with its image, log shows attach → showing window → impression; close tracked (BAN-01 pass).
- Flyout chrome did not match the web: full-height sheet, dim, X under the status bar. Rebuilt as a bottom-anchored content-sized panel with side margin and no overlay; contract tests added (BAN-05 caveat → re-test).

### Run 27 — flyout sizing (2026-09-04)

Rebuilt with the flyout panel; flyout right with the carousel block; other banner types re-checked by the tester and unaffected.

- Flyout panel was correct in shape but filled the screen width and most of the height on the phone, so it looked like a popup at the bottom. Capped to 72 % width / 60 % height; popup and bars confirmed unaffected by the tester.

### Run 28 — new Flyout block with a 200x600 image (2026-09-04)

New block 'Flyout banner' (addef82d-…, left, placeholder image 200x600); build before the 72 % / 60 % cap.

- Flyout: showing/hiding and bannerClose tracked; panel anchored at the bottom but still 353 pt wide and screen-high because the build predates the size cap (re-test after rebuild).
- Renderer bug: image blocks were stretched to the content width; the web renders them at 'width: 100%; max-width: src.width', so a 200 px image stayed 200 px. Fixed: images capped at their source width, aligned per textAlign, placeholder keeps the source aspect ratio.

## Appendix A. Temp-code snippets

Paste into a `#if DEBUG` block in `Views/Settings/SettingsView.swift` (S0). Replace `HOME_TOKEN` with `5ebbee0e-854a-4620-b654-bad4ca46bda6` and `<token>` with the access token. Delete before committing.

**S0 — Where to paste**

```swift
// Add to Views/Settings/SettingsView.swift inside the Form, Debug only. Do not commit.
#if DEBUG
Section("QA scratch") {
    Button("Run scratch") { Task { await qaScratch() } }
}
#endif

// Helper used by every snippet below
@MainActor func qaClient() -> RelevaClient { AppDelegate.relevaClient! }
```

**S1 — Config presets (SET-09, SET-10)**

```swift
@MainActor func qaScratch() async {
    let c = RelevaClient(realm: "", accessToken: "<token>", config: .trackingOnly())
    // also try .pushOnly(), .minimal(), and
    // RelevaConfig(enableTracking: true, enablePushNotifications: true, enableDebugLogging: true, requestTimeoutInterval: 0)
    c.setDeviceId(UUID().uuidString)
    c.setProfileId("ios-qa-config", true)
    do { try await c.registerPushToken("dummy-fcm-token", deviceType: .ios) } catch { print("QA register:", error) }
    do { _ = try await c.trackScreenView(screenToken: "HOME_TOKEN") } catch { print("QA track:", error) }
}
```

**S2 — Profile merge (ID-04, ID-05)**

```swift
qaClient().setProfileId("ios-qa-merged-C", false)   // skipMerge false = merge previous id
// then open Home twice and read the two request bodies
```

**S3 — App version (ID-10, NPS-08)**

```swift
qaClient().setAppVersion("1.2.3")
```

**S4 — Search (TRK-05..07)**

```swift
do {
    _ = try await qaClient().trackSearchView(query: "shoes", resultProductIds: ["2"], screenToken: "HOME_TOKEN")
    _ = try await qaClient().trackSearchView(query: "shoes",
            filter: SimpleFilter.priceRange(minPrice: 10, maxPrice: 100))
    _ = try await qaClient().trackSearchView(query: "")   // expect missingRequiredField
} catch { print("QA search:", error) }
```

**S5 — Full PushRequest builder (TRK-08, CART-09)**

```swift
let req = PushRequest()
    .screenView("HOME_TOKEN")
    .pageUrl("/home")
    .locale("bg")
    .currency("BGN")
    .pageCategories(["shoes", "sale"])
    .pageProductIds(["1", "2"])
    .pageBlocks(tags: ["hero"])
    .pageFilter(NestedFilter.and(SimpleFilter.brand("Nike"), SimpleFilter.minPrice(20)))
do { _ = try await qaClient().push(req) } catch { print("QA push:", error) }

let cart = Cart(products: [CartProduct(id: "1", price: 10, quantity: 2), CartProduct(id: "2", price: 5, quantity: 1)])
print("QA cart", cart.itemCount, cart.totalQuantity, cart.totalPrice)
```

**S6 — Log the response (TRK-09)**

```swift
do {
    let r = try await qaClient().trackScreenView(screenToken: "HOME_TOKEN")
    print("QA recommenders", r.recommenderCount, "products", r.allProducts.count,
          "meta", r.recommenders.first?.meta as Any,
          "banners", r.banners.count, "stories", r.stories.count, "nps", r.nps != nil)
} catch { print("QA resp:", error) }
```

**S7 — Checkout validation (CHK-03)**

```swift
do { _ = try await qaClient().trackCheckoutSuccess(orderedCart: Cart.paid([], orderId: "x")) }
catch { print("QA empty cart:", error) }        // expect missingRequiredField
do { _ = try await qaClient().trackCheckoutSuccess(orderedCart: Cart.active([CartProduct(id: "1", price: 1, quantity: 1)])) }
catch { print("QA unpaid:", error) }            // expect missingRequiredField
```

**S8 — Push token provider for the 24 h throttle (TOK-04)**

```swift
import FirebaseMessaging
qaClient().pushTokenProvider = { completion in Messaging.messaging().token { t, _ in completion(t) } }
qaClient().refreshPushToken()   // then background/foreground and watch the log
```

**S9 — registerPushToken without deviceId (TOK-06)**

```swift
let c = RelevaClient(realm: "", accessToken: "<token>", config: .debug())
do { try await c.registerPushToken("dummy", deviceType: .ios) } catch { print("QA:", error) }  // missingRequiredField
```

**S10 — NPS custom-event trigger (NPS-06)**

```swift
qaClient().trackEvent("qa_nps")
// second run, within the survey's triggerDelaySeconds:
qaClient().trackEvent("qa_cancel")
```

**S11 — UIKit scratch host (UIK-01..09)**

```swift
import UIKit, SwiftUI, RelevaSDK

final class QAUIKitHost: UIViewController {
    private var banners: BannerPresenter?
    private var nps: NpsPresenter?
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        banners = BannerPresenter(host: self, client: AppDelegate.relevaClient!) { url in print("QA banner link", url) }
        nps = NpsPresenter(host: self,
                           onSubmit: { token, score, comment in
                               Task { try? await AppDelegate.relevaClient?.submitNpsResponse(token: token, score: score, comment: comment) } },
                           onSkip: { print("QA nps skip") })
    }
    override func viewWillAppear(_ a: Bool) {
        super.viewWillAppear(a); banners?.start(); nps?.start()
        Task { _ = try? await AppDelegate.relevaClient?.trackScreenView(screenToken: "HOME_TOKEN") }
    }
    override func viewWillDisappear(_ a: Bool) { super.viewWillDisappear(a); banners?.stop(); nps?.stop() }

    // UIK-08: present a story manually
    func showStory(_ story: StoryResponse) {
        let client = AppDelegate.relevaClient!
        client.storyImpression(story)
        var host: UIHostingController<StoryViewerView>?
        let view = StoryViewerView(story: story, client: client,
                                   onLinkTap: { url in print("QA story link", url) },
                                   onClose: { host?.dismiss(animated: true) })
        host = UIHostingController(rootView: view)
        host!.modalPresentationStyle = .fullScreen
        present(host!, animated: true)
    }
}
// Push it from SwiftUI: NavigationLink("QA UIKit host") { UIKitHostRepresentable() }
struct UIKitHostRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UINavigationController { UINavigationController(rootViewController: QAUIKitHost()) }
    func updateUIViewController(_ vc: UINavigationController, context: Context) {}
}
```

## Appendix B. Endpoint quick reference

| Route | Auth | Success | Writes | Look in |
|---|---|---|---|---|
| POST /api/v0/push | Bearer or URL segment | 200 + response models | CH events (pageView, productView, cart*, wishlist*, custom actions), profiles, devices | Admin profile timeline |
| POST /api/v0/appPush/tokens | Bearer header only | 202 | CH device_app_push_tokens FINAL; event pushNotificationSubscribe | CH query; dashboard subscribers |
| GET <callbackUrl> → /api/v0/click?i=&p= | none (encrypted payload) | 200 {} | event pushNotificationClick + 7-day attribution; dropped for UA unknown/axios and for test pushes | Campaign stats Clicks; timeline |
| POST /api/v0/impressions | Bearer or URL segment | 200 | event bannerImpression (bannerBlockId = block token) | Banner stats |
| POST /api/v0/push/events | Bearer or URL segment | 202 | event with action verbatim; bannerClick/bannerClose and storySlideClick/storyClose set Redis suppression | Banner / story stats; timeline |
| POST /api/v0/nps/:token/submissions | none | 202 / 400 / 404 | event npsSubmission; PG npsSubmissionStates; profile custom nps_* | Admin NPS submissions |
| GET /api/v0/inbox/messages?userId&limit&cursor | Bearer | 200 {messages,nextCursor} | reads PG inboxMessageDeliveries | — |
| GET /api/v0/inbox/unread-count?userId | Bearer | 200 {count} | — | — |
| POST /api/v0/inbox/messages/:id/read | Bearer | 202 / 404 | read=true, readAt; event inboxMessageRead | Campaign stats Inbox reads |
| POST /api/v0/inbox/messages/read-all | Bearer | 202 | bulk read | — |
| DELETE /api/v0/inbox/messages/:id | Bearer | 204 / 404 | status='deleted'; event inboxMessageDelete | — |
| POST /api/v0/inbox/messages/:id/action | Bearer | 202 / 404 | event inboxMessageClick (devicePlatform) | Campaign stats Inbox clicks |

Base URL: `setEndpointOverride` > `config.customEndpoint` > `https://<realm>.releva.ai` > `https://releva.ai`. Headers: `Authorization: Bearer <accessToken>`, `User-Agent: RelevaSDK-iOS/5.0.0`, `X-Platform: iOS`. Retries: `/push` 3, banner/story 2, NPS/inbox 1, fixed 2 s after 5xx, 1 s after transport error. Only 5xx and transport errors retry; 401 → `unauthorized`, other 4xx → `serverError(code, body)`.

## Appendix C. UserDefaults keys (all in `UserDefaults.standard`)

Inspect with Xcode → Devices → download container, or add a Debug button that prints `UserDefaults.standard.dictionaryRepresentation().filter { $0.key.hasPrefix("rlv_") }`. Deleting the app resets everything (new device ID).

| Keys | Meaning |
|---|---|
| `rlv_device_id, rlv_profile_id` | identity |
| `rlv_merge_profile_ids` | pending merge ids; cleared after a successful push |
| `rlv_session_id, rlv_session_timestamp, rlv_device_session_count, rlv_device_first_seen, rlv_device_last_session_ts, rlv_device_views` | sessions and device counters |
| `rlv_cart, rlv_cart_initialized, rlv_wishlist, rlv_wishlist_initialized` | cart/wishlist and the first-set suppression flags |
| `rlv_push_token, rlv_device_type, rlv_push_token_uploaded_at` | push token and the 24 h throttle |
| `rlv_pending_engagement_events` | queued engagement events (7-day expiry) |
| `rlv_inbox_messages, rlv_inbox_unread_count, rlv_inbox_next_cursor, rlv_inbox_last_fetch` | inbox cache |

## Appendix D. Backend verification queries

```sql
-- ClickHouse: everything the device did (profileId is 'profile/<domainId>/<profileId>')
SELECT timestamp, action, sessionId, deviceId, products
FROM events
WHERE domainId = <domainId> AND profileId = 'profile/<domainId>/<profileId>' AND deleted = 0
ORDER BY timestamp DESC LIMIT 100;

-- ClickHouse: push tokens for the device
SELECT * FROM device_app_push_tokens FINAL WHERE domainId = <domainId> AND deviceId = '<deviceId>';

-- ClickHouse: profile + device rows
SELECT * FROM profiles FINAL WHERE domainId = <domainId> AND profileId = 'profile/<domainId>/<profileId>';
SELECT * FROM devices  FINAL WHERE domainId = <domainId> AND deviceId = '<deviceId>';

-- Postgres: inbox and NPS state
SELECT id, "inboxMessageId", read, "readAt", status, "createdAt"
FROM "inboxMessageDeliveries" WHERE "domainId" = <domainId> AND "userId" = '<profileId>' ORDER BY "createdAt" DESC;
SELECT * FROM "npsSubmissionStates" WHERE "domainId" = <domainId> AND "profileId" = '<profileId>';
```

## Appendix E. Debug log glossary

| Log line | Meaning / row |
|---|---|
| `RelevaSDK: Initialized with realm '…'` | Client created (SET-03). |
| `RelevaSDK: Device ID set to '…' (changed: true\|false)` | deviceIdChanged flag for the next push (ID-01/02). |
| `RelevaSDK: Profile ID set to '…' (first time, no merge needed)` | First profile on this install. |
| `RelevaSDK: Profile ID changed to '…' (skip merge = true)` | Logout-style change; merge list cleared (ID-03). |
| `RelevaSDK: Profile ID changed from 'A' to 'B' (merge enabled) / Merge profile IDs stored: […]` | mergeProfileIds will be sent on the next push (ID-04). |
| `RelevaSDK: App version set to '…'` | device.version (ID-10). |
| `RelevaSDK: Cart updated with N products (changed: …) / Cart changes synced to backend / Failed to sync cart changes - …` | setCart and its auto-sync (CART-*). |
| `RelevaSDK: Wishlist updated … / Wishlist changes synced to backend` | setWishlist (CART-06). |
| `RelevaSDK: Sending POST request to <url> / Request body: {…} / Response status code: N` | Every network call; the body line is the payload to inspect. |
| `RelevaSDK: Server error 5xx, retrying... / Request failed, retrying... (N attempts left)` | Retry path (RES-01/02). |
| `RelevaSDK: Failed to decode response: …` | Response model mismatch (RES-08); capture the body. |
| `RelevaSDK: Registering push token for ios... / ✓ Successfully registered push token / ✗ Failed to register push token` | TOK-02. |
| `RelevaSDK: ERROR - Cannot register push token without deviceId` | TOK-06. |
| `RelevaSDK: refreshPushToken skipped - pushTokenProvider not set / - refresh already in flight / - token unchanged and uploaded recently, skipping` | TOK-04. |
| `RelevaSDK: Push engagement tracking enabled` | SDK now owns the notification delegate (PUSH-14). |
| `RelevaSDK: Firing callback URL: … / Callback URL response: N / Callback URL failed: … / Invalid callback URL, skipping` | Engagement GET (PUSH-02..09). |
| `RelevaSDK: Banner impression tracked for <token> / Banner action '<action>' tracked for <token>` | BAN-*. |
| `RelevaSDK: Story action '<action>' tracked for <token>` | STO-*. |
| `RelevaSDK: Endpoint override set to '…' / Endpoint override cleared` | SET-07. |

## Appendix F. Covered by unit tests only (no device row)

- JSONValue accessors, literals and the JSONSerialization bridge (JSONValueTests)
- Filter JSON serialisation for every operator (FilterSerializationTests); wire shape is exercised once on device by TRK-07/08
- PushRequest builder copy semantics and validate() (PushRequestTests, TrackingRequestConversionTests)
- RelevaResponse helpers: getRecommendersByTag/ByToken/ByName, merge, filtered(byTokens:), filtered(byTags:) (RelevaResponseTests, RecommenderResponseTests)
- Session / SessionManager 24-hour model (SessionTests). Not on the wire: only SessionService.getSessionId() is sent
- StorageService key round-trips, clearUserData, clearAllData (StorageServiceTests). clearAllData() wipes the host app's whole UserDefaults domain; never run it on a device you care about
- PrivacyInfo.xcprivacy contents (PrivacyManifestTests); REL-01/02 cover the shipped copy
- DesignRenderer parse helpers: colours, dimensions, insets, HTML stripping (DesignRendererParsingTests). Named CSS colours and 3-digit hex are unsupported
- EngagementStatistics / getPendingEventCount (EngagementTrackingServiceTests)
- NetworkService request construction and base-URL precedence against URLProtocol stubs (NetworkServiceTests, EndpointOverrideTests); SET-06/07 cover it live

## Appendix H. Fixtures to create in the admin (domain 758)

Create these in the admin for domain 758 with exactly these texts: the row ID in the subject/body/button shows up in the SDK log (`Title:` / `Body:` lines), in the notification itself and in the admin timeline, so you never have to guess which fixture fired. Save each push first, then use its Test button (send to the test profile ID) for every device-side row; only the three campaigns need a real send. Images: `placehold.co` prints the row ID on the picture and picks the format from the URL; `https://picsum.photos/800/400` returns a different photo on every request. SAFETY: before starting any campaign, confirm the QA segment contains exactly one profile.

| Kind | Name | Settings | Covers |
|---|---|---|---|
| Segment | QA iOS tester [all campaigns] | Profile filter → profile ID equals `rado-ios-spark-0209202614`. Confirm the count is 1. | C1–C3 |
| Push | QA-P1 [PUSH-01 PUSH-02 PUSH-03 PUSH-05 EXT-01 EXT-03 EXT-07 DL-06] image+button→home | Platforms: iOS. Subject `QA-P1 image + button`. Body `Tap → Home. Hold → image + button [PUSH-05]`. Image `https://placehold.co/800x400/1d4ed8/ffffff/jpg?text=QA-P1+EXT-01+JPG`. Button `Shop now [PUSH-05]`. Target URL `myapp://consumer.app/home`. | PUSH-01..05, EXT-01/03/06/07, DL-06 |
| Push | QA-P2 [DL-01 DL-04 DL-08 DL-09] screen cart | Platforms: iOS. Subject `QA-P2 screen → cart`. Body `Expect the Cart tab. Params promo=SUMMER source=qa [DL-04]`. No image, no button. Target Specific Screen `cart`. Key/values `promo` = `SUMMER`, `source` = `qa`. | DL-01, DL-04, DL-08, DL-09 |
| Push | QA-P3 [DL-02] screen product/prod_001 | Subject `QA-P3 screen → product/prod_001`. Body `Expect product prod_001 detail and a Viewed Product event`. Target Specific Screen `product/prod_001` (Firestore ids are prod_001…prod_006). | DL-02 |
| Push | QA-P4 [DL-03] screen checkout | Subject `QA-P4 screen → checkout`. Body `Expect the Checkout screen`. Target Specific Screen `checkout`. | DL-03 |
| Push | QA-P5 [DL-10] screen unknown | Subject `QA-P5 screen → doesnotexist`. Body `Expect: app opens, stays where it was, no crash`. Target Specific Screen `doesnotexist`. | DL-10 |
| Push | QA-P6 [DL-05] external url | Subject `QA-P6 url → releva.ai`. Body `Expect the browser to open releva.ai`. Target URL `https://releva.ai`. | DL-05 |
| Push | QA-P7 [DL-07 INB-01 INB-04 INB-06 INB-11] push+inbox | Platforms: iOS + App Inbox. Subject `QA-P7 inbox message`. Body `Tap → opens this message in Inbox [DL-07]`. Target Inbox. App Inbox title `QA-P7 [INB-11] message with link`; design: heading `QA-P7 inbox`, image `https://placehold.co/800x400/0b6e7a/ffffff/png?text=QA-P7+INB-11`, text `Tap the button → product 3 + inboxMessageClick`, button `Open product [INB-11]` → `myapp://consumer.app/product/prod_003`. The message MUST be built in the visual (Unlayer) editor: the SDK renders the design JSON, not raw html. | DL-07, INB-01, INB-04..06, INB-11 |
| Push | QA-P8 [PUSH-11 INB-10] silent inbox | Platforms: App Inbox only. App Inbox title `QA-P8 [INB-10] silent sync`; text `Arrived via silent push. Badge should increment without opening Inbox.` No iOS content needed. | PUSH-11, INB-10 |
| Push | QA-P9 [PUSH-01 PUSH-04 PUSH-08 PUSH-09] plain | Subject `QA-P9 plain`. Body `No image, no button. Cold start and offline rows.` Target Main Screen. | PUSH-01 baseline, PUSH-04, PUSH-08, PUSH-09, C2 |
| Push | QA-P10 [EXT-02] png | Subject `QA-P10 png`. Body `Hold → PNG with row id`. Image `https://placehold.co/800x400/15803d/ffffff/png?text=QA-P10+EXT-02+PNG`. | EXT-02 |
| Push | QA-P11 [EXT-02] gif | Subject `QA-P11 gif`. Image `https://placehold.co/800x400/b45309/ffffff/gif?text=QA-P11+EXT-02+GIF`. | EXT-02 |
| Push | QA-P12 [EXT-02] webp | Subject `QA-P12 webp`. Image `https://placehold.co/800x400/7e22ce/ffffff/webp?text=QA-P12+EXT-02+WEBP`. | EXT-02 |
| Push | QA-P13 [EXT-04] broken image | Subject `QA-P13 broken image`. Body `Expect text-only notification, no crash`. Image `https://httpbin.org/status/404`. | EXT-04 |
| Push | QA-P14 [EXT-05] slow image | Subject `QA-P14 slow image`. Body `Expect text-only after ~30 s (extension timeout)`. Image `https://httpbin.org/delay/45`. | EXT-05 |
| Push | QA-P15 [EXT-01 random] random photo | Subject `QA-P15 random photo`. Body `Different picture every send`. Image `https://picsum.photos/800/400`. | EXT-01 variant, PUSH-01 |
| Firebase console | QA-FCM [PUSH-07] non-Releva push | Firebase console → Cloud Messaging → test message to the device FCM token (from the log). Title `QA-FCM PUSH-07`. Send once with the app in foreground (expect NOT shown), once in background (expect shown). | PUSH-07 |
| Campaign | QA-C1 [PUSH-03 PUSH-12] click stats | Simple, one-off, scope marketing, segment `QA iOS tester`, step = QA-P1. Start now. Tap the notification. Then: timeline has `pushNotificationClick`; campaign stats Sent 1 / Delivered 1 / Clicks 1. | PUSH-03, PUSH-12, mismatch 1 |
| Campaign | QA-C2 [PUSH-06] delivered only | Same, step = QA-P9. App in the FOREGROUND, do NOT tap, wait 60 s. If `pushNotificationClick` appears, deliveries are counted as clicks. | PUSH-06 |
| Campaign | QA-C4 [PUSH-11 INB-10] silent inbox | Same segment, step = QA-P8 (App Inbox only). App in the foreground on Home: expect no visible notification, `inbox_sync` handled, inbox badge increments. Repeat with the app in the background. The Test button cannot send this push (no iOS content), hence the campaign. | PUSH-11, INB-10 |
| Campaign | QA-C5 [DL-08 DL-07] inbox cold start | Same segment, step = QA-P7, app force-quit before the send. Tap → app launches straight into the message (route inboxMessageFromPush). | DL-08 inbox variant |
| Campaign | QA-C3 [INB-04 INB-11 PUSH-12] inbox stats | Same, step = QA-P7. Open the message, tap its button. Campaign stats: Inbox sent 1 / reads 1 / clicks 1. | INB-04, INB-11 backend, PUSH-12 |
| Inbox bulk | QA-P7 ×21 [INB-02] | Press 'test inbox message' on QA-P7 twenty-one times so the list paginates (limit 20). | INB-02 |
| Banner | QA-BAN-01 [BAN-01 BAN-12 BAN-13] popup immediately | Home page, Pop-up, trigger immediately, type showUntilClick. Design: heading `QA-BAN-01 popup`, image `https://placehold.co/800x400/1d4ed8/ffffff/png?text=QA-BAN-01+POPUP`, button `Go to cart [BAN-12]` → `myapp://consumer.app/cart`, second button `Open web [BAN-12]` → `https://releva.ai`. | BAN-01, BAN-12, BAN-13 |
| Banner | QA-BAN-02 [BAN-02] popup delay 5s | Copy of BAN-01, trigger delay 5 s, heading `QA-BAN-02 delay 5s`. | BAN-02 |
| Banner | QA-BAN-03 [BAN-03] bar top | Bar, position top, trigger immediately. Design one line: `QA-BAN-03 bar top — tap X → bannerClose`, button `Cart [BAN-12]` → `myapp://consumer.app/cart`. | BAN-03 |
| Banner | QA-BAN-04 [BAN-04] bar bottom | Bar, position bottom, text `QA-BAN-04 bar bottom`. | BAN-04 |
| Banner | QA-BAN-05L / QA-BAN-05R [BAN-05] flyout | Flyout left / Flyout right, heading `QA-BAN-05L flyout left` / `QA-BAN-05R flyout right`, image `https://placehold.co/400x400/0b6e7a/ffffff/png?text=QA-BAN-05`. | BAN-05 |
| Banner | QA-BAN-06x [BAN-06] static ×4 | Static on `#home-content` with Before / Beginning of / End of / Replace; heading `QA-BAN-06 static <strategy>`. (The existing 'Bar Banner' block is already Static/After.) | BAN-06 |
| Banner | QA-BAN-07 [BAN-07] static wrong selector | Static, selector `#other`, heading `QA-BAN-07 must NOT show`. | BAN-07 |
| Banner | QA-BAN-08 [BAN-08] popup scroll 50% | Pop-up, trigger scroll 50 %, heading `QA-BAN-08 scroll 50%`. | BAN-08 |
| Banner | QA-BAN-09C / QA-BAN-09W [BAN-09] cart / wishlist | Pop-up, trigger cart changed / wishlist changed, heading `QA-BAN-09C after cart change` / `QA-BAN-09W after wishlist change`. | BAN-09 |
| Banner | QA-BAN-10 [BAN-10] fullscreen + background | Pop-up, full-screen option, background image `https://picsum.photos/1200/2000`, heading `QA-BAN-10 fullscreen`. | BAN-10 |
| Banner | QA-BAN-11 [BAN-11] white text on dark | Pop-up, body background `#111111`, heading text colour `#ffffff` set on the text element itself: `QA-BAN-11 this text must be white`. | BAN-11 |
| Banner | QA-BAN-14 [BAN-14] showAlways | Copy of BAN-01, type showAlways, heading `QA-BAN-14 returns after close`. | BAN-14 |
| Banner | QA-BAN-15 [BAN-15] sessionInterval 2 | Copy of BAN-01, Session Interval 2, heading `QA-BAN-15 every 2nd session`. | BAN-15 |
| Story | QA-STO-01 [STO-01..05 STO-08] dismiss | Running, trigger immediately, end behaviour dismiss, 3 slides of 3 s: images `https://placehold.co/1080x1920/1d4ed8/ffffff/png?text=QA-STO-01+slide+1` (…+2, …+3); slide 2 has a button `Product [STO-04]` → `myapp://consumer.app/product/prod_002`. | STO-01..05, STO-08 |
| Story | QA-STO-05L [STO-05] loop / QA-STO-05S [STO-05] stayOnLast | Copies with end behaviour loop / stayOnLast; slide text names the behaviour. | STO-05, STO-06 |
| Story | QA-STO-07 [STO-07] no slides | Running story with zero slides: heading only `QA-STO-07 must be skipped`. | STO-07 |
| Story | QA-STO-09 [STO-09] delay 5s | Copy of STO-01 with trigger delay 5 s. | STO-09 |
| NPS | QA-NPS-01 [NPS-01 NPS-02 NPS-03 NPS-05] screenView | Active, platforms iOS, trigger screenView on the Home page, frequency onceEver. Question `QA-NPS-01: how likely… [NPS-02]`. Follow-ups: promoter `Promoter follow-up [score ≥ 9]`, passive `Passive follow-up [7–8]`, detractor `Detractor follow-up [≤ 6]`. Thank-you `Thanks — NPS-02 recorded`. | NPS-01, NPS-02, NPS-03, NPS-05 |
| NPS | QA-NPS-06 [NPS-06] customEvent | Trigger customEvent `qa_nps`, cancelOnEvents `qa_cancel`, delay 5 s. Question `QA-NPS-06 custom event trigger`. | NPS-06 |
| NPS | QA-NPS-07 [NPS-07] sessionCount 2 | Trigger sessionCount min 2. Question `QA-NPS-07 second session`. | NPS-07 |
| NPS | QA-NPS-08 [NPS-08] version/platform gates | One survey with appVersionMin `2.0.0`, one with platforms [android]. Questions `QA-NPS-08 needs app 2.0.0` / `QA-NPS-08 android only, must NOT show`. | NPS-08 |

## Appendix G. Version → rows index

- **1.0**: SET-02, SET-03, SET-04, SET-05, SET-08, SET-09, SET-10, ID-01, ID-02, TRK-01, TRK-02, TRK-03, TRK-04, TRK-05, TRK-06, TRK-07, TRK-08, TRK-09, CART-01, CART-02, CART-03, CART-04, CART-06, CART-07, CART-08, CART-09, CHK-01, CHK-03, CHK-04, TOK-01, TOK-02, TOK-03, TOK-05, TOK-06, TOK-07, TOK-08, PUSH-01, PUSH-02, PUSH-04, PUSH-05, PUSH-06, PUSH-07, PUSH-08, PUSH-09, PUSH-10, PUSH-12, PUSH-14, EXT-01, EXT-02, EXT-03, EXT-04, EXT-05, EXT-06, EXT-07, EXT-08
- **1.0.1**: ID-03, ID-04, ID-05
- **1.0.3**: PUSH-03
- **1.0.4**: BAN-01, BAN-02, BAN-03, BAN-04, BAN-05, BAN-06, BAN-07, BAN-08, BAN-09, BAN-12, BAN-13, BAN-14, BAN-16, BAN-17, BAN-18, BAN-19, BAN-20
- **1.1**: SET-07, ID-10, PUSH-11, PUSH-13, DL-01, DL-02, DL-03, DL-04, DL-05, DL-06, DL-07, DL-08, DL-09, DL-10, STO-01, STO-02, STO-03, STO-04, STO-05, STO-06, STO-07, STO-08, STO-09, NPS-01, NPS-02, NPS-03, NPS-04, NPS-05, NPS-06, NPS-07, NPS-08, NPS-09, NPS-11, NPS-12, INB-01, INB-02, INB-03, INB-04, INB-05, INB-06, INB-07, INB-08, INB-09, INB-10, INB-11, INB-12, INB-13, INB-14
- **1.2**: ID-06, ID-07, ID-08, ID-09, BAN-10, BAN-11, BAN-15
- **2.0**: ID-11, TRK-10, CHK-02
- **3.0**: SET-01, SET-06
- **3.1**: REL-01, REL-02
- **3.1.2**: REL-05
- **4.0**: TRK-08, TRK-09, RES-08
- **4.2**: UIK-01, UIK-02, UIK-03, UIK-04, UIK-05, UIK-06, UIK-07, UIK-08, UIK-09, UIK-10, RES-06
- **5.0**: SET-01, CART-05, TOK-04, NPS-10, INB-07, RES-01, RES-02, RES-03, RES-04, RES-05, RES-06, RES-07, REL-03, REL-04
