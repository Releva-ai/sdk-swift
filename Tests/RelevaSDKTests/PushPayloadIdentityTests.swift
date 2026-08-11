import XCTest
@testable import RelevaSDK

/// Locks the identity contract at the request->context merge site (buildPushPayload).
/// profileId is the only identity mechanism, so a request must never be able to inject
/// profile attributes into `context.profile`, and `context.profile.id` must survive.
/// Guards against anyone re-widening the merge whitelist to include "profile".
final class PushPayloadIdentityTests: XCTestCase {
    func testProfileMergeKeepsOnlyIdentity() {
        let service = NetworkService(realm: "us", accessToken: "token", config: .full())

        // Context carries the client-owned identity.
        let context: [String: Any] = ["profile": ["id": "user-123"]]

        // A (hypothetical) request tries to smuggle profile attributes plus a legit page.
        let request: [String: Any] = [
            "profile": ["email": "x@y.com", "phoneNumber": "+1"],
            "page": ["url": "https://example.com"]
        ]

        let payload = service.buildPushPayload(request: request, context: context)
        let ctx = payload["context"] as? [String: Any]
        let profile = ctx?["profile"] as? [String: Any]

        // Identity survives, exactly as { id: ... }.
        XCTAssertEqual(profile?["id"] as? String, "user-123")
        XCTAssertEqual(profile?.count, 1)

        // No profile attribute from the request leaked into the merged context.
        XCTAssertNil(profile?["email"])
        XCTAssertNil(profile?["phoneNumber"])

        // page is a whitelisted key and still merges through.
        XCTAssertNotNil(ctx?["page"])
    }
}
