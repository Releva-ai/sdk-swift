import Foundation

/// Story slide response from the API
public struct StorySlideResponse {
    public let id: String
    public let html: String?
    public let design: [String: Any]?
    public let durationSeconds: Int
    public let actionType: String?
    public let actionUrl: String?
    public let actionLabel: String?

    public init(
        id: String = "",
        html: String? = nil,
        design: [String: Any]? = nil,
        durationSeconds: Int = 5,
        actionType: String? = nil,
        actionUrl: String? = nil,
        actionLabel: String? = nil
    ) {
        self.id = id
        self.html = html
        self.design = design
        self.durationSeconds = durationSeconds
        self.actionType = actionType
        self.actionUrl = actionUrl
        self.actionLabel = actionLabel
    }

    public static func from(dict: [String: Any]) -> StorySlideResponse {
        return StorySlideResponse(
            id: "\(dict["id"] ?? "")",
            html: dict["html"] as? String,
            design: dict["design"] as? [String: Any],
            durationSeconds: (dict["durationSeconds"] as? NSNumber)?.intValue ?? 5,
            actionType: dict["actionType"] as? String,
            actionUrl: dict["actionUrl"] as? String,
            actionLabel: dict["actionLabel"] as? String
        )
    }
}

/// Story response from the API
public struct StoryResponse {
    public let token: String
    public let storyId: String
    public let name: String?
    public let trigger: String?
    public let delaySeconds: Int?
    public let scrollPercentage: Int?
    public let endBehavior: String // dismiss, loop, stayOnLast
    public let progressIndicatorColor: String
    public let progressIndicatorInactiveColor: String
    public let tags: [String]?
    public let slides: [StorySlideResponse]
    public let mergeContext: [String: String]?

    public init(
        token: String,
        storyId: String = "",
        name: String? = nil,
        trigger: String? = nil,
        delaySeconds: Int? = nil,
        scrollPercentage: Int? = nil,
        endBehavior: String = "dismiss",
        progressIndicatorColor: String = "#FFFFFF",
        progressIndicatorInactiveColor: String = "#FFFFFF4D",
        tags: [String]? = nil,
        slides: [StorySlideResponse] = [],
        mergeContext: [String: String]? = nil
    ) {
        self.token = token
        self.storyId = storyId
        self.name = name
        self.trigger = trigger
        self.delaySeconds = delaySeconds
        self.scrollPercentage = scrollPercentage
        self.endBehavior = endBehavior
        self.progressIndicatorColor = progressIndicatorColor
        self.progressIndicatorInactiveColor = progressIndicatorInactiveColor
        self.tags = tags
        self.slides = slides
        self.mergeContext = mergeContext
    }

    public static func from(dict: [String: Any]) -> StoryResponse {
        let slidesArray = (dict["slides"] as? [[String: Any]])?.map { StorySlideResponse.from(dict: $0) } ?? []

        return StoryResponse(
            token: dict["token"] as? String ?? "",
            storyId: "\(dict["storyId"] ?? "")",
            name: dict["name"] as? String,
            trigger: dict["trigger"] as? String,
            delaySeconds: (dict["delaySeconds"] as? NSNumber)?.intValue,
            scrollPercentage: (dict["scrollPercentage"] as? NSNumber)?.intValue,
            endBehavior: dict["endBehavior"] as? String ?? "dismiss",
            progressIndicatorColor: dict["progressIndicatorColor"] as? String ?? "#FFFFFF",
            progressIndicatorInactiveColor: dict["progressIndicatorInactiveColor"] as? String ?? "#FFFFFF4D",
            tags: dict["tags"] as? [String],
            slides: slidesArray,
            mergeContext: dict["mergeContext"] as? [String: String]
        )
    }
}
