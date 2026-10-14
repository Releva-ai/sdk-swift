import Foundation

/// Manages banner trigger logic and lifecycle.
/// Handles trigger types: immediately, delaySeconds, scrollPercentage, cartChanged, wishlistChanged.
public class BannerManagerService {
    /// Tokens of popups and flyouts already shown in the current session, shared by every
    /// instance. `initialize` runs on every push response, so instance state would only remember
    /// one response and a popup the server re-delivers would show on every screen.
    private static var shownOneShotTokens = Set<String>()
    private static let shownOneShotTokensLock = NSLock()

    /// Forgets which popups and flyouts were shown. Called when a new session begins; `dispose()`
    /// and `initialize` leave the memory alone because it belongs to the session, not the instance.
    static func startNewSession() {
        shownOneShotTokensLock.lock()
        defer { shownOneShotTokensLock.unlock() }
        shownOneShotTokens.removeAll()
    }

    private static func wasShownThisSession(_ token: String) -> Bool {
        shownOneShotTokensLock.lock()
        defer { shownOneShotTokensLock.unlock() }
        return shownOneShotTokens.contains(token)
    }

    private static func recordShownThisSession(_ token: String) {
        shownOneShotTokensLock.lock()
        defer { shownOneShotTokensLock.unlock() }
        shownOneShotTokens.insert(token)
    }

    /// Popups and flyouts are shown once per session. Bars and static banners are page content
    /// that a new response is the only way to put back on screen, so they are not remembered.
    static func isOneShot(_ banner: BannerResponse) -> Bool {
        banner.displayType == "popup" || banner.displayType == "flyout"
    }

    private var banners: [BannerResponse] = []
    /// Tokens triggered for the current response, so two trigger paths cannot show one banner twice.
    private var displayedBanners = Set<String>()
    private var delayTimers: [Timer] = []
    private var scrollTimer: Timer?
    private var scrollPercentageProvider: (() -> Int)?

    /// Public initializer
    public init() {}

    /// Initialize with banners from a push response.
    /// Clears the previous response's triggers and sets up triggers for each banner. Popups and
    /// flyouts already shown this session stay suppressed.
    public func initialize(
        newBanners: [BannerResponse],
        scrollPercentageProvider: (() -> Int)? = nil
    ) {
        dispose()

        banners = newBanners
        displayedBanners.removeAll()
        self.scrollPercentageProvider = scrollPercentageProvider

        setupTriggers()
    }

    private func setupTriggers() {
        for banner in banners {
            switch banner.trigger {
            case "immediately":
                triggerBanner(banner)

            case "delaySeconds":
                if let delay = banner.delaySeconds, delay > 0 {
                    let timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(delay), repeats: false) { [weak self] _ in
                        self?.triggerBanner(banner)
                    }
                    delayTimers.append(timer)
                }

            case "scrollPercentage":
                if banner.scrollPercentage != nil, scrollPercentageProvider != nil {
                    setupScrollTrigger(banner)
                }

            case "cartChanged", "wishlistChanged", "leaveIntent":
                // cartChanged/wishlistChanged handled via explicit calls
                // leaveIntent not supported on mobile
                break

            default:
                break
            }
        }
    }

    private func setupScrollTrigger(_ banner: BannerResponse) {
        guard scrollTimer == nil else { return }
        scrollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self,
                  let provider = self.scrollPercentageProvider,
                  let threshold = banner.scrollPercentage else { return }
            let current = provider()
            if current >= threshold && !self.displayedBanners.contains(banner.token) {
                self.triggerBanner(banner)
                self.scrollTimer?.invalidate()
                self.scrollTimer = nil
            }
        }
    }

    /// Call with the page's scroll position (0–100): triggers every pending `scrollPercentage`
    /// banner whose threshold has been reached. Push counterpart of the polled
    /// `scrollPercentageProvider`; `RelevaClient.reportScrollPercentage` calls it.
    public func onScroll(percentage: Int) {
        for banner in banners
        where banner.trigger == "scrollPercentage"
            && (banner.scrollPercentage ?? 0) <= percentage
            && !displayedBanners.contains(banner.token) {
            triggerBanner(banner)
        }
    }

    /// Call when the cart changes to trigger cart-based banners
    public func onCartChanged() {
        banners.filter { $0.trigger == "cartChanged" }.forEach { triggerBanner($0) }
    }

    /// Call when the wishlist changes to trigger wishlist-based banners
    public func onWishlistChanged() {
        banners.filter { $0.trigger == "wishlistChanged" }.forEach { triggerBanner($0) }
    }

    private func triggerBanner(_ banner: BannerResponse) {
        guard !displayedBanners.contains(banner.token) else { return }
        let oneShot = Self.isOneShot(banner)
        guard !(oneShot && Self.wasShownThisSession(banner.token)) else { return }
        displayedBanners.insert(banner.token)
        relevaLog("RelevaSDK: Banner trigger fired: \(banner.token.prefix(8)) (\(banner.trigger ?? "?"))")
        // Recorded only when a display surface was listening, not when it drew it: a popup emitted before any surface
        // subscribed was never shown, so it must not use up its one showing.
        let delivered = BannerDisplayController.shared.showBanner(banner)
        if delivered && oneShot {
            Self.recordShownThisSession(banner.token)
        }
    }

    /// Clean up timers
    public func dispose() {
        delayTimers.forEach { $0.invalidate() }
        delayTimers.removeAll()
        scrollTimer?.invalidate()
        scrollTimer = nil
    }

    deinit {
        dispose()
    }
}
