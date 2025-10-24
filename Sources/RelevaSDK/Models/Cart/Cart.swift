import Foundation

/// Represents a shopping cart with products
public struct Cart: Codable, Equatable {

    // MARK: - Properties

    /// The products in the cart
    public let products: [CartProduct]

    /// The order ID (for paid carts)
    public let orderId: String?

    /// Whether the cart has been paid
    public let cartPaid: Bool

    // MARK: - Initializers

    /// Initialize an active cart
    /// - Parameter products: The products in the cart
    public init(products: [CartProduct]) {
        self.products = products
        self.orderId = nil
        self.cartPaid = false
    }

    /// Initialize a paid cart
    /// - Parameters:
    ///   - products: The products in the cart
    ///   - orderId: The order ID
    public init(products: [CartProduct], orderId: String) {
        self.products = products
        self.orderId = orderId
        self.cartPaid = true
    }

    // MARK: - Static Factory Methods

    /// Create an active cart
    /// - Parameter products: The products in the cart
    /// - Returns: An active cart instance
    public static func active(_ products: [CartProduct]) -> Cart {
        return Cart(products: products)
    }

    /// Create a paid cart
    /// - Parameters:
    ///   - products: The products in the cart
    ///   - orderId: The order ID
    /// - Returns: A paid cart instance
    public static func paid(_ products: [CartProduct], orderId: String) -> Cart {
        return Cart(products: products, orderId: orderId)
    }

    /// Create an empty cart
    /// - Returns: An empty cart instance
    public static func empty() -> Cart {
        return Cart(products: [])
    }

    // MARK: - Serialization

    /// Convert to dictionary for API requests
    public func toDict() -> [String: Any] {
        var dict: [String: Any] = [
            "products": products.map { $0.toDict() },
            "cartPaid": cartPaid
        ]

        if let orderId = orderId {
            dict["orderId"] = orderId
        }

        return dict
    }

    // MARK: - Computed Properties

    /// Check if the cart is empty
    public var isEmpty: Bool {
        return products.isEmpty
    }

    /// Get the total number of items in the cart
    public var itemCount: Int {
        return products.count
    }

    /// Get the total quantity of all products
    public var totalQuantity: Double {
        return products.reduce(0) { $0 + ($1.quantity ?? 0) }
    }

    /// Get the total price of all products
    public var totalPrice: Double {
        return products.reduce(0) { $0 + (($1.price ?? 0) * ($1.quantity ?? 1)) }
    }

    // MARK: - Utility Methods

    /// Check if cart contains a specific product ID
    /// - Parameter productId: The product ID to check
    /// - Returns: True if the cart contains the product
    public func contains(productId: String) -> Bool {
        return products.contains { $0.id == productId }
    }

    /// Get a product by ID
    /// - Parameter productId: The product ID
    /// - Returns: The product if found
    public func product(withId productId: String) -> CartProduct? {
        return products.first { $0.id == productId }
    }

    /// Create a new cart by adding a product
    /// - Parameter product: The product to add
    /// - Returns: A new cart with the added product
    public func adding(product: CartProduct) -> Cart {
        var newProducts = products
        newProducts.append(product)
        return Cart(products: newProducts)
    }

    /// Create a new cart by removing a product
    /// - Parameter productId: The ID of the product to remove
    /// - Returns: A new cart without the specified product
    public func removing(productId: String) -> Cart {
        let newProducts = products.filter { $0.id != productId }
        return Cart(products: newProducts)
    }

    /// Create a new cart by updating a product
    /// - Parameter product: The updated product
    /// - Returns: A new cart with the updated product
    public func updating(product: CartProduct) -> Cart {
        let newProducts = products.map { $0.id == product.id ? product : $0 }
        return Cart(products: newProducts)
    }
}

// MARK: - Hashable

extension Cart: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(products)
        hasher.combine(orderId)
        hasher.combine(cartPaid)
    }
}