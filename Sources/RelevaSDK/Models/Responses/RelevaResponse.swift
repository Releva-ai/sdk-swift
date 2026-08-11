import Foundation

/// Represents the main API response from Releva
///
/// `Codable` conformance is decode-complete but encode-partial: `init(from:)` decodes all five
/// fields, but `encode(to:)` only writes `recommenders` and `push` — `banners`, `stories` and `nps`
/// are intentionally not re-encoded (see the note on `encode(to:)`). Nothing in this SDK encodes a
/// `RelevaResponse`; if a consumer does (for example to cache one in `UserDefaults` or a file), a
/// `decode → encode → decode` round trip silently drops those three fields.
public struct RelevaResponse: Codable, Equatable, Sendable {
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
        !recommenders.isEmpty
    }

    /// Check if there are any banners available
    public var hasBanners: Bool {
        !banners.isEmpty
    }

    /// Check if there are any stories available
    public var hasStories: Bool {
        !stories.isEmpty
    }

    /// Check if NPS config is available
    public var hasNps: Bool {
        nps != nil
    }

    /// Check if push configuration is available
    public var hasPushInfo: Bool {
        push != nil
    }

    /// Get total number of recommenders
    public var recommenderCount: Int {
        recommenders.count
    }

    /// Get all products from all recommenders
    public var allProducts: [ProductRecommendation] {
        recommenders.flatMap { $0.response }
    }

    /// Get total product count across all recommenders
    public var totalProductCount: Int {
        recommenders.reduce(0) { $0 + $1.productCount }
    }

    // MARK: - Public Methods

    /// Get recommenders by tag
    /// - Parameter tag: The tag to filter by
    /// - Returns: Recommenders containing the specified tag
    public func getRecommendersByTag(_ tag: String) -> [RecommenderResponse] {
        recommenders.filter { $0.hasTag(tag) }
    }

    /// Get recommender by token
    /// - Parameter token: The recommender token
    /// - Returns: The recommender with the specified token
    public func getRecommenderByToken(_ token: String) -> RecommenderResponse? {
        recommenders.first { $0.token == token }
    }

    /// Get recommender by name
    /// - Parameter name: The recommender name
    /// - Returns: The recommender with the specified name
    public func getRecommenderByName(_ name: String) -> RecommenderResponse? {
        recommenders.first { $0.name == name }
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
        allProducts.filter { $0.categories?.contains(category) ?? false }
    }

    /// Get available products from all recommenders
    /// - Returns: Only available products
    public func getAvailableProducts() -> [ProductRecommendation] {
        allProducts.filter { $0.available }
    }

    /// Get discounted products from all recommenders
    /// - Returns: Only discounted products
    public func getDiscountedProducts() -> [ProductRecommendation] {
        allProducts.filter { $0.hasDiscount }
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case recommenders, banners, stories, nps, push
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recommenders = try container.decodeIfPresent([RecommenderResponse].self, forKey: .recommenders) ?? []
        push = try container.decodeIfPresent(PushInfo.self, forKey: .push)

        // Banners, stories and NPS carry open-ended JSON, so they are decoded as `JSONValue` and
        // handed to the same `from(dict:)` factories the rest of the SDK uses.
        banners = RelevaResponse.decodeObjects(container, forKey: .banners, using: BannerResponse.from(dict:))
        stories = RelevaResponse.decodeObjects(container, forKey: .stories, using: StoryResponse.from(dict:))
        let rawNps = try? container.decode(JSONValue.self, forKey: .nps)
        nps = rawNps?.objectValue.map { NpsConfig.from(dict: $0.anyValue) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(recommenders, forKey: .recommenders)
        try container.encodeIfPresent(push, forKey: .push)
        // Banners, stories and NPS are read-only API payloads that this SDK never re-encodes
        // internally, so they are deliberately left out here rather than given `Encodable`
        // conformance purely to round-trip. This is a one-way asymmetry: `init(from:)` above
        // decodes all five fields, but a `decode → encode → decode` cycle on this type drops these
        // three (see the type-level doc comment). If a consumer needs to cache a full response,
        // caching the original response `Data` rather than a re-encoded `RelevaResponse` avoids
        // the loss.
    }

    /// Decode an array of JSON objects under `key` and map each through a `from(dict:)` factory.
    ///
    /// A missing key, an explicit `null` and a value of the wrong shape all yield an empty array,
    /// which is what the `JSONSerialization` pass this replaced did. Within an array of the right
    /// shape, an individual element that is not itself an object is dropped rather than emptying
    /// the whole array — more tolerant than before, where `as? [[String: Any]]` made one bad
    /// element empty out the entire list. Only reachable on a malformed response.
    private static func decodeObjects<T>(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys,
        using make: ([String: Any]) -> T
    ) -> [T] {
        let raw = try? container.decode(JSONValue.self, forKey: key)
        return (raw?.arrayValue ?? []).compactMap { $0.objectValue }.map { make($0.anyValue) }
    }

    // MARK: - Equatable

    public static func == (lhs: RelevaResponse, rhs: RelevaResponse) -> Bool {
        lhs.recommenders == rhs.recommenders
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
        try JSONDecoder().decode(RelevaResponse.self, from: data)
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
        RelevaResponse(recommenders: [], banners: [], stories: [], nps: nil, push: nil)
    }
}

/// Push notification configuration info
public struct PushInfo: Codable, Equatable, Sendable {
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
        !(vapidPublicKey ?? "").isEmpty
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
