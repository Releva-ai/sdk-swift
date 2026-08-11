import Foundation

/// Banner response from Releva API
public struct BannerResponse: Sendable {

    // MARK: - Properties

    /// Unique identifier for this banner display
    public let token: String

    /// Banner ID
    public let bannerId: Int

    /// Segment ID
    public let segmentId: Int

    /// Banner name
    public let name: String

    /// Legacy HTML content
    public let html: String

    /// Tags for filtering
    public let tags: [String]?

    /// Merge context
    public let mergeContext: [String: String]?

    /// Display type: popup, bar, flyout, static, custom
    public let displayType: String?

    /// Delay in seconds for trigger
    public let delaySeconds: Int?

    /// Scroll percentage for trigger
    public let scrollPercentage: Int?

    /// CSS selector for static banner targeting
    public let cssSelector: String?

    /// Trigger type: immediately, delaySeconds, scrollPercentage, cartChanged, wishlistChanged, leaveIntent
    public let trigger: String?

    /// Display strategy: afterbegin, beforeend, afterend, replace
    public let displayStrategy: String?

    /// Display position: top, bottom, left, right, full-screen
    public let displayPosition: String?

    /// Whether advanced styling is enabled
    public let advancedStyling: Bool?

    /// CSS style overrides
    public let cssStyles: [String: JSONValue]

    /// Unlayer design JSON
    public let design: [String: JSONValue]?

    /// Legacy content
    public let content: String?

    /// Legacy image URL
    public let imageUrl: String?

    /// Legacy target URL
    public let targetUrl: String?

    /// Additional metadata
    public let meta: [String: JSONValue]?

    // MARK: - Initializers

    public init(
        token: String,
        bannerId: Int = 0,
        segmentId: Int = 0,
        name: String = "",
        html: String = "",
        tags: [String]? = nil,
        mergeContext: [String: String]? = nil,
        displayType: String? = nil,
        delaySeconds: Int? = nil,
        scrollPercentage: Int? = nil,
        cssSelector: String? = nil,
        trigger: String? = nil,
        displayStrategy: String? = "afterbegin",
        displayPosition: String? = nil,
        advancedStyling: Bool? = false,
        cssStyles: [String: JSONValue] = [:],
        design: [String: JSONValue]? = nil,
        content: String? = nil,
        imageUrl: String? = nil,
        targetUrl: String? = nil,
        meta: [String: JSONValue]? = nil
    ) {
        self.token = token
        self.bannerId = bannerId
        self.segmentId = segmentId
        self.name = name
        self.html = html
        self.tags = tags
        self.mergeContext = mergeContext
        self.displayType = displayType
        self.delaySeconds = delaySeconds
        self.scrollPercentage = scrollPercentage
        self.cssSelector = cssSelector
        self.trigger = trigger
        self.displayStrategy = displayStrategy
        self.displayPosition = displayPosition
        self.advancedStyling = advancedStyling
        self.cssStyles = cssStyles
        self.design = design
        self.content = content
        self.imageUrl = imageUrl
        self.targetUrl = targetUrl
        self.meta = meta
    }

    // MARK: - Factory Methods

    /// Create from dictionary (parsed JSON)
    public static func from(dict: [String: Any]) -> BannerResponse {
        return BannerResponse(
            token: dict["token"] as? String ?? "",
            bannerId: (dict["bannerId"] as? NSNumber)?.intValue ?? 0,
            segmentId: (dict["segmentId"] as? NSNumber)?.intValue ?? 0,
            name: dict["name"] as? String ?? "",
            html: dict["html"] as? String ?? "",
            tags: dict["tags"] as? [String],
            mergeContext: dict["mergeContext"] as? [String: String],
            displayType: dict["displayType"] as? String,
            delaySeconds: (dict["delaySeconds"] as? NSNumber)?.intValue,
            scrollPercentage: (dict["scrollPercentage"] as? NSNumber)?.intValue,
            cssSelector: dict["cssSelector"] as? String,
            trigger: dict["trigger"] as? String,
            displayStrategy: dict["displayStrategy"] as? String ?? "afterbegin",
            displayPosition: dict["displayPosition"] as? String,
            advancedStyling: dict["advancedStyling"] as? Bool ?? false,
            cssStyles: (dict["cssStyles"] as? [String: Any]).map { [String: JSONValue](any: $0) } ?? [:],
            design: (dict["design"] as? [String: Any]).map { [String: JSONValue](any: $0) },
            content: dict["content"] as? String,
            imageUrl: dict["imageUrl"] as? String,
            targetUrl: dict["targetUrl"] as? String,
            meta: (dict["meta"] as? [String: Any]).map { [String: JSONValue](any: $0) }
        )
    }

    /// Convert to dictionary
    public func toDict() -> [String: Any] {
        var dict: [String: Any] = [
            "token": token,
            "bannerId": bannerId,
            "segmentId": segmentId,
            "name": name,
            "html": html,
        ]
        if let tags = tags { dict["tags"] = tags }
        if let mergeContext = mergeContext { dict["mergeContext"] = mergeContext }
        if let displayType = displayType { dict["displayType"] = displayType }
        if let delaySeconds = delaySeconds { dict["delaySeconds"] = delaySeconds }
        if let scrollPercentage = scrollPercentage { dict["scrollPercentage"] = scrollPercentage }
        if let cssSelector = cssSelector { dict["cssSelector"] = cssSelector }
        if let trigger = trigger { dict["trigger"] = trigger }
        if let displayStrategy = displayStrategy { dict["displayStrategy"] = displayStrategy }
        if let displayPosition = displayPosition { dict["displayPosition"] = displayPosition }
        if let advancedStyling = advancedStyling { dict["advancedStyling"] = advancedStyling }
        if !cssStyles.isEmpty { dict["cssStyles"] = cssStyles.anyValue }
        if let design = design { dict["design"] = design.anyValue }
        if let content = content { dict["content"] = content }
        if let imageUrl = imageUrl { dict["imageUrl"] = imageUrl }
        if let targetUrl = targetUrl { dict["targetUrl"] = targetUrl }
        if let meta = meta { dict["meta"] = meta.anyValue }
        return dict
    }
}
