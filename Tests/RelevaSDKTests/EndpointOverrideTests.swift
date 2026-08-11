import XCTest
@testable import RelevaSDK

final class EndpointOverrideTests: XCTestCase {
    func testDefaultBaseURLWithRealm() {
        let service = NetworkService(realm: "us", accessToken: "token", config: .full())
        XCTAssertEqual(service.getBaseURL(), "https://us.releva.ai")
    }

    func testDefaultBaseURLWithoutRealm() {
        let service = NetworkService(realm: "", accessToken: "token", config: .full())
        XCTAssertEqual(service.getBaseURL(), "https://releva.ai")
    }

    func testCustomEndpointInConfig() {
        let config = RelevaConfig(customEndpoint: "https://custom.example.com")
        let service = NetworkService(realm: "us", accessToken: "token", config: config)
        XCTAssertEqual(service.getBaseURL(), "https://custom.example.com")
    }

    func testEndpointOverrideTakesPrecedence() {
        let config = RelevaConfig(customEndpoint: "https://custom.example.com")
        let service = NetworkService(realm: "us", accessToken: "token", config: config)

        service.setEndpointOverride("https://ngrok.example.com")
        XCTAssertEqual(service.getBaseURL(), "https://ngrok.example.com")
    }

    func testClearEndpointOverride() {
        let service = NetworkService(realm: "us", accessToken: "token", config: .full())

        service.setEndpointOverride("https://override.com")
        XCTAssertEqual(service.getBaseURL(), "https://override.com")

        service.setEndpointOverride(nil)
        XCTAssertEqual(service.getBaseURL(), "https://us.releva.ai")
    }
}
