import Foundation

/// Represents a product being viewed
public struct ViewedProduct: Codable, Equatable {

    // MARK: - Properties

    /// The product ID
    public let id: String

    /// Custom fields for the product
    public let custom: CustomFields

    // MARK: - Initializers

    /// Initialize a viewed product
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
    /// - Returns: A new viewed product with the custom fields
    public func withCustomFields(_ custom: CustomFields) -> ViewedProduct {
        return ViewedProduct(id: id, custom: custom)
    }

    /// Add a string custom field
    /// - Parameters:
    ///   - key: The field key
    ///   - values: The field values
    /// - Returns: A new viewed product with the added field
    public func withStringField(key: String, values: [String]) -> ViewedProduct {
        let newCustom = custom.withStringField(key: key, values: values)
        return ViewedProduct(id: id, custom: newCustom)
    }

    /// Add a numeric custom field
    /// - Parameters:
    ///   - key: The field key
    ///   - values: The field values
    /// - Returns: A new viewed product with the added field
    public func withNumericField(key: String, values: [Double]) -> ViewedProduct {
        let newCustom = custom.withNumericField(key: key, values: values)
        return ViewedProduct(id: id, custom: newCustom)
    }

    /// Add a date custom field
    /// - Parameters:
    ///   - key: The field key
    ///   - values: The field values
    /// - Returns: A new viewed product with the added field
    public func withDateField(key: String, values: [Date]) -> ViewedProduct {
        let newCustom = custom.withDateField(key: key, values: values)
        return ViewedProduct(id: id, custom: newCustom)
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

    /// Validate the viewed product
    /// - Throws: RelevaError if validation fails
    public func validate() throws {
        if id.isEmpty {
            throw RelevaError.missingRequiredField("Product ID cannot be empty")
        }
    }
}