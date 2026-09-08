import XCTest
@testable import RelevaSDK

/// Rows of the device test plan that need no device: what the client refuses before it
/// touches the network, and the small value helpers the plan lists as "temp code".
///
/// Tracking is left ON in these clients so that a request which *passed* validation would
/// reach `send`; the assertions therefore prove the throw happens before the transfer, not
/// merely that tracking was disabled.
@MainActor
final class RelevaClientValidationTests: XCTestCase {
    private var savedShared: RelevaClient?
    private var clients: [RelevaClient] = []

    override func setUp() {
        super.setUp()
        savedShared = RelevaClient.shared
        RelevaClient.shared = nil
    }

    override func tearDown() {
        clients.forEach { $0.shutdown() }
        clients.removeAll()
        RelevaClient.shared = savedShared
        super.tearDown()
    }

    private func makeClient(config: RelevaConfig = RelevaConfig(enableTracking: true, enablePushNotifications: false)) -> RelevaClient {
        let client = RelevaClient(realm: "test", accessToken: "test-token", config: config)
        clients.append(client)
        return client
    }

    // MARK: - TRK-06

    func testAnEmptySearchQueryIsRejectedBeforeTheNetwork() async {
        let client = makeClient()
        do {
            _ = try await client.trackSearchView(query: "")
            XCTFail("an empty query must not be sent")
        } catch {
            XCTAssertEqual(RelevaErrorKind(error), .missingRequiredField, "unexpected error: \(error)")
        }
    }

    // MARK: - CHK-03

    func testAnUnpaidOrEmptyCheckoutIsRejectedBeforeTheNetwork() async {
        let client = makeClient()

        do {
            _ = try await client.trackCheckoutSuccess(orderedCart: .active([CartProduct(id: "p1", price: 10)]))
            XCTFail("an unpaid cart must not be sent as a checkout")
        } catch {
            XCTAssertEqual(RelevaErrorKind(error), .invalidConfiguration, "unpaid cart: \(error)")
        }

        do {
            _ = try await client.trackCheckoutSuccess(orderedCart: .paid([], orderId: "order-1"))
            XCTFail("an empty cart must not be sent as a checkout")
        } catch {
            XCTAssertEqual(RelevaErrorKind(error), .invalidConfiguration, "empty cart: \(error)")
        }

        do {
            _ = try await client.trackCheckoutSuccess(orderedCart: .paid([CartProduct(id: "p1", price: 10)], orderId: ""))
            XCTFail("a checkout without an order id must not be sent")
        } catch {
            XCTAssertEqual(RelevaErrorKind(error), .missingRequiredField, "missing order id: \(error)")
        }
    }

    // MARK: - TOK-06

    func testRegisteringAPushTokenWithoutADeviceIdThrows() async {
        // The client reads its device id from UserDefaults.standard on init; make sure none is there.
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: "rlv_device_id")
        defaults.removeObject(forKey: "rlv_device_id")
        defer { if let saved = saved { defaults.set(saved, forKey: "rlv_device_id") } }

        let client = makeClient(config: RelevaConfig(enableTracking: false, enablePushNotifications: true))
        XCTAssertNil(client.getDeviceId())

        do {
            try await client.registerPushToken("x", deviceType: .ios)
            XCTFail("registering without a device id must throw")
        } catch {
            XCTAssertEqual(RelevaErrorKind(error), .missingRequiredField, "unexpected error: \(error)")
        }
    }

    // MARK: - CART-09

    func testCartTotalsHelpers() {
        let cart = Cart.active([
            CartProduct(id: "p1", price: 10, quantity: 2),
            CartProduct(id: "p2", price: 5.5, quantity: 1)
        ])
        XCTAssertFalse(cart.isEmpty)
        XCTAssertEqual(cart.itemCount, 2, "distinct products")
        XCTAssertEqual(cart.totalQuantity, 3)
        XCTAssertEqual(cart.totalPrice, 25.5, accuracy: 0.0001)
        XCTAssertTrue(Cart.empty().isEmpty)
        XCTAssertEqual(Cart.empty().totalPrice, 0)
    }

    // MARK: - SET-10

    func testAZeroTimeoutIsAcceptedByInitAndOnlyRejectedByValidate() {
        let config = RelevaConfig(enableTracking: false, enablePushNotifications: false, requestTimeoutInterval: 0)
        let client = makeClient(config: config)
        XCTAssertNotNil(client, "init does not validate the configuration")
        XCTAssertThrowsError(try config.validate()) { error in
            XCTAssertEqual(RelevaErrorKind(error), .invalidConfiguration, "unexpected error: \(error)")
        }
    }
}
