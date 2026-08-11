import XCTest
@testable import RelevaSDK

/// `ScreenViewRequest`, `SearchRequest` and `CheckoutSuccessRequest` describe a push
/// declaratively and turn into a `PushRequest` through `pushRequest`.
///
/// Before 4.0.0 they were `PushRequest` subclasses that applied themselves to `self` inside
/// `init`, so these assertions pin the payload they produce across the move to value types —
/// the client reads nothing off them but `pushRequest`.
final class TrackingRequestConversionTests: XCTestCase {

    // MARK: - Helpers

    private func pageContext<Request: PushRequestConvertible>(_ request: Request) throws -> [String: Any] {
        return try XCTUnwrap(request.pushRequest.toDict()["page"] as? [String: Any], "expected a page dictionary")
    }

    // MARK: - Screen view

    func testScreenViewRequestPutsEverythingItCarriesUnderPage() throws {
        let request = ScreenViewRequest(
            screenToken: "listing",
            productIds: ["p1", "p2"],
            categories: ["shoes"],
            filter: SimpleFilter.priceRange(minPrice: 10, maxPrice: 20),
            blocks: ["tags": ["hero"]]
        )

        let page = try pageContext(request)
        XCTAssertEqual(page["token"] as? String, "listing")
        XCTAssertEqual(page["ids"] as? [String], ["p1", "p2"])
        XCTAssertEqual(page["categories"] as? [String], ["shoes"])
        XCTAssertEqual((page["filter"] as? [String: Any])?["key"] as? String, "price")
        XCTAssertEqual((page["blocks"] as? [String: Any])?["tags"] as? [String], ["hero"])
    }

    func testAnAllNilScreenViewRequestConvertsToAnEmptyPage() throws {
        // The shape `RelevaClient` uses to sync a cart change without any page context.
        let request = ScreenViewRequest(screenToken: nil, productIds: nil, categories: nil, filter: nil)

        XCTAssertTrue(try pageContext(request).isEmpty)
        XCTAssertEqual(request.pushRequest.toDict().keys.sorted(), ["page"])
        XCTAssertNil(request.pushRequest.cart, "a screen view never sets a cart of its own")
    }

    func testProductListingFactoryFillsIdsAndToken() throws {
        let page = try pageContext(ScreenViewRequest.productListing(screenToken: "listing", productIds: ["p1"]))

        XCTAssertEqual(page["token"] as? String, "listing")
        XCTAssertEqual(page["ids"] as? [String], ["p1"])
    }

    // MARK: - Search

    func testSearchRequestCarriesTheQueryAndResultIds() throws {
        let page = try pageContext(SearchRequest.searchWithResults(query: "shoes", resultProductIds: ["p1", "p2"]))

        XCTAssertEqual(page["query"] as? String, "shoes")
        XCTAssertEqual(page["ids"] as? [String], ["p1", "p2"])
    }

    func testASearchWithNoResultsOmitsTheIds() throws {
        let page = try pageContext(SearchRequest.emptySearch(query: "nothing"))

        XCTAssertEqual(page["query"] as? String, "nothing")
        XCTAssertNil(page["ids"] as? [String], "no results must not send an empty ids array")
    }

    // MARK: - Checkout success

    func testCheckoutSuccessRequestHoldsTheCartAsideAndThePageToken() throws {
        let cart = Cart.paid([CartProduct(id: "p1", price: 10, quantity: 2)], orderId: "order-1")

        let request = CheckoutSuccessRequest(screenToken: "thank-you", orderedCart: cart)

        XCTAssertEqual(request.pushRequest.cart, cart, "the client reads .cart off the converted request")
        XCTAssertNil(request.pushRequest.toDict()["cart"], "the cart travels in the context, not the payload")
        XCTAssertEqual(try pageContext(request)["token"] as? String, "thank-you")
        XCTAssertEqual(request.orderId, "order-1")
        XCTAssertEqual(request.orderValue, 20)
        XCTAssertEqual(request.itemCount, 1)
    }

    func testMinimalCheckoutSuccessFactoryProducesAPaidCartAndNoPageContext() throws {
        let request = CheckoutSuccessRequest.minimal(orderId: "order-2", products: [CartProduct(id: "p1", price: 5)])

        XCTAssertTrue(try pageContext(request).isEmpty, "minimal() sets no screen token")
        XCTAssertEqual(request.pushRequest.cart?.orderId, "order-2")
        XCTAssertEqual(request.pushRequest.cart?.cartPaid, true)
        XCTAssertNoThrow(try request.validate())
    }

    // MARK: - Validation

    func testEachRequestKeepsItsOwnValidationRulesBehindTheProtocol() {
        // Held as the protocol so a stricter `validate()` has to be reached by dynamic
        // dispatch rather than by the caller knowing the concrete type.
        let queryless: PushRequestConvertible = SearchRequest(query: nil)
        let unpaid: PushRequestConvertible = CheckoutSuccessRequest(
            orderedCart: Cart.active([CartProduct(id: "p1", price: 10)])
        )

        XCTAssertThrowsError(try queryless.validate()) { error in
            XCTAssertEqual(RelevaErrorKind(error), .missingRequiredField, "unexpected error: \(error)")
        }
        XCTAssertThrowsError(try unpaid.validate()) { error in
            XCTAssertEqual(RelevaErrorKind(error), .invalidConfiguration, "unexpected error: \(error)")
        }
    }

    func testAScreenViewRequestValidatesThroughTheDefaultImplementation() {
        let request: PushRequestConvertible = ScreenViewRequest(screenToken: "home")

        XCTAssertNoThrow(try request.validate(), "a screen view adds no rules of its own")
    }
}
