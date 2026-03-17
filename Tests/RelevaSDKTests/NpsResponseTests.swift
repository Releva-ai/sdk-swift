import XCTest
@testable import RelevaSDK

final class NpsResponseTests: XCTestCase {

    func testNpsConfigFromDict() {
        let dict: [String: Any] = [
            "token": "nps-123",
            "question": "How likely are you to recommend us?",
            "scaleLowLabel": "Not likely",
            "scaleHighLabel": "Very likely",
            "followUpRequired": true,
            "submitLabel": "Send",
            "skipLabel": "Skip",
            "triggerDelaySeconds": 5,
            "cancelOnEvents": ["checkout_started"],
            "followUp": [
                "promoter": "What do you love?",
                "passive": "How can we improve?",
                "detractor": "What went wrong?"
            ],
            "thankYou": [
                "promoter": "Thanks for the love!",
                "passive": "Thanks for feedback.",
                "detractor": "Sorry, we'll do better."
            ],
            "appearance": [
                "primaryColor": "#FF0000",
                "backgroundColor": "#FFFFFF",
                "textColor": "#000000",
                "buttonStyle": "rounded",
                "position": "modal",
                "logoUrl": "https://example.com/logo.png",
                "dark": [
                    "primaryColor": "#CC0000",
                    "backgroundColor": "#222222",
                    "textColor": "#EEEEEE"
                ]
            ],
            "triggers": [
                ["type": "appOpen"],
                ["type": "customEvent", "eventName": "checkout_complete"],
                ["type": "sessionCount", "minSessions": 3]
            ]
        ]

        let config = NpsConfig.from(dict: dict)

        XCTAssertEqual(config.token, "nps-123")
        XCTAssertEqual(config.question, "How likely are you to recommend us?")
        XCTAssertEqual(config.scaleLowLabel, "Not likely")
        XCTAssertEqual(config.scaleHighLabel, "Very likely")
        XCTAssertTrue(config.followUpRequired)
        XCTAssertEqual(config.submitLabel, "Send")
        XCTAssertEqual(config.skipLabel, "Skip")
        XCTAssertEqual(config.triggerDelaySeconds, 5)
        XCTAssertEqual(config.cancelOnEvents, ["checkout_started"])
        XCTAssertEqual(config.triggers.count, 3)

        // Follow-up
        XCTAssertEqual(config.followUp?.forScore(10), "What do you love?")
        XCTAssertEqual(config.followUp?.forScore(8), "How can we improve?")
        XCTAssertEqual(config.followUp?.forScore(3), "What went wrong?")

        // Thank you
        XCTAssertEqual(config.thankYou?.forScore(9), "Thanks for the love!")
        XCTAssertEqual(config.thankYou?.forScore(7), "Thanks for feedback.")
        XCTAssertEqual(config.thankYou?.forScore(0), "Sorry, we'll do better.")

        // Appearance
        XCTAssertEqual(config.appearance.primaryColor, "#FF0000")
        XCTAssertEqual(config.appearance.buttonStyle, "rounded")
        XCTAssertEqual(config.appearance.position, "modal")
        XCTAssertNotNil(config.appearance.dark)
        XCTAssertEqual(config.appearance.dark?.primaryColor, "#CC0000")

        // Triggers
        XCTAssertEqual(config.triggers[0].type, "appOpen")
        XCTAssertEqual(config.triggers[1].type, "customEvent")
        XCTAssertEqual(config.triggers[1].eventName, "checkout_complete")
        XCTAssertEqual(config.triggers[2].type, "sessionCount")
        XCTAssertEqual(config.triggers[2].minSessions, 3)
    }

    func testNpsConfigFromDictDefaults() {
        let config = NpsConfig.from(dict: [:])

        XCTAssertEqual(config.token, "")
        XCTAssertEqual(config.question, "")
        XCTAssertFalse(config.followUpRequired)
        XCTAssertEqual(config.submitLabel, "Submit")
        XCTAssertNil(config.skipLabel)
        XCTAssertEqual(config.triggerDelaySeconds, 0)
        XCTAssertTrue(config.cancelOnEvents.isEmpty)
        XCTAssertTrue(config.triggers.isEmpty)
        XCTAssertEqual(config.appearance.primaryColor, "#6C3FC4")
        XCTAssertEqual(config.appearance.position, "bottomSheet")
    }

    func testNpsFollowUpForScore() {
        let followUp = NpsFollowUp(promoter: "P", passive: "Pa", detractor: "D")

        XCTAssertEqual(followUp.forScore(10), "P")
        XCTAssertEqual(followUp.forScore(9), "P")
        XCTAssertEqual(followUp.forScore(8), "Pa")
        XCTAssertEqual(followUp.forScore(7), "Pa")
        XCTAssertEqual(followUp.forScore(6), "D")
        XCTAssertEqual(followUp.forScore(0), "D")
    }

    func testNpsThankYouForScore() {
        let thankYou = NpsThankYou(promoter: nil, passive: nil, detractor: nil)

        XCTAssertEqual(thankYou.forScore(10), "Thank you for your feedback!")
        XCTAssertEqual(thankYou.forScore(7), "Thank you for your feedback.")
        XCTAssertEqual(thankYou.forScore(0), "Thank you. We'll work on it.")
    }
}
