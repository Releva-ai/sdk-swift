import Foundation

/// Manages banner trigger logic and lifecycle.
/// Handles trigger types: immediately, delaySeconds, scrollPercentage, cartChanged, wishlistChanged.
public class BannerManagerService {

    private var banners: [BannerResponse] = []
    private var displayedBanners = Set<String>()
    private var delayTimers: [Timer] = []
    private var scrollTimer: Timer?
    private var scrollPercentageProvider: (() -> Int)?

    /// Public initializer
    public init() {}

    /// Initialize with banners from a push response.
    /// Clears previous state and sets up triggers for each banner.
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
        displayedBanners.insert(banner.token)
        BannerDisplayController.shared.showBanner(banner)
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
