import Foundation

/// A nested filter that combines multiple filters with AND/OR operations
public struct NestedFilter: AbstractFilter {

    // MARK: - Properties

    /// The operation to apply to nested filters
    public let operation: NestedFilterOperation

    /// The nested filters
    public let nested: [AbstractFilter]

    // MARK: - Initializers

    /// Initialize a nested filter
    /// - Parameters:
    ///   - operation: The operation to apply (AND/OR)
    ///   - nested: The nested filters
    public init(operation: NestedFilterOperation, nested: [AbstractFilter]) {
        self.operation = operation
        self.nested = nested
    }

    // MARK: - Factory Methods

    /// Create an AND filter (all conditions must match)
    /// - Parameter filters: The filters to combine with AND
    /// - Returns: A nested filter with AND operation
    public static func and(_ filters: [AbstractFilter]) -> NestedFilter {
        return NestedFilter(operation: .and, nested: filters)
    }

    /// Create an AND filter with variadic parameters
    /// - Parameter filters: The filters to combine with AND
    /// - Returns: A nested filter with AND operation
    public static func and(_ filters: AbstractFilter...) -> NestedFilter {
        return NestedFilter(operation: .and, nested: filters)
    }

    /// Create an OR filter (at least one condition must match)
    /// - Parameter filters: The filters to combine with OR
    /// - Returns: A nested filter with OR operation
    public static func or(_ filters: [AbstractFilter]) -> NestedFilter {
        return NestedFilter(operation: .or, nested: filters)
    }

    /// Create an OR filter with variadic parameters
    /// - Parameter filters: The filters to combine with OR
    /// - Returns: A nested filter with OR operation
    public static func or(_ filters: AbstractFilter...) -> NestedFilter {
        return NestedFilter(operation: .or, nested: filters)
    }

    // MARK: - Builder Methods

    /// Add a filter to the nested collection
    /// - Parameter filter: The filter to add
    /// - Returns: A new nested filter with the added filter
    public func adding(_ filter: AbstractFilter) -> NestedFilter {
        var newNested = nested
        newNested.append(filter)
        return NestedFilter(operation: operation, nested: newNested)
    }

    /// Add multiple filters to the nested collection
    /// - Parameter filters: The filters to add
    /// - Returns: A new nested filter with the added filters
    public func adding(_ filters: [AbstractFilter]) -> NestedFilter {
        var newNested = nested
        newNested.append(contentsOf: filters)
        return NestedFilter(operation: operation, nested: newNested)
    }

    // MARK: - Common Filter Combinations

    /// Create a filter for price range AND brand
    /// - Parameters:
    ///   - minPrice: Minimum price
    ///   - maxPrice: Maximum price
    ///   - brand: Brand name
    ///   - action: The filter action
    public static func priceAndBrand(
        minPrice: Double,
        maxPrice: Double,
        brand: String,
        action: FilterAction = .include
    ) -> NestedFilter {
        return .and(
            SimpleFilter.priceRange(minPrice: minPrice, maxPrice: maxPrice, action: action),
            SimpleFilter.brand(brand, action: action)
        )
    }

    /// Create a filter for multiple brands (OR)
    /// - Parameters:
    ///   - brands: Array of brand names
    ///   - action: The filter action
    public static func brands(
        _ brands: [String],
        action: FilterAction = .include
    ) -> NestedFilter {
        let brandFilters = brands.map { SimpleFilter.brand($0, action: action) }
        return .or(brandFilters)
    }

    /// Create a filter for multiple sizes (OR)
    /// - Parameters:
    ///   - sizes: Array of sizes
    ///   - action: The filter action
    public static func sizes(
        _ sizes: [String],
        action: FilterAction = .include
    ) -> NestedFilter {
        let sizeFilters = sizes.map { SimpleFilter.size($0, action: action) }
        return .or(sizeFilters)
    }

    /// Create a filter for multiple colors (OR)
    /// - Parameters:
    ///   - colors: Array of colors
    ///   - action: The filter action
    public static func colors(
        _ colors: [String],
        action: FilterAction = .include
    ) -> NestedFilter {
        let colorFilters = colors.map { SimpleFilter.color($0, action: action) }
        return .or(colorFilters)
    }

    /// Create a filter for price range AND (brand OR category)
    /// - Parameters:
    ///   - minPrice: Minimum price
    ///   - maxPrice: Maximum price
    ///   - brands: Array of brand names (optional)
    ///   - categories: Array of category names (optional)
    public static func priceWithBrandsOrCategories(
        minPrice: Double,
        maxPrice: Double,
        brands: [String] = [],
        categories: [String] = []
    ) -> NestedFilter {
        var filters: [AbstractFilter] = [
            SimpleFilter.priceRange(minPrice: minPrice, maxPrice: maxPrice)
        ]

        var orFilters: [AbstractFilter] = []

        if !brands.isEmpty {
            orFilters.append(contentsOf: brands.map { SimpleFilter.brand($0) })
        }

        if !categories.isEmpty {
            orFilters.append(contentsOf: categories.map { SimpleFilter.category($0) })
        }

        if !orFilters.isEmpty {
            filters.append(NestedFilter.or(orFilters))
        }

        return .and(filters)
    }

    // MARK: - Serialization

    /// Convert to dictionary for API requests
    public func toDict() -> [String: Any] {
        return [
            "operator": operation.value,
            "nested": nested.map { $0.toDict() }
        ]
    }

    // MARK: - Validation

    /// Validate the nested filter
    /// - Throws: RelevaError if validation fails
    public func validate() throws {
        if nested.isEmpty {
            throw RelevaError.invalidConfiguration("Nested filter must contain at least one filter")
        }

        // Validate all nested filters
        for filter in nested {
            if let simpleFilter = filter as? SimpleFilter {
                try simpleFilter.validate()
            } else if let nestedFilter = filter as? NestedFilter {
                try nestedFilter.validate()
            }
        }
    }

    // MARK: - Computed Properties

    /// Get the total number of filters (including nested)
    public var filterCount: Int {
        var count = 0
        for filter in nested {
            if let nestedFilter = filter as? NestedFilter {
                count += nestedFilter.filterCount
            } else {
                count += 1
            }
        }
        return count
    }

    /// Check if the filter is empty
    public var isEmpty: Bool {
        return nested.isEmpty
    }

    /// Get the depth of nesting
    public var depth: Int {
        var maxDepth = 0
        for filter in nested {
            if let nestedFilter = filter as? NestedFilter {
                maxDepth = max(maxDepth, nestedFilter.depth)
            }
        }
        return maxDepth + 1
    }
}

// MARK: - Codable Implementation

extension NestedFilter {

    enum CodingKeys: String, CodingKey {
        case operation = "operator"
        case nested
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let operationString = try container.decode(String.self, forKey: .operation)

        guard let operation = NestedFilterOperation(rawValue: operationString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .operation,
                in: container,
                debugDescription: "Invalid operation: \(operationString)"
            )
        }

        self.operation = operation

        // For decoding nested filters, we'd need a more complex implementation
        // This is a simplified version
        self.nested = []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(operation.value, forKey: .operation)
        // Encoding nested filters would require more complex implementation
    }
}