import Foundation

/// Represents a recommended product from the API
public struct ProductRecommendation: Codable, Equatable, Sendable {

    // MARK: - Properties

    /// Whether the product is available
    public let available: Bool

    /// Product categories
    public let categories: [String]?

    /// Creation timestamp
    public let createdAt: Date?

    /// Currency code
    public let currency: String?

    /// Custom fields
    public let custom: [String: JSONValue]?

    /// Additional data
    public let data: [String: JSONValue]?

    /// Product description
    public let description: String?

    /// Discount amount
    public let discount: Double?

    /// Discount percentage
    public let discountPercent: Double?

    /// Discounted price
    public let discountPrice: Double?

    /// Product ID
    public let id: String

    /// Product image URL
    public let imageUrl: String?

    /// List price (before discount)
    public let listPrice: Double?

    /// Locale
    public let locale: String?

    /// Merge context for personalization
    public let mergeContext: [String: String]?

    /// Product name
    public let name: String

    /// Current price
    public let price: Double

    /// Publication timestamp
    public let publishedAt: Date?

    /// Last update timestamp
    public let updatedAt: Date?

    /// Product page URL
    public let url: String?

    // MARK: - Computed Properties

    /// Check if product has a discount
    public var hasDiscount: Bool {
        return discount != nil && discount! > 0
    }

    /// Calculate the actual discount percentage if not provided
    public var calculatedDiscountPercent: Double? {
        guard let listPrice = listPrice, listPrice > 0 else { return discountPercent }
        let actualPrice = discountPrice ?? price
        return ((listPrice - actualPrice) / listPrice) * 100
    }

    /// Get the best available price (discounted or regular)
    public var bestPrice: Double {
        return discountPrice ?? price
    }

    /// Check if product has an image
    public var hasImage: Bool {
        return imageUrl != nil && !imageUrl!.isEmpty
    }

    /// Check if product has a URL
    public var hasUrl: Bool {
        return url != nil && !url!.isEmpty
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case available, categories, createdAt, currency, custom, data
        case description, discount, discountPercent, discountPrice
        case id, imageUrl, listPrice, locale, mergeContext
        case name, price, publishedAt, updatedAt, url
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        available = try container.decodeIfPresent(Bool.self, forKey: .available) ?? false
        categories = try container.decodeIfPresent([String].self, forKey: .categories)

        // Date parsing
        let dateFormatter = ISO8601DateFormatter()
        if let createdAtString = try container.decodeIfPresent(String.self, forKey: .createdAt) {
            createdAt = dateFormatter.date(from: createdAtString)
        } else {
            createdAt = nil
        }

        currency = try container.decodeIfPresent(String.self, forKey: .currency)

        custom = try container.decodeIfPresent([String: JSONValue].self, forKey: .custom)
        data = try container.decodeIfPresent([String: JSONValue].self, forKey: .data)

        description = try container.decodeIfPresent(String.self, forKey: .description)
        discount = try container.decodeIfPresent(Double.self, forKey: .discount)
        discountPercent = try container.decodeIfPresent(Double.self, forKey: .discountPercent)
        discountPrice = try container.decodeIfPresent(Double.self, forKey: .discountPrice)

        id = try container.decode(String.self, forKey: .id)
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        listPrice = try container.decodeIfPresent(Double.self, forKey: .listPrice)
        locale = try container.decodeIfPresent(String.self, forKey: .locale)

        // Handle mergeContext with mixed types - convert all values to strings
        if container.contains(.mergeContext) {
            // Try decoding as [String: String] first (most common case)
            if let stringDict = try? container.decode([String: String].self, forKey: .mergeContext) {
                mergeContext = stringDict
            } else {
                // Fallback: decode with dynamic types and convert all values to strings
                do {
                    let nestedContainer = try container.nestedContainer(keyedBy: DynamicKey.self, forKey: .mergeContext)
                    var result: [String: String] = [:]

                    for key in nestedContainer.allKeys {
                        // Try to decode as different types and convert to string
                        if let stringValue = try? nestedContainer.decode(String.self, forKey: key) {
                            result[key.stringValue] = stringValue
                        } else if let intValue = try? nestedContainer.decode(Int.self, forKey: key) {
                            result[key.stringValue] = String(intValue)
                        } else if let doubleValue = try? nestedContainer.decode(Double.self, forKey: key) {
                            result[key.stringValue] = String(doubleValue)
                        } else if let boolValue = try? nestedContainer.decode(Bool.self, forKey: key) {
                            result[key.stringValue] = String(boolValue)
                        }
                    }

                    mergeContext = result.isEmpty ? nil : result
                } catch {
                    mergeContext = nil
                }
            }
        } else {
            mergeContext = nil
        }

        name = try container.decode(String.self, forKey: .name)
        price = try container.decode(Double.self, forKey: .price)

        if let publishedAtString = try container.decodeIfPresent(String.self, forKey: .publishedAt) {
            publishedAt = dateFormatter.date(from: publishedAtString)
        } else {
            publishedAt = nil
        }

        if let updatedAtString = try container.decodeIfPresent(String.self, forKey: .updatedAt) {
            updatedAt = dateFormatter.date(from: updatedAtString)
        } else {
            updatedAt = nil
        }

        url = try container.decodeIfPresent(String.self, forKey: .url)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(available, forKey: .available)
        try container.encodeIfPresent(categories, forKey: .categories)

        let dateFormatter = ISO8601DateFormatter()
        if let createdAt = createdAt {
            try container.encode(dateFormatter.string(from: createdAt), forKey: .createdAt)
        }

        try container.encodeIfPresent(currency, forKey: .currency)

        try container.encodeIfPresent(custom, forKey: .custom)
        try container.encodeIfPresent(data, forKey: .data)

        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(discount, forKey: .discount)
        try container.encodeIfPresent(discountPercent, forKey: .discountPercent)
        try container.encodeIfPresent(discountPrice, forKey: .discountPrice)

        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(imageUrl, forKey: .imageUrl)
        try container.encodeIfPresent(listPrice, forKey: .listPrice)
        try container.encodeIfPresent(locale, forKey: .locale)
        try container.encodeIfPresent(mergeContext, forKey: .mergeContext)

        try container.encode(name, forKey: .name)
        try container.encode(price, forKey: .price)

        if let publishedAt = publishedAt {
            try container.encode(dateFormatter.string(from: publishedAt), forKey: .publishedAt)
        }

        if let updatedAt = updatedAt {
            try container.encode(dateFormatter.string(from: updatedAt), forKey: .updatedAt)
        }

        try container.encodeIfPresent(url, forKey: .url)
    }

    // MARK: - Equatable

    public static func == (lhs: ProductRecommendation, rhs: ProductRecommendation) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Array Extensions

extension Array where Element == ProductRecommendation {

    /// Filter available products
    public var available: [ProductRecommendation] {
        return filter { $0.available }
    }

    /// Filter products with discounts
    public var discounted: [ProductRecommendation] {
        return filter { $0.hasDiscount }
    }

    /// Sort by price (ascending)
    public func sortedByPrice(ascending: Bool = true) -> [ProductRecommendation] {
        return sorted { ascending ? $0.price < $1.price : $0.price > $1.price }
    }

    /// Sort by discount percentage (highest first)
    public func sortedByDiscount() -> [ProductRecommendation] {
        return sorted {
            let discount1 = $0.calculatedDiscountPercent ?? 0
            let discount2 = $1.calculatedDiscountPercent ?? 0
            return discount1 > discount2
        }
    }

    /// Get products in a specific category
    public func inCategory(_ category: String) -> [ProductRecommendation] {
        return filter { $0.categories?.contains(category) ?? false }
    }

    /// Get products within a price range
    public func inPriceRange(min: Double, max: Double) -> [ProductRecommendation] {
        return filter { $0.bestPrice >= min && $0.bestPrice <= max }
    }
}

// MARK: - Helper Coding Keys

private struct DynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}