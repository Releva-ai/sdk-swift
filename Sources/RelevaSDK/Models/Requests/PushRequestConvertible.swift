import Foundation

/// Anything `RelevaClient.push(_:)` accepts.
///
/// `PushRequest` is the general, fluently built form. `ScreenViewRequest`, `SearchRequest`
/// and `CheckoutSuccessRequest` are narrower immutable descriptions that convert into one;
/// before 4.0.0 they inherited from `PushRequest` instead, which is what forced it to be a
/// non-final class and therefore kept it from being `Sendable`.
public protocol PushRequestConvertible: Sendable {

    /// The request in the form the client sends.
    var pushRequest: PushRequest { get }

    /// Validate the request
    /// - Throws: RelevaError if validation fails
    func validate() throws
}

extension PushRequestConvertible {

    /// Validates whatever the request converts to.
    ///
    /// `validate()` is a requirement rather than only an extension member so that a type
    /// carrying stricter rules of its own still gets them when the caller holds the
    /// protocol — the dynamic dispatch the `override` in `SearchRequest` and
    /// `CheckoutSuccessRequest` used to provide.
    public func validate() throws {
        try pushRequest.validate()
    }
}
