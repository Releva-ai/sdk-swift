import Foundation

/// Represents a product in the shopping cart
public struct CartProduct: Codable, Equatable, Hashable {

    // MARK: - Properties

    /// The product ID
    public let id: String

    /// The product price
    public let price: Double?

    /// The product quantity
    public let quantity: Double?

    /// Custom fields for the product
    public let custom: CustomFields

    // MARK: - Initializers

    /// Initialize a cart product
    /// - Parameters:
    ///   - id: The product ID
    ///   - price: The product price (optional)
    ///   - quantity: The product quantity (optional)
    ///   - custom: Custom fields for the product
    public init(
        id: String,
        price: Double? = nil,
        quantity: Double? = nil,
        custom: CustomFields = CustomFields()
    ) {
        self.id = id
        self.price = price
        self.quantity = quantity
        self.custom = custom
    }

    // MARK: - Builder Methods

    /// Create a new product with updated price
    /// - Parameter price: The new price
    /// - Returns: A new cart product with the updated price
    public func withPrice(_ price: Double?) -> CartProduct {
        return CartProduct(
            id: self.id,
            price: price,
            quantity: self.quantity,
            custom: self.custom
        )
    }

    /// Create a new product with updated quantity
    /// - Parameter quantity: The new quantity
    /// - Returns: A new cart product with the updated quantity
    public func withQuantity(_ quantity: Double?) -> CartProduct {
        return CartProduct(
            id: self.id,
            price: self.price,
            quantity: quantity,
            custom: self.custom
        )
    }

    /// Create a new product with updated custom fields
    /// - Parameter custom: The new custom fields
    /// - Returns: A new cart product with the updated custom fields
    public func withCustomFields(_ custom: CustomFields) -> CartProduct {
        return CartProduct(
            id: self.id,
            price: self.price,
            quantity: self.quantity,
            custom: custom
        )
    }

    // MARK: - Serialization

    /// Convert to dictionary for API requests
    public func toDict() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "custom": custom.toDict()
        ]

        if let price = price {
            dict["price"] = price
        }

        if let quantity = quantity {
            dict["quantity"] = quantity
        }

        return dict
    }

    // MARK: - Computed Properties

    /// Calculate the total price (price * quantity)
    public var totalPrice: Double {
        let unitPrice = price ?? 0
        let qty = quantity ?? 1
        return unitPrice * qty
    }

    /// Check if the product has a valid price
    public var hasPrice: Bool {
        return price != nil && price! > 0
    }

    /// Check if the product has a valid quantity
    public var hasQuantity: Bool {
        return quantity != nil && quantity! > 0
    }

    // MARK: - Validation

    /// Validate the cart product
    /// - Throws: RelevaError if validation fails
    public func validate() throws {
        if id.isEmpty {
            throw RelevaError.missingRequiredField("Product ID cannot be empty")
        }

        if let price = price, price < 0 {
            throw RelevaError.invalidConfiguration("Product price cannot be negative")
        }

        if let quantity = quantity, quantity < 0 {
            throw RelevaError.invalidConfiguration("Product quantity cannot be negative")
        }
    }
}

// MARK: - Convenience Initializers

extension CartProduct {

    /// Initialize with just an ID
    /// - Parameter id: The product ID
    public init(id: String) {
        self.init(id: id, price: nil, quantity: nil, custom: CustomFields())
    }

    /// Initialize with ID and price
    /// - Parameters:
    ///   - id: The product ID
    ///   - price: The product price
    public init(id: String, price: Double) {
        self.init(id: id, price: price, quantity: nil, custom: CustomFields())
    }

    /// Initialize with ID, price, and quantity
    /// - Parameters:
    ///   - id: The product ID
    ///   - price: The product price
    ///   - quantity: The product quantity
    public init(id: String, price: Double, quantity: Double) {
        self.init(id: id, price: price, quantity: quantity, custom: CustomFields())
    }
}

// MARK: - Comparable

extension CartProduct: Comparable {
    public static func < (lhs: CartProduct, rhs: CartProduct) -> Bool {
        return lhs.id < rhs.id
    }
}