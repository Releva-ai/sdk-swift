import XCTest
@testable import RelevaSDK

final class StoryResponseTests: XCTestCase {

    func testStoryResponseFromDict() {
        let dict: [String: Any] = [
            "token": "story-abc",
            "storyId": 42,
            "name": "Welcome Story",
            "trigger": "immediately",
            "delaySeconds": 3,
            "scrollPercentage": 50,
            "endBehavior": "loop",
            "progressIndicatorColor": "#00FF00",
            "progressIndicatorInactiveColor": "#00FF0044",
            "tags": ["onboarding", "promo"],
            "mergeContext": ["key": "value"],
            "slides": [
                [
                    "id": 1,
                    "durationSeconds": 5,
                    "actionType": "url",
                    "actionUrl": "https://example.com",
                    "actionLabel": "Learn More",
                    "design": ["body": ["rows": []]]
                ],
                [
                    "id": "slide-2",
                    "durationSeconds": 8,
                    "html": "<p>Hello</p>"
                ]
            ]
        ]

        let story = StoryResponse.from(dict: dict)

        XCTAssertEqual(story.token, "story-abc")
        XCTAssertEqual(story.storyId, "42")
        XCTAssertEqual(story.name, "Welcome Story")
        XCTAssertEqual(story.trigger, "immediately")
        XCTAssertEqual(story.delaySeconds, 3)
        XCTAssertEqual(story.scrollPercentage, 50)
        XCTAssertEqual(story.endBehavior, "loop")
        XCTAssertEqual(story.progressIndicatorColor, "#00FF00")
        XCTAssertEqual(story.tags, ["onboarding", "promo"])
        XCTAssertEqual(story.mergeContext?["key"], "value")
        XCTAssertEqual(story.slides.count, 2)

        // First slide
        XCTAssertEqual(story.slides[0].id, "1")
        XCTAssertEqual(story.slides[0].durationSeconds, 5)
        XCTAssertEqual(story.slides[0].actionType, "url")
        XCTAssertEqual(story.slides[0].actionUrl, "https://example.com")
        XCTAssertEqual(story.slides[0].actionLabel, "Learn More")
        XCTAssertNotNil(story.slides[0].design)

        // Second slide
        XCTAssertEqual(story.slides[1].id, "slide-2")
        XCTAssertEqual(story.slides[1].durationSeconds, 8)
        XCTAssertEqual(story.slides[1].html, "<p>Hello</p>")
        XCTAssertNil(story.slides[1].design)
    }

    func testStoryResponseFromDictDefaults() {
        let story = StoryResponse.from(dict: [:])

        XCTAssertEqual(story.token, "")
        XCTAssertEqual(story.endBehavior, "dismiss")
        XCTAssertEqual(story.progressIndicatorColor, "#FFFFFF")
        XCTAssertTrue(story.slides.isEmpty)
    }

    func testStorySlideDefaults() {
        let slide = StorySlideResponse.from(dict: [:])

        XCTAssertEqual(slide.durationSeconds, 5)
        XCTAssertNil(slide.actionType)
        XCTAssertNil(slide.design)
    }
}
