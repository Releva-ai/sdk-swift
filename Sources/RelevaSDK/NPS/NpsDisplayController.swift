import Foundation
import Combine

/// Singleton controller that manages NPS display events.
/// NPS configs are emitted here by NpsManagerService and consumed by NpsDisplayView.
public class NpsDisplayController: ObservableObject {
    /// Shared instance
    public static let shared = NpsDisplayController()

    /// Published NPS events
    private let npsSubject = PassthroughSubject<NpsConfig, Never>()

    /// Publisher for NPS events
    public var npsPublisher: AnyPublisher<NpsConfig, Never> {
        npsSubject.eraseToAnyPublisher()
    }

    private init() {}

    /// Emit an NPS config to be displayed
    public func showNps(_ config: NpsConfig) {
        npsSubject.send(config)
    }
}
