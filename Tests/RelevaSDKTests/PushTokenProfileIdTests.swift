import XCTest
@testable import RelevaSDK

/// `POST /api/v0/appPush/tokens` requires a `profileId` and answers 400 without one, and `/push`
/// files an unidentified device's profile under its deviceId. An anonymous registration therefore
/// sends the deviceId, while what the client stores stays nil so the host's first `setProfileId`
/// re-files the token under the real id.
@MainActor
final class PushTokenProfileIdTests: XCTestCase {
    /// Cleared before each test and restored after: `RelevaClient` loads its identity from
    /// `UserDefaults.standard` on init, so an id left behind by another test would decide the
    /// request body under test here.
    private static let storageKeys: [StorageService.StorageKey] = [
        .deviceId,
        .profileId,
        .pushToken,
        .deviceType,
        .pushTokenUploadedAt,
        .pushTokenProfileId,
        .mergeProfileIds
    ]

    private let storage = StorageService()
    private var savedDefaults: [String: Any] = [:]
    private var savedShared: RelevaClient?
    private var session: URLSession!
    private var clients: [RelevaClient] = []

    override func setUp() {
        super.setUp()
        savedShared = RelevaClient.shared
        RelevaClient.shared = nil

        let defaults = UserDefaults.standard
        for key in Self.storageKeys {
            savedDefaults[key.rawValue] = defaults.object(forKey: key.rawValue)
            defaults.removeObject(forKey: key.rawValue)
        }

        session = StubURLProtocol.makeSession()
    }

    override func tearDown() {
        clients.forEach { $0.shutdown() }
        clients.removeAll()
        session?.invalidateAndCancel()
        session = nil
        StubURLProtocol.reset()

        let defaults = UserDefaults.standard
        for key in Self.storageKeys {
            defaults.removeObject(forKey: key.rawValue)
            if let value = savedDefaults[key.rawValue] {
                defaults.set(value, forKey: key.rawValue)
            }
        }
        savedDefaults.removeAll()

        RelevaClient.shared = savedShared
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeClient() -> RelevaClient {
        let config = RelevaConfig(enableTracking: false, enablePushNotifications: true)
        let client = RelevaClient(realm: "us", accessToken: "test-token", config: config)
        client.networkService = NetworkService(
            realm: "us",
            accessToken: "test-token",
            config: config,
            session: session
        )
        clients.append(client)
        return client
    }

    private func tokenRequestBody() throws -> [String: Any] {
        let request = try XCTUnwrap(StubURLProtocol.receivedRequests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://us.releva.ai/api/v0/appPush/tokens")
        let body = try XCTUnwrap(request.httpBody, "request had no body")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    // MARK: - Tests

    func testAnAnonymousRegistrationFilesTheTokenUnderTheDeviceId() async throws {
        StubURLProtocol.stub { _ in .response(statusCode: 200, body: Data("{}".utf8)) }
        let client = makeClient()
        client.setDeviceId("device-1")

        try await client.registerPushToken("fcm-token", deviceType: .ios)

        let payload = try tokenRequestBody()
        XCTAssertEqual(payload["deviceId"] as? String, "device-1")
        XCTAssertEqual(payload["profileId"] as? String, "device-1")
        XCTAssertNil(client.getProfileId(), "the host has not identified the user")
        XCTAssertNil(storage.getProfileId(), "the deviceId is sent, not adopted as the profile")
        XCTAssertNil(
            storage.getPushTokenProfileId(),
            "the token is recorded as filed under no host profile, so the first setProfileId re-files it"
        )
    }

    func testAnIdentifiedRegistrationSendsTheHostProfileId() async throws {
        StubURLProtocol.stub { _ in .response(statusCode: 200, body: Data("{}".utf8)) }
        let client = makeClient()
        client.setDeviceId("device-1")
        client.setProfileId("u1")

        try await client.registerPushToken("fcm-token", deviceType: .ios)

        let payload = try tokenRequestBody()
        XCTAssertEqual(payload["profileId"] as? String, "u1")
        XCTAssertEqual(storage.getPushTokenProfileId(), "u1")
    }

    func testIdentifyingTheUserRefilesAnAnonymouslyRegisteredToken() async throws {
        StubURLProtocol.stub { _ in .response(statusCode: 200, body: Data("{}".utf8)) }
        let client = makeClient()
        client.setDeviceId("device-1")
        client.pushTokenProvider = { completion in completion("fcm-token") }

        try await client.registerPushToken("fcm-token", deviceType: .ios)

        // The token and its upload timestamp are both unchanged by what follows, so the stored
        // profile id is the only thing that keeps `refreshPushToken` from throttling the re-upload
        // away — which is why the anonymous registration above must not have stored the deviceId.
        let reupload = expectation(description: "the token is re-registered")
        StubURLProtocol.stub { _ in
            reupload.fulfill()
            return .response(statusCode: 200, body: Data("{}".utf8))
        }

        client.setProfileId("u1")
        await fulfillment(of: [reupload], timeout: 2)

        let payload = try tokenRequestBody()
        XCTAssertEqual(payload["profileId"] as? String, "u1")

        // The stub answers before the registration resumes and records it; wait for that so the
        // write cannot land after `tearDown` has restored the defaults.
        for _ in 0..<200 where storage.getPushTokenProfileId() != "u1" {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(storage.getPushTokenProfileId(), "u1", "the re-filing is recorded")
    }
}
