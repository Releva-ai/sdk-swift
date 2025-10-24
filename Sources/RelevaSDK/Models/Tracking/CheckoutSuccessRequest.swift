import Foundation

/// Request for tracking successful checkout/purchase events
public class CheckoutSuccessRequest: PushRequest {

    // MARK: - Properties

    /// The screen identifier token
    public let screenToken: String?

    /// The cart that was successfully ordered
    public let orderedCart: Cart

    /// User email address
    public let userEmail: String?

    /// User phone number
    public let userPhoneNumber: String?

    /// User first name
    public let userFirstName: String?

    /// User last name
    public let userLastName: String?

    /// User registration date
    public let userRegisteredAt: Date?

    // MARK: - Initializers

    /// Initialize a checkout success request
    /// - Parameters:
    ///   - screenToken: The screen identifier token
    ///   - orderedCart: The cart that was successfully ordered
    ///   - userEmail: User email address
    ///   - userPhoneNumber: User phone number
    ///   - userFirstName: User first name
    ///   - userLastName: User last name
    ///   - userRegisteredAt: User registration date
    public init(
        screenToken: String? = nil,
        orderedCart: Cart,
        userEmail: String? = nil,
        userPhoneNumber: String? = nil,
        userFirstName: String? = nil,
        userLastName: String? = nil,
        userRegisteredAt: Date? = nil
    ) {
        self.screenToken = screenToken
        self.orderedCart = orderedCart
        self.userEmail = userEmail
        self.userPhoneNumber = userPhoneNumber
        self.userFirstName = userFirstName
        self.userLastName = userLastName
        self.userRegisteredAt = userRegisteredAt

        super.init()

        // Set the cart on the base request
        self.setCart(orderedCart)

        // Apply screen token if provided
        if let token = screenToken {
            self.screenView(token)
        }

        // Apply profile information
        self.profile(
            email: userEmail,
            phoneNumber: userPhoneNumber,
            firstName: userFirstName,
            lastName: userLastName,
            registeredAt: userRegisteredAt
        )
    }

    // MARK: - Factory Methods

    /// Create a checkout success request with minimal information
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

    /// Create a checkout success request with user information
    /// - Parameters:
    ///   - orderId: The order ID
    ///   - products: The products that were ordered
    ///   - userEmail: User email address
    ///   - userFirstName: User first name
    ///   - userLastName: User last name
    /// - Returns: A configured checkout success request
    public static func withUserInfo(
        orderId: String,
        products: [CartProduct],
        userEmail: String,
        userFirstName: String? = nil,
        userLastName: String? = nil
    ) -> CheckoutSuccessRequest {
        let orderedCart = Cart.paid(products, orderId: orderId)
        return CheckoutSuccessRequest(
            screenToken: nil,
            orderedCart: orderedCart,
            userEmail: userEmail,
            userFirstName: userFirstName,
            userLastName: userLastName
        )
    }

    /// Create a checkout success request with complete information
    /// - Parameters:
    ///   - orderId: The order ID
    ///   - products: The products that were ordered
    ///   - userEmail: User email address
    ///   - userPhoneNumber: User phone number
    ///   - userFirstName: User first name
    ///   - userLastName: User last name
    ///   - userRegisteredAt: User registration date
    /// - Returns: A configured checkout success request
    public static func complete(
        orderId: String,
        products: [CartProduct],
        userEmail: String,
        userPhoneNumber: String,
        userFirstName: String,
        userLastName: String,
        userRegisteredAt: Date? = nil
    ) -> CheckoutSuccessRequest {
        let orderedCart = Cart.paid(products, orderId: orderId)
        return CheckoutSuccessRequest(
            screenToken: nil,
            orderedCart: orderedCart,
            userEmail: userEmail,
            userPhoneNumber: userPhoneNumber,
            userFirstName: userFirstName,
            userLastName: userLastName,
            userRegisteredAt: userRegisteredAt
        )
    }

    /// Create a checkout success request for a guest checkout
    /// - Parameters:
    ///   - orderId: The order ID
    ///   - products: The products that were ordered
    ///   - guestEmail: Guest email address
    /// - Returns: A configured checkout success request
    public static func guestCheckout(
        orderId: String,
        products: [CartProduct],
        guestEmail: String? = nil
    ) -> CheckoutSuccessRequest {
        let orderedCart = Cart.paid(products, orderId: orderId)
        return CheckoutSuccessRequest(
            screenToken: nil,
            orderedCart: orderedCart,
            userEmail: guestEmail
        )
    }

    // MARK: - Computed Properties

    /// Check if user information is provided
    public var hasUserInfo: Bool {
        return userEmail != nil || userPhoneNumber != nil ||
               userFirstName != nil || userLastName != nil
    }

    /// Check if this is a registered user checkout
    public var isRegisteredUser: Bool {
        return userRegisteredAt != nil
    }

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
    ///   - userEmail: New user email
    ///   - userPhoneNumber: New user phone number
    ///   - userFirstName: New user first name
    ///   - userLastName: New user last name
    ///   - userRegisteredAt: New user registration date
    /// - Returns: A new checkout success request with updated values
    public func copyWith(
        screenToken: String? = nil,
        orderedCart: Cart? = nil,
        userEmail: String? = nil,
        userPhoneNumber: String? = nil,
        userFirstName: String? = nil,
        userLastName: String? = nil,
        userRegisteredAt: Date? = nil
    ) -> CheckoutSuccessRequest {
        return CheckoutSuccessRequest(
            screenToken: screenToken ?? self.screenToken,
            orderedCart: orderedCart ?? self.orderedCart,
            userEmail: userEmail ?? self.userEmail,
            userPhoneNumber: userPhoneNumber ?? self.userPhoneNumber,
            userFirstName: userFirstName ?? self.userFirstName,
            userLastName: userLastName ?? self.userLastName,
            userRegisteredAt: userRegisteredAt ?? self.userRegisteredAt
        )
    }

    // MARK: - Validation

    /// Validate the checkout success request
    /// - Throws: RelevaError if validation fails
    public override func validate() throws {
        try super.validate()

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

        // Validate email format if provided
        if let email = userEmail, !email.isEmpty {
            let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
            let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
            if !emailPredicate.evaluate(with: email) {
                throw RelevaError.invalidConfiguration("Invalid email format")
            }
        }
    }
}