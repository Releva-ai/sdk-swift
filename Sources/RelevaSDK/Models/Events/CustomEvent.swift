import Foundation

/// Represents a custom tracking event
public struct CustomEvent: Codable, Equatable {

    // MARK: - Properties

    /// The event action name
    public let action: String

    /// Products associated with the event
    public let products: [CustomEventProduct]

    /// Tags associated with the event
    public let tags: [String]

    /// Custom fields for the event
    public let custom: CustomFields

    // MARK: - Initializers

    /// Initialize a custom event
    /// - Parameters:
    ///   - action: The event action name
    ///   - products: Products associated with the event
    ///   - tags: Tags associated with the event
    ///   - custom: Custom fields for the event
    public init(
        action: String,
        products: [CustomEventProduct] = [],
        tags: [String] = [],
        custom: CustomFields = CustomFields()
    ) {
        self.action = action
        self.products = products
        self.tags = tags
        self.custom = custom
    }

    // MARK: - Builder Methods

    /// Add a product to the event
    /// - Parameter product: The product to add
    /// - Returns: A new event with the added product
    public func withProduct(_ product: CustomEventProduct) -> CustomEvent {
        var newProducts = products
        newProducts.append(product)
        return CustomEvent(
            action: action,
            products: newProducts,
            tags: tags,
            custom: custom
        )
    }

    /// Add a product by ID to the event
    /// - Parameters:
    ///   - id: The product ID
    ///   - quantity: The product quantity (optional)
    /// - Returns: A new event with the added product
    public func withProduct(id: String, quantity: Double? = nil) -> CustomEvent {
        return withProduct(CustomEventProduct(id: id, quantity: quantity))
    }

    /// Add multiple products to the event
    /// - Parameter products: The products to add
    /// - Returns: A new event with the added products
    public func withProducts(_ products: [CustomEventProduct]) -> CustomEvent {
        var newProducts = self.products
        newProducts.append(contentsOf: products)
        return CustomEvent(
            action: action,
            products: newProducts,
            tags: tags,
            custom: custom
        )
    }

    /// Add a tag to the event
    /// - Parameter tag: The tag to add
    /// - Returns: A new event with the added tag
    public func withTag(_ tag: String) -> CustomEvent {
        var newTags = tags
        newTags.append(tag)
        return CustomEvent(
            action: action,
            products: products,
            tags: newTags,
            custom: custom
        )
    }

    /// Add multiple tags to the event
    /// - Parameter tags: The tags to add
    /// - Returns: A new event with the added tags
    public func withTags(_ tags: [String]) -> CustomEvent {
        var newTags = self.tags
        newTags.append(contentsOf: tags)
        return CustomEvent(
            action: action,
            products: products,
            tags: newTags,
            custom: custom
        )
    }

    /// Set custom fields for the event
    /// - Parameter custom: The custom fields
    /// - Returns: A new event with the custom fields
    public func withCustomFields(_ custom: CustomFields) -> CustomEvent {
        return CustomEvent(
            action: action,
            products: products,
            tags: tags,
            custom: custom
        )
    }

    // MARK: - Serialization

    /// Convert to dictionary for API requests
    public func toDict() -> [String: Any] {
        return [
            "action": action,
            "tags": tags,
            "products": products.map { $0.toDict() },
            "custom": custom.toDict()
        ]
    }

    // MARK: - Validation

    /// Validate the custom event
    /// - Throws: RelevaError if validation fails
    public func validate() throws {
        if action.isEmpty {
            throw RelevaError.missingRequiredField("Event action cannot be empty")
        }

        for product in products {
            try product.validate()
        }
    }

    // MARK: - Computed Properties

    /// Check if the event has products
    public var hasProducts: Bool {
        return !products.isEmpty
    }

    /// Check if the event has tags
    public var hasTags: Bool {
        return !tags.isEmpty
    }

    /// Check if the event has custom fields
    public var hasCustomFields: Bool {
        return !custom.isEmpty
    }

    /// Get product IDs
    public var productIds: [String] {
        return products.map { $0.id }
    }
}

// MARK: - Common Event Actions

extension CustomEvent {

    /// Predefined common event actions
    public struct Actions {
        public static let addToCart = "add_to_cart"
        public static let removeFromCart = "remove_from_cart"
        public static let addToWishlist = "add_to_wishlist"
        public static let removeFromWishlist = "remove_from_wishlist"
        public static let shareProduct = "share_product"
        public static let rateProduct = "rate_product"
        public static let reviewProduct = "review_product"
        public static let compareProducts = "compare_products"
        public static let contactSupport = "contact_support"
        public static let subscribeNewsletter = "subscribe_newsletter"
        public static let downloadApp = "download_app"
        public static let signUp = "sign_up"
        public static let login = "login"
        public static let logout = "logout"
    }
}