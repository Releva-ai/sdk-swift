import Foundation

/// A simple filter with a single condition
public struct SimpleFilter: AbstractFilter {

    // MARK: - Properties

    /// The field key to filter on
    public let key: String

    /// The filter operator
    public let `operator`: FilterOperator

    /// The filter value
    public let value: String

    /// The filter action
    public let action: FilterAction

    /// Optional weight for ranking adjustments
    public let weight: Int?

    // MARK: - Initializers

    /// Initialize a simple filter
    /// - Parameters:
    ///   - key: The field key to filter on
    ///   - operator: The filter operator
    ///   - value: The filter value
    ///   - action: The filter action
    ///   - weight: Optional weight for ranking adjustments
    public init(
        key: String,
        operator: FilterOperator,
        value: String,
        action: FilterAction,
        weight: Int? = nil
    ) {
        self.key = key
        self.operator = `operator`
        self.value = value
        self.action = action
        self.weight = weight
    }

    // MARK: - Factory Methods for Standard Fields

    /// Create a filter for standard fields
    /// - Parameters:
    ///   - fieldName: The field name
    ///   - operator: The filter operator
    ///   - value: The filter value
    ///   - action: The filter action
    ///   - weight: Optional weight for ranking adjustments
    public static func standardField(
        fieldName: String,
        operator: FilterOperator,
        value: String,
        action: FilterAction,
        weight: Int? = nil
    ) -> SimpleFilter {
        return SimpleFilter(
            key: fieldName,
            operator: `operator`,
            value: value,
            action: action,
            weight: weight
        )
    }

    /// Create a filter for custom string fields
    /// - Parameters:
    ///   - fieldName: The custom field name
    ///   - operator: The filter operator
    ///   - value: The filter value
    ///   - action: The filter action
    ///   - weight: Optional weight for ranking adjustments
    public static func customString(
        fieldName: String,
        operator: FilterOperator,
        value: String,
        action: FilterAction,
        weight: Int? = nil
    ) -> SimpleFilter {
        return SimpleFilter(
            key: "custom.string.\(fieldName)",
            operator: `operator`,
            value: value,
            action: action,
            weight: weight
        )
    }

    /// Create a filter for custom numeric fields
    /// - Parameters:
    ///   - fieldName: The custom field name
    ///   - operator: The filter operator
    ///   - value: The filter value
    ///   - action: The filter action
    ///   - weight: Optional weight for ranking adjustments
    public static func customNumeric(
        fieldName: String,
        operator: FilterOperator,
        value: String,
        action: FilterAction,
        weight: Int? = nil
    ) -> SimpleFilter {
        return SimpleFilter(
            key: "custom.numeric.\(fieldName)",
            operator: `operator`,
            value: value,
            action: action,
            weight: weight
        )
    }

    /// Create a filter for custom date fields
    /// - Parameters:
    ///   - fieldName: The custom field name
    ///   - operator: The filter operator
    ///   - value: The filter value (ISO8601 date string)
    ///   - action: The filter action
    ///   - weight: Optional weight for ranking adjustments
    public static func customDate(
        fieldName: String,
        operator: FilterOperator,
        value: String,
        action: FilterAction,
        weight: Int? = nil
    ) -> SimpleFilter {
        return SimpleFilter(
            key: "custom.date.\(fieldName)",
            operator: `operator`,
            value: value,
            action: action,
            weight: weight
        )
    }

    // MARK: - Common Filter Presets

    /// Create a price range filter
    /// - Parameters:
    ///   - minPrice: Minimum price
    ///   - maxPrice: Maximum price
    ///   - action: The filter action (defaults to include)
    ///   - weight: Optional weight for ranking adjustments
    public static func priceRange(
        minPrice: Double,
        maxPrice: Double,
        action: FilterAction = .include,
        weight: Int? = nil
    ) -> SimpleFilter {
        return SimpleFilter(
            key: "price",
            operator: .gteLte,
            value: "\(minPrice),\(maxPrice)",
            action: action,
            weight: weight
        )
    }

    /// Create a minimum price filter
    /// - Parameters:
    ///   - minPrice: Minimum price
    ///   - action: The filter action (defaults to include)
    ///   - weight: Optional weight for ranking adjustments
    public static func minPrice(
        _ minPrice: Double,
        action: FilterAction = .include,
        weight: Int? = nil
    ) -> SimpleFilter {
        return SimpleFilter(
            key: "price",
            operator: .gte,
            value: "\(minPrice)",
            action: action,
            weight: weight
        )
    }

    /// Create a maximum price filter
    /// - Parameters:
    ///   - maxPrice: Maximum price
    ///   - action: The filter action (defaults to include)
    ///   - weight: Optional weight for ranking adjustments
    public static func maxPrice(
        _ maxPrice: Double,
        action: FilterAction = .include,
        weight: Int? = nil
    ) -> SimpleFilter {
        return SimpleFilter(
            key: "price",
            operator: .lte,
            value: "\(maxPrice)",
            action: action,
            weight: weight
        )
    }

    /// Create a size filter
    /// - Parameters:
    ///   - size: The size value
    ///   - action: The filter action (defaults to include)
    ///   - weight: Optional weight for ranking adjustments
    public static func size(
        _ size: String,
        action: FilterAction = .include,
        weight: Int? = nil
    ) -> SimpleFilter {
        return customString(
            fieldName: "size",
            operator: .eq,
            value: size,
            action: action,
            weight: weight
        )
    }

    /// Create a brand filter
    /// - Parameters:
    ///   - brand: The brand name
    ///   - action: The filter action (defaults to include)
    ///   - weight: Optional weight for ranking adjustments
    public static func brand(
        _ brand: String,
        action: FilterAction = .include,
        weight: Int? = nil
    ) -> SimpleFilter {
        return customString(
            fieldName: "brand",
            operator: .eq,
            value: brand,
            action: action,
            weight: weight
        )
    }

    /// Create a color filter
    /// - Parameters:
    ///   - color: The color value
    ///   - action: The filter action (defaults to include)
    ///   - weight: Optional weight for ranking adjustments
    public static func color(
        _ color: String,
        action: FilterAction = .include,
        weight: Int? = nil
    ) -> SimpleFilter {
        return customString(
            fieldName: "color",
            operator: .eq,
            value: color,
            action: action,
            weight: weight
        )
    }

    /// Create a category filter
    /// - Parameters:
    ///   - category: The category name
    ///   - action: The filter action (defaults to include)
    ///   - weight: Optional weight for ranking adjustments
    public static func category(
        _ category: String,
        action: FilterAction = .include,
        weight: Int? = nil
    ) -> SimpleFilter {
        return customString(
            fieldName: "category",
            operator: .eq,
            value: category,
            action: action,
            weight: weight
        )
    }

    /// Create an availability filter
    /// - Parameters:
    ///   - inStock: Whether to filter for in-stock items
    ///   - action: The filter action (defaults to include)
    ///   - weight: Optional weight for ranking adjustments
    public static func availability(
        inStock: Bool,
        action: FilterAction = .include,
        weight: Int? = nil
    ) -> SimpleFilter {
        return customString(
            fieldName: "availability",
            operator: .eq,
            value: inStock ? "in_stock" : "out_of_stock",
            action: action,
            weight: weight
        )
    }

    /// Create a rating filter
    /// - Parameters:
    ///   - minRating: Minimum rating (1-5)
    ///   - action: The filter action (defaults to include)
    ///   - weight: Optional weight for ranking adjustments
    public static func rating(
        minRating: Double,
        action: FilterAction = .include,
        weight: Int? = nil
    ) -> SimpleFilter {
        return customNumeric(
            fieldName: "rating",
            operator: .gte,
            value: "\(minRating)",
            action: action,
            weight: weight
        )
    }

    // MARK: - Serialization

    /// Convert to dictionary for API requests
    public func toDict() -> [String: Any] {
        var dict: [String: Any] = [
            "key": key,
            "operator": `operator`.value,
            "value": value,
            "action": action.value
        ]

        if let weight = weight {
            dict["weight"] = String(weight)
        }

        return dict
    }

    // MARK: - Validation

    /// Validate the filter
    /// - Throws: RelevaError if validation fails
    public func validate() throws {
        if key.isEmpty {
            throw RelevaError.missingRequiredField("Filter key cannot be empty")
        }

        if value.isEmpty {
            throw RelevaError.missingRequiredField("Filter value cannot be empty")
        }

        // Validate range operators have comma-separated values
        if `operator`.isRangeOperator && !value.contains(",") {
            throw RelevaError.invalidConfiguration("Range operator requires comma-separated values")
        }

        // Validate weight is positive if specified
        if let weight = weight, weight <= 0 {
            throw RelevaError.invalidConfiguration("Filter weight must be positive")
        }
    }
}