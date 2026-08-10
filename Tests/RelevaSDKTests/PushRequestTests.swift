import XCTest
@testable import RelevaSDK

/// Payload construction for `PushRequest`: which keys land under `page`, which land at the
/// top level, and what the factory methods pre-fill.
///
/// `PushPayloadIdentityTests` owns the identity/merge contract at the `buildPushPayload`
/// seam; this suite covers the builder side of it.
final class PushRequestTests: XCTestCase {

    // MARK: - Helpers

    private func pageContext(_ request: PushRequest) throws -> [String: Any] {
        return try XCTUnwrap(request.toDict()["page"] as? [String: Any], "expected a page dictionary")
    }

    // MARK: - Page context

    func testAnEmptyRequestCarriesAnEmptyPage() throws {
        let dict = PushRequest().toDict()

        XCTAssertEqual(dict.keys.sorted(), ["page"], "a fresh request has nothing but the page container")
        XCTAssertTrue(try pageContext(PushRequest()).isEmpty)
    }

    func testPageBuildersAccumulateUnderPage() throws {
        let request = PushRequest()
            .screenView("home")
            .pageUrl("https://example.com/home")
            .locale("en_US")
            .currency("USD")
            .search("running shoes")

        let page = try pageContext(request)
        XCTAssertEqual(page["token"] as? String, "home")
        XCTAssertEqual(page["url"] as? String, "https://example.com/home")
        XCTAssertEqual(page["locale"] as? String, "en_US")
        XCTAssertEqual(page["currency"] as? String, "USD")
        XCTAssertEqual(page["query"] as? String, "running shoes")
    }

    func testBuildersReturnTheSameInstanceSoChainingAndStatementsAgree() throws {
        let request = PushRequest()
        let returned = request.screenView("home")
        request.locale("en_US")

        XCTAssertTrue(returned === request, "the fluent builders mutate and return self")
        XCTAssertEqual(try pageContext(request)["locale"] as? String, "en_US")
    }

    func testLatestValueWinsForARepeatedPageKey() throws {
        let request = PushRequest().screenView("home").screenView("product")

        XCTAssertEqual(try pageContext(request)["token"] as? String, "product")
    }

    // MARK: - Product view

    func testProductViewIsStoredAtTheTopLevelNotUnderPage() throws {
        let product = ViewedProduct(id: "p1")
            .withStringField(key: "size", values: ["XL"])

        let dict = PushRequest().productView(product).toDict()

        let productDict = try XCTUnwrap(dict["product"] as? [String: Any])
        XCTAssertEqual(productDict["id"] as? String, "p1")
        XCTAssertNil(try pageContext(PushRequest().productView(product))["product"], "product is not page context")

        let custom = try XCTUnwrap(productDict["custom"] as? [String: Any])
        let stringFields = try XCTUnwrap(custom["string"] as? [[String: Any]])
        XCTAssertEqual(stringFields.first?["key"] as? String, "size")
        XCTAssertEqual(stringFields.first?["values"] as? [String], ["XL"])
    }

    // MARK: - Listing context

    func testPageProductIdsAndCategoriesAreSetWhenNonEmpty() throws {
        let request = PushRequest()
            .pageProductIds(["p1", "p2"])
            .pageCategories(["shoes"])

        let page = try pageContext(request)
        XCTAssertEqual(page["ids"] as? [String], ["p1", "p2"])
        XCTAssertEqual(page["categories"] as? [String], ["shoes"])
    }

    func testEmptyProductIdsAndCategoriesAreOmittedRatherThanSentEmpty() throws {
        let request = PushRequest()
            .pageProductIds([])
            .pageCategories([])

        let page = try pageContext(request)
        XCTAssertNil(page["ids"] as? [String], "an empty listing must not send ids")
        XCTAssertNil(page["categories"] as? [String], "an empty category list must not send categories")
    }

    func testEmptyProductIdsClearAPreviouslySetListing() throws {
        let request = PushRequest().pageProductIds(["p1"])
        XCTAssertEqual(try pageContext(request)["ids"] as? [String], ["p1"])

        request.pageProductIds([])

        XCTAssertNil(try pageContext(request)["ids"] as? [String])
    }

    func testPageBlocksNestTagsUnderBlocks() throws {
        let request = PushRequest().pageBlocks(tags: ["hero", "footer"])

        let blocks = try XCTUnwrap(try pageContext(request)["blocks"] as? [String: Any])
        XCTAssertEqual(blocks["tags"] as? [String], ["hero", "footer"])
    }

    // MARK: - Filters

    func testPageFilterEmbedsTheEncodedFilter() throws {
        let request = PushRequest().pageFilter(SimpleFilter.priceRange(minPrice: 10, maxPrice: 20))

        let filter = try XCTUnwrap(try pageContext(request)["filter"] as? [String: Any])
        XCTAssertEqual(filter["key"] as? String, "price")
        XCTAssertEqual(filter["operator"] as? String, "gte,lte")
        XCTAssertEqual(filter["value"] as? String, "10.0,20.0")
    }

    func testPageFilterAcceptsANestedFilter() throws {
        let request = PushRequest().pageFilter(NestedFilter.brands(["A", "B"]))

        let filter = try XCTUnwrap(try pageContext(request)["filter"] as? [String: Any])
        XCTAssertEqual(filter["operator"] as? String, "or")
        XCTAssertEqual((filter["nested"] as? [[String: Any]])?.count, 2)
    }

    // MARK: - Custom events

    func testCustomEventsAreEncodedAtTheTopLevel() throws {
        let event = CustomEvent(action: CustomEvent.Actions.addToCart, tags: ["promo"])
            .withProduct(id: "p1", quantity: 2)

        let dict = PushRequest().customEvents([event]).toDict()

        let events = try XCTUnwrap(dict["events"] as? [[String: Any]])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0]["action"] as? String, "add_to_cart")
        XCTAssertEqual(events[0]["tags"] as? [String], ["promo"])
        XCTAssertEqual((events[0]["products"] as? [[String: Any]])?.first?["id"] as? String, "p1")
    }

    func testAnEmptyEventListIsOmitted() {
        let dict = PushRequest().customEvents([]).toDict()

        XCTAssertNil(dict["events"] as? [[String: Any]], "an empty events array must not be sent")
    }

    func testAddCustomEventAppendsToTheExistingEvents() throws {
        let request = PushRequest()
            .customEvents([CustomEvent(action: "first")])
            .addCustomEvent(CustomEvent(action: "second"))

        let events = try XCTUnwrap(request.toDict()["events"] as? [[String: Any]])
        XCTAssertEqual(events.compactMap { $0["action"] as? String }, ["first", "second"])
    }

    func testAddCustomEventStartsAListWhenNoneExists() throws {
        let request = PushRequest().addCustomEvent(CustomEvent(action: "only"))

        let events = try XCTUnwrap(request.toDict()["events"] as? [[String: Any]])
        XCTAssertEqual(events.count, 1)
    }

    // MARK: - Cart

    func testCartIsHeldAsideRatherThanEncodedIntoThePayload() {
        let cart = Cart.paid([CartProduct(id: "p1", price: 10, quantity: 1)], orderId: "order-1")

        let request = PushRequest().setCart(cart)

        XCTAssertEqual(request.cart, cart, "the client reads .cart and sends it via the context builder")
        XCTAssertNil(request.toDict()["cart"], "the cart is not part of the request payload")
    }

    // MARK: - Validation

    func testValidateAcceptsAnEmptyRequest() {
        XCTAssertNoThrow(try PushRequest().validate())
    }

    func testValidateRejectsAnEmptyEventsArrayThatWasExplicitlySet() {
        let request = PushRequest()
        request.addCustomEvent(CustomEvent(action: "a"))
        request.customEvents([])

        // customEvents([]) removes the key, so nothing is left to reject.
        XCTAssertNoThrow(try request.validate())
    }

    func testValidatePropagatesCartProductValidationFailures() {
        let request = PushRequest().setCart(Cart.active([CartProduct(id: "", price: 1)]))

        XCTAssertThrowsError(try request.validate()) { error in
            XCTAssertEqual(RelevaErrorKind(error), .missingRequiredField, "unexpected error: \(error)")
        }
    }

    func testValidateRejectsANegativeCartPrice() {
        let request = PushRequest().setCart(Cart.active([CartProduct(id: "p1", price: -1)]))

        XCTAssertThrowsError(try request.validate()) { error in
            XCTAssertEqual(RelevaErrorKind(error), .invalidConfiguration, "unexpected error: \(error)")
        }
    }

    // MARK: - Factory methods

    func testForScreenViewSetsOnlyTheToken() throws {
        let request = PushRequest.forScreenView("home")

        XCTAssertEqual(try pageContext(request)["token"] as? String, "home")
        XCTAssertEqual(request.toDict().keys.sorted(), ["page"])
    }

    func testForProductViewSetsTheProductAndOptionalScreenToken() throws {
        let withoutToken = PushRequest.forProductView(ViewedProduct(id: "p1"))
        let withToken = PushRequest.forProductView(ViewedProduct(id: "p1"), screenToken: "product")

        XCTAssertNotNil(withoutToken.toDict()["product"])
        XCTAssertNil(try pageContext(withoutToken)["token"])
        XCTAssertEqual(try pageContext(withToken)["token"] as? String, "product")
    }

    func testForSearchSetsTheQueryAndOnlyIncludesResultIdsWhenPresent() throws {
        let plain = PushRequest.forSearch(query: "shoes")
        let withResults = PushRequest.forSearch(
            query: "shoes",
            resultProductIds: ["p1", "p2"],
            screenToken: "search"
        )

        XCTAssertEqual(try pageContext(plain)["query"] as? String, "shoes")
        XCTAssertNil(try pageContext(plain)["ids"] as? [String])

        XCTAssertEqual(try pageContext(withResults)["ids"] as? [String], ["p1", "p2"])
        XCTAssertEqual(try pageContext(withResults)["token"] as? String, "search")
    }

    func testForCheckoutSuccessCarriesTheOrderedCart() throws {
        let cart = Cart.paid([CartProduct(id: "p1", price: 10, quantity: 1)], orderId: "order-1")

        let request = PushRequest.forCheckoutSuccess(orderedCart: cart, screenToken: "thank-you")

        XCTAssertEqual(request.cart, cart)
        XCTAssertEqual(try pageContext(request)["token"] as? String, "thank-you")
    }

    func testForCustomEventWrapsTheSingleEvent() throws {
        let request = PushRequest.forCustomEvent(CustomEvent(action: "share_product"), screenToken: "product")

        let events = try XCTUnwrap(request.toDict()["events"] as? [[String: Any]])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0]["action"] as? String, "share_product")
        XCTAssertEqual(try pageContext(request)["token"] as? String, "product")
    }

    // MARK: - Serializability

    func testAFullyPopulatedRequestIsJsonSerializable() throws {
        let request = PushRequest()
            .screenView("listing")
            .pageUrl("https://example.com/listing")
            .locale("en_US")
            .currency("USD")
            .pageProductIds(["p1", "p2"])
            .pageCategories(["shoes"])
            .pageFilter(NestedFilter.priceAndBrand(minPrice: 10, maxPrice: 20, brand: "Acme"))
            .pageBlocks(tags: ["hero"])
            .productView(ViewedProduct(id: "p1"))
            .customEvents([CustomEvent(action: "add_to_cart").withProduct(id: "p1", quantity: 1)])

        let payload = request.toDict()
        XCTAssertTrue(
            JSONSerialization.isValidJSONObject(payload),
            "NetworkService serializes this dictionary directly, so it must contain only JSON types"
        )
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: payload))
    }
}
