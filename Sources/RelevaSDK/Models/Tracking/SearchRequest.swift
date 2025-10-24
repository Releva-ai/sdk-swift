import Foundation

/// Request for tracking search events
public class SearchRequest: PushRequest {

    // MARK: - Properties

    /// The screen identifier token
    public let screenToken: String?

    /// The search query
    public let query: String?

    /// Product IDs in search results
    public let resultProductIds: [String]?

    /// Filter applied to search
    public let filter: AbstractFilter?

    /// Blocks with tags
    public let blocks: [String: [String]]?

    // MARK: - Initializers

    /// Initialize a search request
    /// - Parameters:
    ///   - screenToken: The screen identifier token
    ///   - query: The search query
    ///   - resultProductIds: Product IDs in search results
    ///   - filter: Filter applied to search
    ///   - blocks: Blocks with tags
    public init(
        screenToken: String? = nil,
        query: String? = nil,
        resultProductIds: [String]? = nil,
        filter: AbstractFilter? = nil,
        blocks: [String: [String]]? = nil
    ) {
        self.screenToken = screenToken
        self.query = query
        self.resultProductIds = resultProductIds
        self.filter = filter
        self.blocks = blocks

        super.init()

        // Apply properties to the base request
        if let token = screenToken {
            self.screenView(token)
        }
        if let searchQuery = query {
            self.search(searchQuery)
        }
        if let ids = resultProductIds, !ids.isEmpty {
            self.pageProductIds(ids)
        }
        if let searchFilter = filter {
            self.pageFilter(searchFilter)
        }
        if let tags = blocks?["tags"], !tags.isEmpty {
            self.pageBlocks(tags: tags)
        }
    }

    // MARK: - Factory Methods

    /// Create a search request for a basic search
    /// - Parameters:
    ///   - query: The search query
    ///   - resultCount: Optional number of results found
    /// - Returns: A configured search request
    public static func basicSearch(
        query: String,
        resultCount: Int? = nil
    ) -> SearchRequest {
        return SearchRequest(
            screenToken: nil,
            query: query
        )
    }

    /// Create a search request with results
    /// - Parameters:
    ///   - query: The search query
    ///   - resultProductIds: Product IDs in search results
    ///   - filter: Optional filter applied
    /// - Returns: A configured search request
    public static func searchWithResults(
        query: String,
        resultProductIds: [String],
        filter: AbstractFilter? = nil
    ) -> SearchRequest {
        return SearchRequest(
            screenToken: nil,
            query: query,
            resultProductIds: resultProductIds,
            filter: filter
        )
    }

    /// Create a search request for an empty search (no results)
    /// - Parameter query: The search query that returned no results
    /// - Returns: A configured search request
    public static func emptySearch(query: String) -> SearchRequest {
        return SearchRequest(
            screenToken: nil,
            query: query,
            resultProductIds: []
        )
    }

    /// Create a search request for a filtered search
    /// - Parameters:
    ///   - query: The search query
    ///   - filter: The filter applied
    ///   - resultProductIds: Product IDs after filtering
    /// - Returns: A configured search request
    public static func filteredSearch(
        query: String,
        filter: AbstractFilter,
        resultProductIds: [String]
    ) -> SearchRequest {
        return SearchRequest(
            screenToken: nil,
            query: query,
            resultProductIds: resultProductIds,
            filter: filter
        )
    }

    /// Create a search request for autocomplete/suggestions
    /// - Parameters:
    ///   - query: The partial search query
    ///   - suggestionProductIds: Product IDs in suggestions
    /// - Returns: A configured search request
    public static func autocomplete(
        query: String,
        suggestionProductIds: [String]
    ) -> SearchRequest {
        return SearchRequest(
            screenToken: nil,
            query: query,
            resultProductIds: suggestionProductIds
        )
    }

    // MARK: - Computed Properties

    /// Check if the search has results
    public var hasResults: Bool {
        return resultProductIds != nil && !resultProductIds!.isEmpty
    }

    /// Get the number of results
    public var resultCount: Int {
        return resultProductIds?.count ?? 0
    }

    /// Check if a filter is applied
    public var hasFilter: Bool {
        return filter != nil
    }

    // MARK: - Copy Method

    /// Create a copy with updated values
    /// - Parameters:
    ///   - screenToken: New screen token
    ///   - query: New search query
    ///   - resultProductIds: New result product IDs
    ///   - filter: New filter
    ///   - blocks: New blocks
    /// - Returns: A new search request with updated values
    public func copyWith(
        screenToken: String? = nil,
        query: String? = nil,
        resultProductIds: [String]? = nil,
        filter: AbstractFilter? = nil,
        blocks: [String: [String]]? = nil
    ) -> SearchRequest {
        return SearchRequest(
            screenToken: screenToken ?? self.screenToken,
            query: query ?? self.query,
            resultProductIds: resultProductIds ?? self.resultProductIds,
            filter: filter ?? self.filter,
            blocks: blocks ?? self.blocks
        )
    }

    // MARK: - Validation

    /// Validate the search request
    /// - Throws: RelevaError if validation fails
    public override func validate() throws {
        try super.validate()

        // Search requests should have at least a query
        if query == nil || query!.isEmpty {
            throw RelevaError.missingRequiredField("Search query cannot be empty")
        }
    }
}