import Foundation

/// Request for tracking successful checkout/purchase events.
///
/// The SDK identifies the user solely by the `profileId` set via
/// `RelevaClient.setProfileId(_:)` (sent as `context.profile.id`). Contact details
/// and other profile attributes are never accepted or sent from the client.
public struct CheckoutSuccessRequest: PushRequestConvertible {

    // MARK: - Properties

    /// The screen identifier token
    public let screenToken: String?

    /// The cart that was successfully ordered
    public let orderedCart: Cart

    // MARK: - Initializers

    /// Initialize a checkout success request
    /// - Parameters:
    ///   - screenToken: The screen identifier token
    ///   - orderedCart: The cart that was successfully ordered
    public init(
        screenToken: String? = nil,
        orderedCart: Cart
    ) {
        self.screenToken = screenToken
        self.orderedCart = orderedCart
    }

    // MARK: - PushRequestConvertible

    public var pushRequest: PushRequest {
        var request = PushRequest().setCart(orderedCart)

        if let token = screenToken {
            request = request.screenView(token)
        }

        // NOTE: no profile attributes are attached. Identity is carried by
        // context.profile.id (set in RelevaClient from the stored profileId).

        return request
    }

    // MARK: - Factory Methods

    /// Create a checkout success request
    /// - Parameters:
    ///   - orderId: The order ID
    ///   - products: The products that were ordered
    /// - Returns: A configured checkout success request
    public static func minimal(
        orderId: String,
        products: [CartProduct]
    ) -> CheckoutSuccessRequest {
        let orderedCart = Cart.paid(products, orderId: orderId)
        return CheckoutSuccessRequest(
            screenToken: nil,
            orderedCart: orderedCart
        )
    }

    // MARK: - Computed Properties

    /// Get the order ID
    public var orderId: String? {
        return orderedCart.orderId
    }

    /// Get the total order value
    public var orderValue: Double {
        return orderedCart.totalPrice
    }

    /// Get the number of items in the order
    public var itemCount: Int {
        return orderedCart.itemCount
    }

    // MARK: - Copy Method

    /// Create a copy with updated values
    /// - Parameters:
    ///   - screenToken: New screen token
    ///   - orderedCart: New ordered cart
    /// - Returns: A new checkout success request with updated values
    public func copyWith(
        screenToken: String? = nil,
        orderedCart: Cart? = nil
    ) -> CheckoutSuccessRequest {
        return CheckoutSuccessRequest(
            screenToken: screenToken ?? self.screenToken,
            orderedCart: orderedCart ?? self.orderedCart
        )
    }

    // MARK: - Validation

    /// Validate the checkout success request
    /// - Throws: RelevaError if validation fails
    public func validate() throws {
        // Inlined from `PushRequest.validate()` rather than delegating to it, so this has to
        // stay in sync with that body by hand. Revisit if it grows a check that isn't
        // cart-specific — this bypasses it.
        for product in orderedCart.products {
            try product.validate()
        }

        // Validate the cart is paid
        if !orderedCart.cartPaid {
            throw RelevaError.invalidConfiguration("Checkout success requires a paid cart")
        }

        // Validate order ID exists
        if orderedCart.orderId == nil || orderedCart.orderId!.isEmpty {
            throw RelevaError.missingRequiredField("Order ID is required for checkout success")
        }

        // Validate cart has products
        if orderedCart.products.isEmpty {
            throw RelevaError.invalidConfiguration("Ordered cart must contain at least one product")
        }
    }
}
