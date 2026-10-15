import Foundation
import Combine

/// Singleton controller that manages banner display events.
/// Banners are emitted here by BannerManagerService and consumed by BannerDisplayView.
public class BannerDisplayController: ObservableObject {
    /// Shared instance
    public static let shared = BannerDisplayController()

    /// Published banner events
    private let bannerSubject = PassthroughSubject<BannerResponse, Never>()

    private let subscriberLock = NSLock()
    private var subscriberCount = 0

    /// Publisher for banner events
    public var bannerPublisher: AnyPublisher<BannerResponse, Never> {
        bannerSubject
            .handleEvents(
                receiveSubscription: { [weak self] _ in self?.changeSubscriberCount(by: 1) },
                receiveCancel: { [weak self] in self?.changeSubscriberCount(by: -1) }
            )
            .eraseToAnyPublisher()
    }

    /// Whether any display surface is subscribed to `bannerPublisher`.
    var hasSubscribers: Bool {
        subscriberLock.lock()
        defer { subscriberLock.unlock() }
        return subscriberCount > 0
    }

    private init() {}

    /// Emit a banner to be displayed
    /// - Returns: whether a subscriber received it; `false` when no display surface is subscribed.
    @discardableResult
    public func showBanner(_ banner: BannerResponse) -> Bool {
        let delivered = hasSubscribers
        bannerSubject.send(banner)
        return delivered
    }

    private func changeSubscriberCount(by delta: Int) {
        subscriberLock.lock()
        defer { subscriberLock.unlock() }
        subscriberCount += delta
    }
}
