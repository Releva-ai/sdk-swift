import Foundation

/// Represents the main API response from Releva
public struct RelevaResponse: Codable, Equatable {

    // NOTE: the /api/v0/push response also carries a top-level `userId` (the backend's resolved
    // canonical id). We intentionally do NOT decode or persist it. Identity is client-owned: the SDK
    // always sends its profileId, and under the userId-only contract the backend returns the same id
    // it was given (anonymous->known merges are driven explicitly via setProfileId + mergeProfileIds),
    // so there is nothing to adopt. Wiring it up would be dead code. (The web SDK adopts it only
    // because web has an anonymous email-consolidation flow that the mobile SDKs do not.)

    // MARK: - Properties

    /// List of recommender responses
    public let recommenders: [RecommenderResponse]

    /// List of banner responses
    public let banners: [BannerResponse]

    /// List of story responses
    public let stories: [StoryResponse]

    /// NPS survey configuration (if a server-side trigger fired)
    public let nps: NpsConfig?

    /// Push notification configuration info
    public let push: PushInfo?

    // MARK: - Initializers

    /// Initialize a Releva response
    public init(
        recommenders: [RecommenderResponse] = [],
        banners: [BannerResponse] = [],
        stories: [StoryResponse] = [],
        nps: NpsConfig? = nil,
        push: PushInfo? = nil
    ) {
        self.recommenders = recommenders
        self.banners = banners
        self.stories = stories
        self.nps = nps
        self.push = push
    }

    // MARK: - Computed Properties

    /// Check if there are any recommenders available
    public var hasRecommenders: Bool {
        return !recommenders.isEmpty
    }

    /// Check if there are any banners available
    public var hasBanners: Bool {
        return !banners.isEmpty
    }

    /// Check if there are any stories available
    public var hasStories: Bool {
        return !stories.isEmpty
    }

    /// Check if NPS config is available
    public var hasNps: Bool {
        return nps != nil
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
        case recommenders, banners, stories, nps, push
    }

    /// Codable initializer — only decodes Codable-compatible fields.
    /// Stories and NPS contain [String: Any] and are NOT decoded here.
    /// Always use `from(jsonData:)` or `from(jsonString:)` to get the full response.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recommenders = try container.decodeIfPresent([RecommenderResponse].self, forKey: .recommenders) ?? []
        push = try container.decodeIfPresent(PushInfo.self, forKey: .push)

        banners = RelevaResponse.decodeBanners(from: decoder)

        // Stories and NPS require manual JSON parsing (they contain [String: Any]).
        // They are populated by from(jsonData:) after this initializer returns.
        stories = []
        nps = nil

        // Warn if stories/nps keys are present — caller should use from(jsonData:) instead
        if container.contains(.stories), (try? container.decodeNil(forKey: .stories)) == false {
            print("RelevaSDK Warning: RelevaResponse.init(from:) drops stories data. Use RelevaResponse.from(jsonData:) instead.")
        }
        if container.contains(.nps), (try? container.decodeNil(forKey: .nps)) == false {
            print("RelevaSDK Warning: RelevaResponse.init(from:) drops NPS data. Use RelevaResponse.from(jsonData:) instead.")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(recommenders, forKey: .recommenders)
        try container.encodeIfPresent(push, forKey: .push)
        // Banners, stories, NPS are not re-encoded (they're read-only from API)
    }

    /// Decode banners from raw JSON data since BannerResponse contains [String: Any] fields
    private static func decodeBanners(from decoder: Decoder) -> [BannerResponse] {
        // Try to get the raw JSON data from the decoder's userInfo or re-parse
        // Since JSONDecoder doesn't expose raw data per-key easily, we use a workaround
        // by decoding banners as [[String: AnyCodable]] or raw JSON
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else { return [] }

        // Decode as array of raw JSON dictionaries using a helper
        guard let rawBanners = try? container.decode([RawJSON].self, forKey: .banners) else { return [] }

        return rawBanners.compactMap { raw -> BannerResponse? in
            guard let dict = raw.value as? [String: Any] else { return nil }
            return BannerResponse.from(dict: dict)
        }
    }

    // MARK: - Equatable

    public static func == (lhs: RelevaResponse, rhs: RelevaResponse) -> Bool {
        return lhs.recommenders == rhs.recommenders
            && lhs.push == rhs.push
            && lhs.banners.count == rhs.banners.count
            && lhs.stories.count == rhs.stories.count
            && lhs.nps?.token == rhs.nps?.token
    }

    // MARK: - Factory Methods

    /// Create from JSON data
    /// - Parameter data: JSON data
    /// - Returns: RelevaResponse instance
    /// - Throws: Decoding error if JSON is invalid
    public static func from(jsonData data: Data) throws -> RelevaResponse {
        // Parse banners, stories, and NPS manually from raw JSON (they contain [String: Any])
        var parsedBanners: [BannerResponse] = []
        var parsedStories: [StoryResponse] = []
        var parsedNps: NpsConfig?

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let bannersArray = json["banners"] as? [[String: Any]] {
                parsedBanners = bannersArray.map { BannerResponse.from(dict: $0) }
            }
            if let storiesArray = json["stories"] as? [[String: Any]] {
                parsedStories = storiesArray.map { StoryResponse.from(dict: $0) }
            }
            if let npsDict = json["nps"] as? [String: Any] {
                parsedNps = NpsConfig.from(dict: npsDict)
            }
        }

        // Decode the rest with standard Codable
        let decoder = JSONDecoder()
        let response = try decoder.decode(RelevaResponse.self, from: data)

        return RelevaResponse(
            recommenders: response.recommenders,
            banners: parsedBanners.isEmpty ? response.banners : parsedBanners,
            stories: parsedStories,
            nps: parsedNps,
            push: response.push
        )
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
        return RelevaResponse(recommenders: [], banners: [], stories: [], nps: nil, push: nil)
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
        let allBanners = responses.flatMap { $0.banners }
        let allStories = responses.flatMap { $0.stories }
        let pushInfo = responses.first { $0.push != nil }?.push
        let npsInfo = responses.first { $0.nps != nil }?.nps
        return RelevaResponse(recommenders: allRecommenders, banners: allBanners, stories: allStories, nps: npsInfo, push: pushInfo)
    }

    /// Filter response to only include specific recommender tokens
    /// - Parameter tokens: Set of tokens to include
    /// - Returns: Filtered response
    public func filtered(byTokens tokens: Set<String>) -> RelevaResponse {
        let filteredRecommenders = recommenders.filter { tokens.contains($0.token) }
        return RelevaResponse(recommenders: filteredRecommenders, banners: banners, stories: stories, nps: nps, push: push)
    }

    /// Filter response to only include specific tags
    /// - Parameter tags: Set of tags to include
    /// - Returns: Filtered response
    public func filtered(byTags tags: Set<String>) -> RelevaResponse {
        let filteredRecommenders = recommenders.filter { recommender in
            guard let recommenderTags = recommender.tags else { return false }
            return !Set(recommenderTags).isDisjoint(with: tags)
        }
        return RelevaResponse(recommenders: filteredRecommenders, banners: banners, stories: stories, nps: nps, push: push)
    }
}