import Foundation

/// Represents a product in the wishlist
public struct WishlistProduct: Codable, Equatable, Hashable {

    // MARK: - Properties

    /// The product ID
    public let id: String

    /// Custom fields for the product
    public let custom: CustomFields

    // MARK: - Initializers

    /// Initialize a wishlist product
    /// - Parameters:
    ///   - id: The product ID
    ///   - custom: Custom fields for the product
    public init(id: String, custom: CustomFields = CustomFields()) {
        self.id = id
        self.custom = custom
    }

    // MARK: - Builder Methods

    /// Add custom fields to the product
    /// - Parameter custom: The custom fields to set
    /// - Returns: A new wishlist product with the custom fields
    public func withCustomFields(_ custom: CustomFields) -> WishlistProduct {
        return WishlistProduct(id: id, custom: custom)
    }

    /// Add a string custom field
    /// - Parameters:
    ///   - key: The field key
    ///   - values: The field values
    /// - Returns: A new wishlist product with the added field
    public func withStringField(key: String, values: [String]) -> WishlistProduct {
        let newCustom = custom.withStringField(key: key, values: values)
        return WishlistProduct(id: id, custom: newCustom)
    }

    /// Add a numeric custom field
    /// - Parameters:
    ///   - key: The field key
    ///   - values: The field values
    /// - Returns: A new wishlist product with the added field
    public func withNumericField(key: String, values: [Double]) -> WishlistProduct {
        let newCustom = custom.withNumericField(key: key, values: values)
        return WishlistProduct(id: id, custom: newCustom)
    }

    /// Add a date custom field
    /// - Parameters:
    ///   - key: The field key
    ///   - values: The field values
    /// - Returns: A new wishlist product with the added field
    public func withDateField(key: String, values: [Date]) -> WishlistProduct {
        let newCustom = custom.withDateField(key: key, values: values)
        return WishlistProduct(id: id, custom: newCustom)
    }

    // MARK: - Serialization

    /// Convert to dictionary for API requests
    public func toDict() -> [String: Any] {
        return [
            "id": id,
            "custom": custom.toDict()
        ]
    }

    // MARK: - Validation

    /// Validate the wishlist product
    /// - Throws: RelevaError if validation fails
    public func validate() throws {
        if id.isEmpty {
            throw RelevaError.missingRequiredField("Product ID cannot be empty")
        }
    }

    // MARK: - Convenience Methods

    /// Check if this product matches another by ID
    /// - Parameter other: The other product to compare
    /// - Returns: True if IDs match
    public func matches(_ other: WishlistProduct) -> Bool {
        return id == other.id
    }

    /// Create from a viewed product
    /// - Parameter viewedProduct: The viewed product
    /// - Returns: A wishlist product
    public static func from(_ viewedProduct: ViewedProduct) -> WishlistProduct {
        return WishlistProduct(id: viewedProduct.id, custom: viewedProduct.custom)
    }

    /// Create from a cart product
    /// - Parameter cartProduct: The cart product
    /// - Returns: A wishlist product
    public static func from(_ cartProduct: CartProduct) -> WishlistProduct {
        return WishlistProduct(id: cartProduct.id, custom: cartProduct.custom)
    }
}

// MARK: - Array Extensions

extension Array where Element == WishlistProduct {

    /// Convert array of wishlist products to dictionary array
    public func toDict() -> [[String: Any]] {
        return map { $0.toDict() }
    }

    /// Get unique product IDs
    public var productIds: [String] {
        return map { $0.id }
    }

    /// Check if contains a product with the given ID
    /// - Parameter productId: The product ID to check
    /// - Returns: True if the array contains a product with the ID
    public func contains(productId: String) -> Bool {
        return contains { $0.id == productId }
    }

    /// Find product by ID
    /// - Parameter productId: The product ID
    /// - Returns: The wishlist product if found
    public func product(withId productId: String) -> WishlistProduct? {
        return first { $0.id == productId }
    }

    /// Remove duplicates based on product ID
    /// - Returns: Array with unique products (keeps first occurrence)
    public func removingDuplicates() -> [WishlistProduct] {
        var seen = Set<String>()
        return filter { product in
            if seen.contains(product.id) {
                return false
            }
            seen.insert(product.id)
            return true
        }
    }
}