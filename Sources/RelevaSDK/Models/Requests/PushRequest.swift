import Foundation

/// Base request builder for API calls using fluent pattern.
///
/// A value type: each builder returns a modified copy, so a chain reads exactly as it did
/// when this was a class. The builders are deliberately **not** `@discardableResult` —
/// with value semantics a discarded result is an edit that was silently dropped, and the
/// missing attribute turns such a call site into a compiler diagnostic instead.
public struct PushRequest: PushRequestConvertible {
    // MARK: - Properties

    /// Page context, serialized under `page`. Holds only strings, string arrays and the
    /// one `blocks` object, so no number's JSON shape passes through `JSONValue` here.
    private var page: [String: JSONValue] = [:]

    /// The page filter, held as the filter rather than as its dictionary so `toDict()`
    /// still hands `NetworkService` the filter's own `toDict()` output verbatim.
    private var filter: AbstractFilter?

    /// The viewed product, serialized under `product`.
    private var product: ViewedProduct?

    /// Custom events, serialized under `events`. An empty list is omitted from the payload.
    private var events: [CustomEvent] = []

    /// Optional cart for checkout success
    public var cart: Cart?

    // MARK: - Initializers

    /// Initialize an empty push request
    public init() {}

    // MARK: - Page Context Methods

    /// Set the screen/page token
    /// - Parameter pageToken: The page identifier token
    /// - Returns: A copy with the token applied
    public func screenView(_ pageToken: String) -> PushRequest {
        setting("token", .string(pageToken))
    }

    /// Set the page URL
    /// - Parameter url: The page URL
    /// - Returns: A copy with the URL applied
    public func pageUrl(_ url: String) -> PushRequest {
        setting("url", .string(url))
    }

    /// Set the locale
    /// - Parameter locale: The locale identifier (e.g., "en_US")
    /// - Returns: A copy with the locale applied
    public func locale(_ locale: String) -> PushRequest {
        setting("locale", .string(locale))
    }

    /// Set the search query
    /// - Parameter query: The search query string
    /// - Returns: A copy with the query applied
    public func search(_ query: String) -> PushRequest {
        setting("query", .string(query))
    }

    /// Set the currency
    /// - Parameter currency: The currency code (e.g., "USD")
    /// - Returns: A copy with the currency applied
    public func currency(_ currency: String) -> PushRequest {
        setting("currency", .string(currency))
    }

    /// Set the product being viewed
    /// - Parameter product: The viewed product
    /// - Returns: A copy with the product applied
    public func productView(_ product: ViewedProduct) -> PushRequest {
        var copy = self
        copy.product = product
        return copy
    }

    /// Set a filter for the page
    /// - Parameter filter: The filter to apply
    /// - Returns: A copy with the filter applied
    public func pageFilter(_ filter: AbstractFilter) -> PushRequest {
        var copy = self
        copy.filter = filter
        return copy
    }

    /// Set product IDs visible on the page (for listing pages)
    /// - Parameter productIds: Array of product IDs
    /// - Returns: A copy with the product IDs applied
    public func pageProductIds(_ productIds: [String]) -> PushRequest {
        setting(
            "ids",
            productIds.isEmpty ? nil : JSONValue.array(productIds.map { JSONValue.string($0) })
        )
    }

    /// Set categories visible on the page
    /// - Parameter categories: Array of category names
    /// - Returns: A copy with the categories applied
    public func pageCategories(_ categories: [String]) -> PushRequest {
        setting(
            "categories",
            categories.isEmpty ? nil : JSONValue.array(categories.map { JSONValue.string($0) })
        )
    }

    /// Set custom events to track user interactions
    /// - Parameter events: Array of custom events
    /// - Returns: A copy with the events applied
    public func customEvents(_ events: [CustomEvent]) -> PushRequest {
        var copy = self
        copy.events = events
        return copy
    }

    /// Set cart explicitly (used for checkout success)
    /// - Parameter cart: The cart to set
    /// - Returns: A copy with the cart applied
    public func setCart(_ cart: Cart) -> PushRequest {
        var copy = self
        copy.cart = cart
        return copy
    }

    // MARK: - Additional Builder Methods

    /// Set page blocks with tags
    /// - Parameter tags: Array of tag strings
    /// - Returns: A copy with the blocks applied
    public func pageBlocks(tags: [String]) -> PushRequest {
        setting("blocks", JSONValue.object(["tags": JSONValue.array(tags.map { JSONValue.string($0) })]))
    }

    // NOTE: a `profile(email:phoneNumber:firstName:lastName:registeredAt:)` builder was removed.
    // The SDK identifies the user solely by profileId (sent as context.profile.id by RelevaClient);
    // contact details and other profile attributes are never accepted or sent from the client.

    /// Add a single custom event
    /// - Parameter event: The custom event to add
    /// - Returns: A copy with the event appended
    public func addCustomEvent(_ event: CustomEvent) -> PushRequest {
        var copy = self
        copy.events.append(event)
        return copy
    }

    // MARK: - PushRequestConvertible

    /// `PushRequest` is already the form the client sends.
    public var pushRequest: PushRequest {
        self
    }

    // MARK: - Serialization

    /// Convert to dictionary for API requests
    public func toDict() -> [String: Any] {
        var page = self.page.anyValue
        if let filter = filter {
            page["filter"] = filter.toDict()
        }

        var request: [String: Any] = ["page": page]

        if let product = product {
            request["product"] = product.toDict()
        }

        if !events.isEmpty {
            request["events"] = events.map { $0.toDict() }
        }

        return request
    }

    // MARK: - Validation

    /// Validate the request
    ///
    /// Only the cart is checked: `toDict()` omits an empty `events` list rather than
    /// emitting one, so the payload can never carry an empty events array to reject.
    /// - Throws: RelevaError if validation fails
    public func validate() throws {
        if let cart = cart {
            for product in cart.products {
                try product.validate()
            }
        }
    }

    // MARK: - Factory Methods

    /// Create a request for screen view tracking
    /// - Parameter screenToken: The screen identifier
    /// - Returns: A configured PushRequest
    public static func forScreenView(_ screenToken: String) -> PushRequest {
        PushRequest().screenView(screenToken)
    }

    /// Create a request for product view tracking
    /// - Parameters:
    ///   - product: The viewed product
    ///   - screenToken: Optional screen identifier
    /// - Returns: A configured PushRequest
    public static func forProductView(_ product: ViewedProduct, screenToken: String? = nil) -> PushRequest {
        var request = PushRequest().productView(product)
        if let token = screenToken {
            request = request.screenView(token)
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
        var request = PushRequest().search(query)

        if !resultProductIds.isEmpty {
            request = request.pageProductIds(resultProductIds)
        }

        if let token = screenToken {
            request = request.screenView(token)
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
        var request = PushRequest().setCart(orderedCart)

        if let token = screenToken {
            request = request.screenView(token)
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
        var request = PushRequest().customEvents([event])

        if let token = screenToken {
            request = request.screenView(token)
        }

        return request
    }

    // MARK: - Private

    /// Return a copy with `key` set under `page`, or removed from it when `value` is nil.
    private func setting(_ key: String, _ value: JSONValue?) -> PushRequest {
        var copy = self
        copy.page[key] = value
        return copy
    }
}
