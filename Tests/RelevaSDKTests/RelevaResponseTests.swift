import XCTest
@testable import RelevaSDK

final class RelevaResponseTests: XCTestCase {

    func testParseResponseWithNpsAndStories() throws {
        let json = """
        {
            "recommenders": [],
            "banners": [],
            "stories": [
                {
                    "token": "story-1",
                    "storyId": 1,
                    "trigger": "immediately",
                    "endBehavior": "dismiss",
                    "slides": [
                        {"id": 1, "durationSeconds": 5}
                    ]
                }
            ],
            "nps": {
                "token": "nps-1",
                "question": "Rate us?",
                "triggers": [{"type": "appOpen"}],
                "appearance": {
                    "primaryColor": "#FF0000",
                    "position": "bottomSheet"
                }
            }
        }
        """

        let data = json.data(using: .utf8)!
        let response = try RelevaResponse.from(jsonData: data)

        // Stories
        XCTAssertTrue(response.hasStories)
        XCTAssertEqual(response.stories.count, 1)
        XCTAssertEqual(response.stories[0].token, "story-1")
        XCTAssertEqual(response.stories[0].slides.count, 1)

        // NPS
        XCTAssertTrue(response.hasNps)
        XCTAssertEqual(response.nps?.token, "nps-1")
        XCTAssertEqual(response.nps?.question, "Rate us?")
        XCTAssertEqual(response.nps?.triggers.count, 1)
        XCTAssertEqual(response.nps?.appearance.primaryColor, "#FF0000")
    }

    /// `init(from:)` used to drop stories and NPS and print a warning, so a plain
    /// `JSONDecoder().decode(RelevaResponse.self, ...)` silently lost half the response.
    /// There is now one decoding path and `from(jsonData:)` is a thin wrapper over it.
    func testPlainCodableDecodingSeesStoriesAndNpsToo() throws {
        let json = """
        {
            "banners": [{"token": "b-1", "design": {"body": {"values": {"backgroundColor": "#fff"}}}}],
            "stories": [{"token": "story-1", "slides": [{"id": 1}]}],
            "nps": {"token": "nps-1", "question": "Rate us?"}
        }
        """

        let response = try JSONDecoder().decode(RelevaResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.banners.map(\.token), ["b-1"])
        XCTAssertEqual(response.stories.map(\.token), ["story-1"])
        XCTAssertEqual(response.nps?.token, "nps-1")
    }

    /// `RecommenderResponseTests` pins that a wrong-shape `meta` decodes to `nil` on the
    /// `RecommenderResponse` itself, but the claim the CHANGELOG and PR description actually
    /// make is one level up: that field going bad must not cost the rest of the envelope. A
    /// sub-type test can't see that composition; this is where it would show up if a future
    /// edit (tightening `try?` back to `try`, say) silently reopened a whole-response failure.
    func testAWrongShapeRecommenderMetaDoesNotTakeDownTheRestOfTheResponse() throws {
        let json = """
        {
            "recommenders": [{"token": "r-1", "name": "n", "meta": [], "response": []}],
            "banners": [{"token": "b-1"}],
            "nps": {"token": "nps-1", "question": "Rate us?"}
        }
        """

        let response = try JSONDecoder().decode(RelevaResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.recommenders.map(\.token), ["r-1"], "the recommender itself must survive, not just the banners")
        XCTAssertNil(response.recommenders.first?.meta)
        XCTAssertEqual(response.banners.map(\.token), ["b-1"], "one open-ended field must not cost the banners")
        XCTAssertEqual(response.nps?.token, "nps-1")
    }

    func testParseResponseWithoutNpsOrStories() throws {
        let json = """
        {
            "recommenders": [],
            "banners": []
        }
        """

        let data = json.data(using: .utf8)!
        let response = try RelevaResponse.from(jsonData: data)

        XCTAssertFalse(response.hasStories)
        XCTAssertFalse(response.hasNps)
        XCTAssertTrue(response.stories.isEmpty)
        XCTAssertNil(response.nps)
    }

    func testEmptyResponse() {
        let response = RelevaResponse.empty()

        XCTAssertTrue(response.recommenders.isEmpty)
        XCTAssertTrue(response.banners.isEmpty)
        XCTAssertTrue(response.stories.isEmpty)
        XCTAssertNil(response.nps)
        XCTAssertNil(response.push)
    }

    func testMergeResponses() {
        let r1 = RelevaResponse(
            stories: [StoryResponse(token: "s1", slides: [])],
            nps: NpsConfig(token: "n1", question: "Q?")
        )
        let r2 = RelevaResponse(
            stories: [StoryResponse(token: "s2", slides: [])]
        )

        let merged = RelevaResponse.merge([r1, r2])

        XCTAssertEqual(merged.stories.count, 2)
        XCTAssertNotNil(merged.nps)
        XCTAssertEqual(merged.nps?.token, "n1")
    }
}
