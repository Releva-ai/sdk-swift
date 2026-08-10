import Foundation
@testable import RelevaSDK

/// The case of a thrown error, ignoring any associated message.
///
/// `RelevaError` is not `Equatable` and carries free-text messages, so tests assert on
/// the kind rather than pattern-matching in every assertion or pinning wording.
enum RelevaErrorKind: String {
    case invalidConfiguration
    case networkError
    case invalidResponse
    case missingRequiredField
    case unauthorized
    case serverError
    case unknown

    /// Not a `RelevaError` at all — surfaced as a distinct kind so a mismatch reads clearly.
    case notARelevaError

    init(_ error: Error) {
        guard let relevaError = error as? RelevaError else {
            self = .notARelevaError
            return
        }

        switch relevaError {
        case .invalidConfiguration:
            self = .invalidConfiguration
        case .networkError:
            self = .networkError
        case .invalidResponse:
            self = .invalidResponse
        case .missingRequiredField:
            self = .missingRequiredField
        case .unauthorized:
            self = .unauthorized
        case .serverError:
            self = .serverError
        case .unknown:
            self = .unknown
        }
    }
}
