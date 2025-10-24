import Foundation

/// Represents a recommender response containing product recommendations
public struct RecommenderResponse: Codable, Equatable {

    // MARK: - Properties

    /// Recommender token identifier
    public let token: String

    /// Recommender name
    public let name: String

    /// Metadata dictionary
    public let meta: [String: Any]?

    /// Associated tags
    public let tags: [String]?

    /// CSS selector for web placement
    public let cssSelector: String?

    /// Display strategy
    public let displayStrategy: String?

    /// Display template
    public let template: Template?

    /// Product recommendations
    public let response: [ProductRecommendation]

    // MARK: - Computed Properties

    /// Check if recommender has products
    public var hasProducts: Bool {
        return !response.isEmpty
    }

    /// Get the number of products
    public var productCount: Int {
        return response.count
    }

    /// Check if recommender has tags
    public var hasTags: Bool {
        return tags != nil && !tags!.isEmpty
    }

    /// Check if recommender has a template
    public var hasTemplate: Bool {
        return template != nil
    }

    /// Get all product IDs
    public var productIds: [String] {
        return response.map { $0.id }
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case token, name, meta, tags
        case cssSelector, displayStrategy, template, response
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        token = try container.decodeIfPresent(String.self, forKey: .token) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""

        // meta is set to nil as [String: Any] cannot be decoded with standard Codable
        // If needed, implement custom decoding using JSONSerialization
        meta = nil

        tags = try container.decodeIfPresent([String].self, forKey: .tags)
        cssSelector = try container.decodeIfPresent(String.self, forKey: .cssSelector)
        displayStrategy = try container.decodeIfPresent(String.self, forKey: .displayStrategy)
        template = try container.decodeIfPresent(Template.self, forKey: .template)

        response = try container.decodeIfPresent([ProductRecommendation].self, forKey: .response) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(token, forKey: .token)
        try container.encode(name, forKey: .name)

        // Note: meta encoding would need special handling for Any types
        try container.encodeIfPresent(tags, forKey: .tags)
        try container.encodeIfPresent(cssSelector, forKey: .cssSelector)
        try container.encodeIfPresent(displayStrategy, forKey: .displayStrategy)
        try container.encodeIfPresent(template, forKey: .template)
        try container.encode(response, forKey: .response)
    }

    // MARK: - Equatable

    public static func == (lhs: RecommenderResponse, rhs: RecommenderResponse) -> Bool {
        return lhs.token == rhs.token && lhs.name == rhs.name
    }

    // MARK: - Public Methods

    /// Filter products by availability
    /// - Returns: Available products only
    public func availableProducts() -> [ProductRecommendation] {
        return response.filter { $0.available }
    }

    /// Check if recommender has a specific tag
    /// - Parameter tag: The tag to check
    /// - Returns: True if the recommender has the tag
    public func hasTag(_ tag: String) -> Bool {
        return tags?.contains(tag) ?? false
    }

    /// Get products matching specific IDs
    /// - Parameter ids: Product IDs to match
    /// - Returns: Matching products
    public func products(withIds ids: [String]) -> [ProductRecommendation] {
        let idSet = Set(ids)
        return response.filter { idSet.contains($0.id) }
    }

    /// Get products in a specific price range
    /// - Parameters:
    ///   - minPrice: Minimum price
    ///   - maxPrice: Maximum price
    /// - Returns: Products within the price range
    public func products(inPriceRange minPrice: Double, maxPrice: Double) -> [ProductRecommendation] {
        return response.filter { product in
            let price = product.bestPrice
            return price >= minPrice && price <= maxPrice
        }
    }

    /// Get products with discounts
    /// - Returns: Products that have discounts
    public func discountedProducts() -> [ProductRecommendation] {
        return response.filter { $0.hasDiscount }
    }

    /// Sort products by a given criteria
    public enum SortCriteria {
        case priceAscending
        case priceDescending
        case nameAscending
        case nameDescending
        case discountHighestFirst
        case newest
        case oldest
    }

    /// Get sorted products
    /// - Parameter criteria: Sort criteria
    /// - Returns: Sorted products
    public func sortedProducts(by criteria: SortCriteria) -> [ProductRecommendation] {
        switch criteria {
        case .priceAscending:
            return response.sorted { $0.price < $1.price }
        case .priceDescending:
            return response.sorted { $0.price > $1.price }
        case .nameAscending:
            return response.sorted { $0.name < $1.name }
        case .nameDescending:
            return response.sorted { $0.name > $1.name }
        case .discountHighestFirst:
            return response.sorted {
                let discount1 = $0.calculatedDiscountPercent ?? 0
                let discount2 = $1.calculatedDiscountPercent ?? 0
                return discount1 > discount2
            }
        case .newest:
            return response.sorted { (p1, p2) in
                guard let date1 = p1.publishedAt, let date2 = p2.publishedAt else { return false }
                return date1 > date2
            }
        case .oldest:
            return response.sorted { (p1, p2) in
                guard let date1 = p1.publishedAt, let date2 = p2.publishedAt else { return false }
                return date1 < date2
            }
        }
    }
}

// MARK: - Array Extensions

extension Array where Element == RecommenderResponse {

    /// Get recommenders by tag
    /// - Parameter tag: The tag to filter by
    /// - Returns: Recommenders containing the specified tag
    public func withTag(_ tag: String) -> [RecommenderResponse] {
        return filter { $0.hasTag(tag) }
    }

    /// Find recommender by token
    /// - Parameter token: The recommender token
    /// - Returns: The recommender with the specified token
    public func withToken(_ token: String) -> RecommenderResponse? {
        return first { $0.token == token }
    }

    /// Find recommender by name
    /// - Parameter name: The recommender name
    /// - Returns: The recommender with the specified name
    public func withName(_ name: String) -> RecommenderResponse? {
        return first { $0.name == name }
    }

    /// Get all unique tags from all recommenders
    /// - Returns: Set of all unique tags
    public var allTags: Set<String> {
        var tags = Set<String>()
        forEach { recommender in
            if let recommenderTags = recommender.tags {
                tags.formUnion(recommenderTags)
            }
        }
        return tags
    }

    /// Get total product count across all recommenders
    /// - Returns: Total number of products
    public var totalProductCount: Int {
        return reduce(0) { $0 + $1.productCount }
    }
}