import Foundation

/// Base request builder for API calls using fluent pattern
public class PushRequest {

    // MARK: - Properties

    /// The request payload
    private var request: [String: Any]

    /// Optional cart for checkout success
    public var cart: Cart?

    // MARK: - Initializers

    /// Initialize an empty push request
    public init() {
        self.request = ["page": [:]]
    }

    // MARK: - Page Context Methods

    /// Set the screen/page token
    /// - Parameter pageToken: The page identifier token
    /// - Returns: Self for chaining
    @discardableResult
    public func screenView(_ pageToken: String) -> PushRequest {
        var page = request["page"] as? [String: Any] ?? [:]
        page["token"] = pageToken
        request["page"] = page
        return self
    }

    /// Set the page URL
    /// - Parameter url: The page URL
    /// - Returns: Self for chaining
    @discardableResult
    public func pageUrl(_ url: String) -> PushRequest {
        var page = request["page"] as? [String: Any] ?? [:]
        page["url"] = url
        request["page"] = page
        return self
    }

    /// Set the locale
    /// - Parameter locale: The locale identifier (e.g., "en_US")
    /// - Returns: Self for chaining
    @discardableResult
    public func locale(_ locale: String) -> PushRequest {
        var page = request["page"] as? [String: Any] ?? [:]
        page["locale"] = locale
        request["page"] = page
        return self
    }

    /// Set the search query
    /// - Parameter query: The search query string
    /// - Returns: Self for chaining
    @discardableResult
    public func search(_ query: String) -> PushRequest {
        var page = request["page"] as? [String: Any] ?? [:]
        page["query"] = query
        request["page"] = page
        return self
    }

    /// Set the currency
    /// - Parameter currency: The currency code (e.g., "USD")
    /// - Returns: Self for chaining
    @discardableResult
    public func currency(_ currency: String) -> PushRequest {
        var page = request["page"] as? [String: Any] ?? [:]
        page["currency"] = currency
        request["page"] = page
        return self
    }

    /// Set the product being viewed
    /// - Parameter product: The viewed product
    /// - Returns: Self for chaining
    @discardableResult
    public func productView(_ product: ViewedProduct) -> PushRequest {
        request["product"] = product.toDict()
        return self
    }

    /// Set a filter for the page
    /// - Parameter filter: The filter to apply
    /// - Returns: Self for chaining
    @discardableResult
    public func pageFilter(_ filter: AbstractFilter) -> PushRequest {
        var page = request["page"] as? [String: Any] ?? [:]
        page["filter"] = filter.toDict()
        request["page"] = page
        return self
    }

    /// Set product IDs visible on the page (for listing pages)
    /// - Parameter productIds: Array of product IDs
    /// - Returns: Self for chaining
    @discardableResult
    public func pageProductIds(_ productIds: [String]) -> PushRequest {
        var page = request["page"] as? [String: Any] ?? [:]
        page["ids"] = productIds.isEmpty ? nil : productIds
        request["page"] = page
        return self
    }

    /// Set categories visible on the page
    /// - Parameter categories: Array of category names
    /// - Returns: Self for chaining
    @discardableResult
    public func pageCategories(_ categories: [String]) -> PushRequest {
        var page = request["page"] as? [String: Any] ?? [:]
        page["categories"] = categories.isEmpty ? nil : categories
        request["page"] = page
        return self
    }

    /// Set custom events to track user interactions
    /// - Parameter events: Array of custom events
    /// - Returns: Self for chaining
    @discardableResult
    public func customEvents(_ events: [CustomEvent]) -> PushRequest {
        request["events"] = events.isEmpty ? nil : events.map { $0.toDict() }
        return self
    }

    /// Set cart explicitly (used for checkout success)
    /// - Parameter cart: The cart to set
    /// - Returns: Self for chaining
    @discardableResult
    public func setCart(_ cart: Cart) -> PushRequest {
        self.cart = cart
        return self
    }

    // MARK: - Additional Builder Methods

    /// Set page blocks with tags
    /// - Parameter tags: Array of tag strings
    /// - Returns: Self for chaining
    @discardableResult
    public func pageBlocks(tags: [String]) -> PushRequest {
        var page = request["page"] as? [String: Any] ?? [:]
        page["blocks"] = ["tags": tags]
        request["page"] = page
        return self
    }

    /// Set profile information
    /// - Parameters:
    ///   - email: User email
    ///   - phoneNumber: User phone number
    ///   - firstName: User first name
    ///   - lastName: User last name
    ///   - registeredAt: User registration date
    /// - Returns: Self for chaining
    @discardableResult
    public func profile(
        email: String? = nil,
        phoneNumber: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        registeredAt: Date? = nil
    ) -> PushRequest {
        var profileMap: [String: Any] = [:]

        if let email = email { profileMap["email"] = email }
        if let phoneNumber = phoneNumber { profileMap["phoneNumber"] = phoneNumber }
        if let firstName = firstName { profileMap["firstName"] = firstName }
        if let lastName = lastName { profileMap["lastName"] = lastName }
        if let registeredAt = registeredAt {
            profileMap["registeredAt"] = ISO8601DateFormatter().string(from: registeredAt)
        }

        if !profileMap.isEmpty {
            request["profile"] = profileMap
        }

        return self
    }

    /// Add a single custom event
    /// - Parameter event: The custom event to add
    /// - Returns: Self for chaining
    @discardableResult
    public func addCustomEvent(_ event: CustomEvent) -> PushRequest {
        var events = request["events"] as? [[String: Any]] ?? []
        events.append(event.toDict())
        request["events"] = events
        return self
    }

    // MARK: - Serialization

    /// Convert to dictionary for API requests
    public func toDict() -> [String: Any] {
        return request
    }

    // MARK: - Validation

    /// Validate the request
    /// - Throws: RelevaError if validation fails
    public func validate() throws {
        // Validate cart if set
        if let cart = cart {
            for product in cart.products {
                try product.validate()
            }
        }

        // Validate custom events if present
        if let events = request["events"] as? [[String: Any]] {
            // Basic validation that events array is not empty
            if events.isEmpty {
                throw RelevaError.invalidConfiguration("Events array cannot be empty if specified")
            }
        }

        // Validate product if present
        if request["product"] != nil {
            // Product validation would be done by ViewedProduct.validate()
        }
    }

    // MARK: - Factory Methods

    /// Create a request for screen view tracking
    /// - Parameter screenToken: The screen identifier
    /// - Returns: A configured PushRequest
    public static func forScreenView(_ screenToken: String) -> PushRequest {
        return PushRequest().screenView(screenToken)
    }

    /// Create a request for product view tracking
    /// - Parameters:
    ///   - product: The viewed product
    ///   - screenToken: Optional screen identifier
    /// - Returns: A configured PushRequest
    public static func forProductView(_ product: ViewedProduct, screenToken: String? = nil) -> PushRequest {
        let request = PushRequest().productView(product)
        if let token = screenToken {
            request.screenView(token)
        }
        return request
    }

    /// Create a request for search tracking
    /// - Parameters:
    ///   - query: The search query
    ///   - resultProductIds: Product IDs in search results
    ///   - screenToken: Optional screen identifier
    /// - Returns: A configured PushRequest
    public static func forSearch(
        query: String,
        resultProductIds: [String] = [],
        screenToken: String? = nil
    ) -> PushRequest {
        let request = PushRequest().search(query)

        if !resultProductIds.isEmpty {
            request.pageProductIds(resultProductIds)
        }

        if let token = screenToken {
            request.screenView(token)
        }

        return request
    }

    /// Create a request for checkout success tracking
    /// - Parameters:
    ///   - orderedCart: The cart that was ordered
    ///   - screenToken: Optional screen identifier
    /// - Returns: A configured PushRequest
    public static func forCheckoutSuccess(
        orderedCart: Cart,
        screenToken: String? = nil
    ) -> PushRequest {
        let request = PushRequest().setCart(orderedCart)

        if let token = screenToken {
            request.screenView(token)
        }

        return request
    }

    /// Create a request for custom event tracking
    /// - Parameters:
    ///   - event: The custom event to track
    ///   - screenToken: Optional screen identifier
    /// - Returns: A configured PushRequest
    public static func forCustomEvent(
        _ event: CustomEvent,
        screenToken: String? = nil
    ) -> PushRequest {
        let request = PushRequest().customEvents([event])

        if let token = screenToken {
            request.screenView(token)
        }

        return request
    }
}