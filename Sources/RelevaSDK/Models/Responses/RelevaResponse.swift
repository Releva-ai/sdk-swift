import Foundation

/// Represents the main API response from Releva
public struct RelevaResponse: Codable, Equatable {

    // MARK: - Properties

    /// List of recommender responses
    public let recommenders: [RecommenderResponse]

    /// Push notification configuration info
    public let push: PushInfo?

    // MARK: - Initializers

    /// Initialize a Releva response
    /// - Parameters:
    ///   - recommenders: List of recommender responses
    ///   - push: Push notification configuration
    public init(
        recommenders: [RecommenderResponse] = [],
        push: PushInfo? = nil
    ) {
        self.recommenders = recommenders
        self.push = push
    }

    // MARK: - Computed Properties

    /// Check if there are any recommenders available
    public var hasRecommenders: Bool {
        return !recommenders.isEmpty
    }

    /// Check if push configuration is available
    public var hasPushInfo: Bool {
        return push != nil
    }

    /// Get total number of recommenders
    public var recommenderCount: Int {
        return recommenders.count
    }

    /// Get all products from all recommenders
    public var allProducts: [ProductRecommendation] {
        return recommenders.flatMap { $0.response }
    }

    /// Get total product count across all recommenders
    public var totalProductCount: Int {
        return recommenders.reduce(0) { $0 + $1.productCount }
    }

    // MARK: - Public Methods

    /// Get recommenders by tag
    /// - Parameter tag: The tag to filter by
    /// - Returns: Recommenders containing the specified tag
    public func getRecommendersByTag(_ tag: String) -> [RecommenderResponse] {
        return recommenders.filter { $0.hasTag(tag) }
    }

    /// Get recommender by token
    /// - Parameter token: The recommender token
    /// - Returns: The recommender with the specified token
    public func getRecommenderByToken(_ token: String) -> RecommenderResponse? {
        return recommenders.first { $0.token == token }
    }

    /// Get recommender by name
    /// - Parameter name: The recommender name
    /// - Returns: The recommender with the specified name
    public func getRecommenderByName(_ name: String) -> RecommenderResponse? {
        return recommenders.first { $0.name == name }
    }

    /// Get all unique product IDs
    /// - Returns: Set of all unique product IDs
    public func getAllProductIds() -> Set<String> {
        var ids = Set<String>()
        recommenders.forEach { recommender in
            ids.formUnion(recommender.productIds)
        }
        return ids
    }

    /// Get all unique tags
    /// - Returns: Set of all unique tags
    public func getAllTags() -> Set<String> {
        var tags = Set<String>()
        recommenders.forEach { recommender in
            if let recommenderTags = recommender.tags {
                tags.formUnion(recommenderTags)
            }
        }
        return tags
    }

    /// Get products by category from all recommenders
    /// - Parameter category: The category to filter by
    /// - Returns: Products in the specified category
    public func getProductsByCategory(_ category: String) -> [ProductRecommendation] {
        return allProducts.filter { $0.categories?.contains(category) ?? false }
    }

    /// Get available products from all recommenders
    /// - Returns: Only available products
    public func getAvailableProducts() -> [ProductRecommendation] {
        return allProducts.filter { $0.available }
    }

    /// Get discounted products from all recommenders
    /// - Returns: Only discounted products
    public func getDiscountedProducts() -> [ProductRecommendation] {
        return allProducts.filter { $0.hasDiscount }
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case recommenders, push
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recommenders = try container.decodeIfPresent([RecommenderResponse].self, forKey: .recommenders) ?? []
        push = try container.decodeIfPresent(PushInfo.self, forKey: .push)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(recommenders, forKey: .recommenders)
        try container.encodeIfPresent(push, forKey: .push)
    }

    // MARK: - Factory Methods

    /// Create from JSON data
    /// - Parameter data: JSON data
    /// - Returns: RelevaResponse instance
    /// - Throws: Decoding error if JSON is invalid
    public static func from(jsonData data: Data) throws -> RelevaResponse {
        let decoder = JSONDecoder()
        return try decoder.decode(RelevaResponse.self, from: data)
    }

    /// Create from JSON string
    /// - Parameter jsonString: JSON string
    /// - Returns: RelevaResponse instance
    /// - Throws: Decoding error if JSON is invalid
    public static func from(jsonString: String) throws -> RelevaResponse {
        guard let data = jsonString.data(using: .utf8) else {
            throw RelevaError.invalidResponse("Invalid JSON string")
        }
        return try from(jsonData: data)
    }

    /// Create an empty response
    /// - Returns: Empty RelevaResponse instance
    public static func empty() -> RelevaResponse {
        return RelevaResponse(recommenders: [], push: nil)
    }
}

/// Push notification configuration info
public struct PushInfo: Codable, Equatable {

    // MARK: - Properties

    /// VAPID public key for web push
    public let vapidPublicKey: String?

    // MARK: - Initializers

    /// Initialize push info
    /// - Parameter vapidPublicKey: VAPID public key
    public init(vapidPublicKey: String? = nil) {
        self.vapidPublicKey = vapidPublicKey
    }

    // MARK: - Computed Properties

    /// Check if VAPID key is available
    public var hasVapidKey: Bool {
        return vapidPublicKey != nil && !vapidPublicKey!.isEmpty
    }

    // MARK: - Serialization

    /// Convert to dictionary for API responses
    public func toDict() -> [String: Any] {
        var dict: [String: Any] = [:]
        if let vapidPublicKey = vapidPublicKey {
            dict["vapidPublicKey"] = vapidPublicKey
        }
        return dict
    }

    // MARK: - Factory Methods

    /// Create from dictionary
    /// - Parameter dict: Dictionary containing push info data
    /// - Returns: PushInfo instance or nil if invalid
    public static func from(dict: [String: Any]) -> PushInfo? {
        let vapidPublicKey = dict["vapidPublicKey"] as? String
        return PushInfo(vapidPublicKey: vapidPublicKey)
    }
}

// MARK: - Response Helpers

extension RelevaResponse {

    /// Merge multiple responses
    /// - Parameter responses: Array of responses to merge
    /// - Returns: Merged response
    public static func merge(_ responses: [RelevaResponse]) -> RelevaResponse {
        let allRecommenders = responses.flatMap { $0.recommenders }
        // Use the first non-nil push info
        let pushInfo = responses.first { $0.push != nil }?.push
        return RelevaResponse(recommenders: allRecommenders, push: pushInfo)
    }

    /// Filter response to only include specific recommender tokens
    /// - Parameter tokens: Set of tokens to include
    /// - Returns: Filtered response
    public func filtered(byTokens tokens: Set<String>) -> RelevaResponse {
        let filteredRecommenders = recommenders.filter { tokens.contains($0.token) }
        return RelevaResponse(recommenders: filteredRecommenders, push: push)
    }

    /// Filter response to only include specific tags
    /// - Parameter tags: Set of tags to include
    /// - Returns: Filtered response
    public func filtered(byTags tags: Set<String>) -> RelevaResponse {
        let filteredRecommenders = recommenders.filter { recommender in
            guard let recommenderTags = recommender.tags else { return false }
            return !Set(recommenderTags).isDisjoint(with: tags)
        }
        return RelevaResponse(recommenders: filteredRecommenders, push: push)
    }
}