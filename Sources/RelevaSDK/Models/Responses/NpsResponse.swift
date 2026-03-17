import Foundation

/// NPS survey configuration from the API
public struct NpsConfig {
    public let token: String
    public let question: String
    public let scaleLowLabel: String?
    public let scaleHighLabel: String?
    public let followUp: NpsFollowUp?
    public let followUpRequired: Bool
    public let submitLabel: String
    public let skipLabel: String?
    public let thankYou: NpsThankYou?
    public let appearance: NpsAppearance
    public let triggers: [NpsTrigger]
    public let triggerDelaySeconds: Int
    public let cancelOnEvents: [String]

    public init(
        token: String,
        question: String,
        scaleLowLabel: String? = nil,
        scaleHighLabel: String? = nil,
        followUp: NpsFollowUp? = nil,
        followUpRequired: Bool = false,
        submitLabel: String = "Submit",
        skipLabel: String? = nil,
        thankYou: NpsThankYou? = nil,
        appearance: NpsAppearance = .defaults(),
        triggers: [NpsTrigger] = [],
        triggerDelaySeconds: Int = 0,
        cancelOnEvents: [String] = []
    ) {
        self.token = token
        self.question = question
        self.scaleLowLabel = scaleLowLabel
        self.scaleHighLabel = scaleHighLabel
        self.followUp = followUp
        self.followUpRequired = followUpRequired
        self.submitLabel = submitLabel
        self.skipLabel = skipLabel
        self.thankYou = thankYou
        self.appearance = appearance
        self.triggers = triggers
        self.triggerDelaySeconds = triggerDelaySeconds
        self.cancelOnEvents = cancelOnEvents
    }

    public static func from(dict: [String: Any]) -> NpsConfig {
        return NpsConfig(
            token: dict["token"] as? String ?? "",
            question: dict["question"] as? String ?? "",
            scaleLowLabel: dict["scaleLowLabel"] as? String,
            scaleHighLabel: dict["scaleHighLabel"] as? String,
            followUp: (dict["followUp"] as? [String: Any]).map { NpsFollowUp.from(dict: $0) },
            followUpRequired: dict["followUpRequired"] as? Bool ?? false,
            submitLabel: dict["submitLabel"] as? String ?? "Submit",
            skipLabel: dict["skipLabel"] as? String,
            thankYou: (dict["thankYou"] as? [String: Any]).map { NpsThankYou.from(dict: $0) },
            appearance: (dict["appearance"] as? [String: Any]).map { NpsAppearance.from(dict: $0) } ?? .defaults(),
            triggers: (dict["triggers"] as? [[String: Any]])?.map { NpsTrigger.from(dict: $0) } ?? [],
            triggerDelaySeconds: (dict["triggerDelaySeconds"] as? NSNumber)?.intValue ?? 0,
            cancelOnEvents: dict["cancelOnEvents"] as? [String] ?? []
        )
    }
}

/// Follow-up prompts by NPS score range
public struct NpsFollowUp {
    public let promoter: String?
    public let passive: String?
    public let detractor: String?

    public init(promoter: String? = nil, passive: String? = nil, detractor: String? = nil) {
        self.promoter = promoter
        self.passive = passive
        self.detractor = detractor
    }

    /// Get the follow-up question for a given score
    public func forScore(_ score: Int) -> String? {
        if score >= 9 { return promoter }
        if score >= 7 { return passive }
        return detractor
    }

    public static func from(dict: [String: Any]) -> NpsFollowUp {
        return NpsFollowUp(
            promoter: dict["promoter"] as? String,
            passive: dict["passive"] as? String,
            detractor: dict["detractor"] as? String
        )
    }
}

/// Thank-you messages by NPS score range
public struct NpsThankYou {
    public let promoter: String?
    public let passive: String?
    public let detractor: String?

    public init(promoter: String? = nil, passive: String? = nil, detractor: String? = nil) {
        self.promoter = promoter
        self.passive = passive
        self.detractor = detractor
    }

    /// Get the thank-you message for a given score
    public func forScore(_ score: Int) -> String {
        if score >= 9 { return promoter ?? "Thank you for your feedback!" }
        if score >= 7 { return passive ?? "Thank you for your feedback." }
        return detractor ?? "Thank you. We'll work on it."
    }

    public static func from(dict: [String: Any]) -> NpsThankYou {
        return NpsThankYou(
            promoter: dict["promoter"] as? String,
            passive: dict["passive"] as? String,
            detractor: dict["detractor"] as? String
        )
    }
}

/// NPS survey appearance configuration (server-driven)
public struct NpsAppearance {
    public let primaryColor: String
    public let backgroundColor: String
    public let textColor: String
    public let buttonStyle: String // pill, rounded, square
    public let position: String // bottomSheet, modal
    public let logoUrl: String?
    public let dark: NpsAppearanceDark?

    public init(
        primaryColor: String = "#6C3FC4",
        backgroundColor: String = "#FFFFFF",
        textColor: String = "#1A1A1A",
        buttonStyle: String = "pill",
        position: String = "bottomSheet",
        logoUrl: String? = nil,
        dark: NpsAppearanceDark? = nil
    ) {
        self.primaryColor = primaryColor
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.buttonStyle = buttonStyle
        self.position = position
        self.logoUrl = logoUrl
        self.dark = dark
    }

    public static func defaults() -> NpsAppearance {
        return NpsAppearance()
    }

    public static func from(dict: [String: Any]) -> NpsAppearance {
        return NpsAppearance(
            primaryColor: dict["primaryColor"] as? String ?? "#6C3FC4",
            backgroundColor: dict["backgroundColor"] as? String ?? "#FFFFFF",
            textColor: dict["textColor"] as? String ?? "#1A1A1A",
            buttonStyle: dict["buttonStyle"] as? String ?? "pill",
            position: dict["position"] as? String ?? "bottomSheet",
            logoUrl: dict["logoUrl"] as? String,
            dark: (dict["dark"] as? [String: Any]).map { NpsAppearanceDark.from(dict: $0) }
        )
    }
}

/// Dark mode color overrides for NPS appearance
public struct NpsAppearanceDark {
    public let primaryColor: String?
    public let backgroundColor: String?
    public let textColor: String?

    public init(primaryColor: String? = nil, backgroundColor: String? = nil, textColor: String? = nil) {
        self.primaryColor = primaryColor
        self.backgroundColor = backgroundColor
        self.textColor = textColor
    }

    public static func from(dict: [String: Any]) -> NpsAppearanceDark {
        return NpsAppearanceDark(
            primaryColor: dict["primaryColor"] as? String,
            backgroundColor: dict["backgroundColor"] as? String,
            textColor: dict["textColor"] as? String
        )
    }
}

/// NPS trigger configuration
public struct NpsTrigger {
    public let type: String // appOpen, customEvent, sessionCount, screenView
    public let eventName: String?
    public let minSessions: Int?

    public init(type: String, eventName: String? = nil, minSessions: Int? = nil) {
        self.type = type
        self.eventName = eventName
        self.minSessions = minSessions
    }

    public static func from(dict: [String: Any]) -> NpsTrigger {
        return NpsTrigger(
            type: dict["type"] as? String ?? "",
            eventName: dict["eventName"] as? String,
            minSessions: (dict["minSessions"] as? NSNumber)?.intValue
        )
    }
}
