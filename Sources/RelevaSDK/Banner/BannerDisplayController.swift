import Foundation
import Combine

/// Singleton controller that manages banner display events.
/// Banners are emitted here by BannerManagerService and consumed by BannerDisplayView.
public class BannerDisplayController: ObservableObject {

    /// Shared instance
    public static let shared = BannerDisplayController()

    /// Published banner events
    private let bannerSubject = PassthroughSubject<BannerResponse, Never>()

    /// Publisher for banner events
    public var bannerPublisher: AnyPublisher<BannerResponse, Never> {
        bannerSubject.eraseToAnyPublisher()
    }

    private init() {}

    /// Emit a banner to be displayed
    public func showBanner(_ banner: BannerResponse) {
        bannerSubject.send(banner)
    }
}
