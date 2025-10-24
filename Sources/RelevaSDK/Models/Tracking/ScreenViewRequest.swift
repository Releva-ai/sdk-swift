import Foundation

/// Request for tracking screen view events
public class ScreenViewRequest: PushRequest {

    // MARK: - Properties

    /// The screen identifier token
    public let screenToken: String?

    /// Product IDs visible on the screen
    public let productIds: [String]?

    /// Categories visible on the screen
    public let categories: [String]?

    /// Filter applied to the screen
    public let filter: AbstractFilter?

    /// Blocks with tags
    public let blocks: [String: [String]]?

    // MARK: - Initializers

    /// Initialize a screen view request
    /// - Parameters:
    ///   - screenToken: The screen identifier token
    ///   - productIds: Product IDs visible on the screen
    ///   - categories: Categories visible on the screen
    ///   - filter: Filter applied to the screen
    ///   - blocks: Blocks with tags
    public init(
        screenToken: String? = nil,
        productIds: [String]? = nil,
        categories: [String]? = nil,
        filter: AbstractFilter? = nil,
        blocks: [String: [String]]? = nil
    ) {
        self.screenToken = screenToken
        self.productIds = productIds
        self.categories = categories
        self.filter = filter
        self.blocks = blocks

        super.init()

        // Apply properties to the base request
        if let token = screenToken {
            self.screenView(token)
        }
        if let ids = productIds, !ids.isEmpty {
            self.pageProductIds(ids)
        }
        if let cats = categories, !cats.isEmpty {
            self.pageCategories(cats)
        }
        if let pageFilter = filter {
            self.pageFilter(pageFilter)
        }
        if let tags = blocks?["tags"], !tags.isEmpty {
            self.pageBlocks(tags: tags)
        }
    }

    // MARK: - Factory Methods

    /// Create a screen view request for a product listing page
    /// - Parameters:
    ///   - screenToken: The screen identifier
    ///   - productIds: Product IDs on the page
    ///   - filter: Optional filter applied
    /// - Returns: A configured screen view request
    public static func productListing(
        screenToken: String,
        productIds: [String],
        filter: AbstractFilter? = nil
    ) -> ScreenViewRequest {
        return ScreenViewRequest(
            screenToken: screenToken,
            productIds: productIds,
            filter: filter
        )
    }

    /// Create a screen view request for a category page
    /// - Parameters:
    ///   - screenToken: The screen identifier
    ///   - categories: Categories on the page
    ///   - productIds: Product IDs on the page
    /// - Returns: A configured screen view request
    public static func categoryPage(
        screenToken: String,
        categories: [String],
        productIds: [String] = []
    ) -> ScreenViewRequest {
        return ScreenViewRequest(
            screenToken: screenToken,
            productIds: productIds.isEmpty ? nil : productIds,
            categories: categories
        )
    }

    /// Create a screen view request for a home page
    /// - Parameters:
    ///   - screenToken: The screen identifier (defaults to "home")
    ///   - blocks: Optional blocks with tags for different sections
    /// - Returns: A configured screen view request
    public static func homePage(
        screenToken: String,
        blocks: [String: [String]]? = nil
    ) -> ScreenViewRequest {
        return ScreenViewRequest(
            screenToken: screenToken,
            blocks: blocks
        )
    }

    /// Create a screen view request for a cart page
    /// - Parameter screenToken: The screen identifier (defaults to "cart")
    /// - Returns: A configured screen view request
    public static func cartPage(screenToken: String) -> ScreenViewRequest {
        return ScreenViewRequest(screenToken: screenToken)
    }

    /// Create a screen view request for a checkout page
    /// - Parameter screenToken: The screen identifier (defaults to "checkout")
    /// - Returns: A configured screen view request
    public static func checkoutPage(screenToken: String) -> ScreenViewRequest {
        return ScreenViewRequest(screenToken: screenToken)
    }

    // MARK: - Copy Method

    /// Create a copy with updated values
    /// - Parameters:
    ///   - screenToken: New screen token
    ///   - productIds: New product IDs
    ///   - categories: New categories
    ///   - filter: New filter
    ///   - blocks: New blocks
    /// - Returns: A new screen view request with updated values
    public func copyWith(
        screenToken: String? = nil,
        productIds: [String]? = nil,
        categories: [String]? = nil,
        filter: AbstractFilter? = nil,
        blocks: [String: [String]]? = nil
    ) -> ScreenViewRequest {
        return ScreenViewRequest(
            screenToken: screenToken ?? self.screenToken,
            productIds: productIds ?? self.productIds,
            categories: categories ?? self.categories,
            filter: filter ?? self.filter,
            blocks: blocks ?? self.blocks
        )
    }
}