import Foundation

/// Represents a product associated with a custom event
public struct CustomEventProduct: Codable, Equatable, Hashable {

    // MARK: - Properties

    /// The product ID
    public let id: String

    /// The product quantity (optional)
    public let quantity: Double?

    // MARK: - Initializers

    /// Initialize a custom event product
    /// - Parameters:
    ///   - id: The product ID
    ///   - quantity: The product quantity (optional)
    public init(id: String, quantity: Double? = nil) {
        self.id = id
        self.quantity = quantity
    }

    // MARK: - Serialization

    /// Convert to dictionary for API requests
    public func toDict() -> [String: Any] {
        var dict: [String: Any] = ["id": id]

        if let quantity = quantity {
            dict["quantity"] = quantity
        }

        return dict
    }

    // MARK: - Validation

    /// Validate the custom event product
    /// - Throws: RelevaError if validation fails
    public func validate() throws {
        if id.isEmpty {
            throw RelevaError.missingRequiredField("Product ID cannot be empty")
        }

        if let quantity = quantity, quantity < 0 {
            throw RelevaError.invalidConfiguration("Product quantity cannot be negative")
        }
    }
}

// MARK: - Convenience Methods

extension CustomEventProduct {

    /// Check if the product has a valid quantity
    public var hasQuantity: Bool {
        return quantity != nil && quantity! > 0
    }

    /// Create a new product with updated quantity
    /// - Parameter quantity: The new quantity
    /// - Returns: A new custom event product with the updated quantity
    public func withQuantity(_ quantity: Double?) -> CustomEventProduct {
        return CustomEventProduct(id: self.id, quantity: quantity)
    }
}