import XCTest
@testable import RelevaSDK

/// Decoding of the recommender section of a push response, plus the filtering and sorting
/// helpers that callers use on it.
///
/// `RelevaResponseTests` covers the envelope (`RelevaResponse.from(jsonData:)`); this suite
/// covers what the recommender and product decoders make of realistic payloads, including the
/// fields they deliberately drop and the timestamp formats they silently refuse.
final class RecommenderResponseTests: XCTestCase {

    // MARK: - Fixtures

    /// Shaped after a real recommender block: mixed availability, one discounted product,
    /// one product carrying only the required fields, and `meta`/`custom`/`data` objects that
    /// the decoders are known to drop.
    private let recommenderJSON = """
    {
      "token": "similar-products",
      "name": "Similar products",
      "meta": { "algorithm": "collaborative-filtering", "modelVersion": 3 },
      "tags": ["pdp", "below-fold"],
      "cssSelector": "#reco-similar",
      "displayStrategy": "carousel",
      "template": { "id": 42, "body": "<div>{{name}}</div>" },
      "response": [
        {
          "id": "SKU-1",
          "name": "Trail Runner",
          "price": 89.5,
          "available": true,
          "categories": ["shoes", "running"],
          "currency": "EUR",
          "locale": "en_GB",
          "description": "Lightweight trail shoe",
          "discount": 21.0,
          "discountPercent": 21.0,
          "discountPrice": 79.0,
          "listPrice": 100.0,
          "imageUrl": "https://cdn.example.com/sku-1.jpg",
          "url": "https://example.com/p/sku-1",
          "createdAt": "2024-01-15T10:30:00Z",
          "publishedAt": "2023-11-02T08:00:00Z",
          "updatedAt": "2024-01-15T10:30:00Z",
          "mergeContext": { "slot": "1", "source": "reco" },
          "custom": { "material": ["mesh"] },
          "data": { "warehouse": "DE1" }
        },
        {
          "id": "SKU-2",
          "name": "Canvas Sneaker",
          "price": 45.0,
          "available": false,
          "categories": ["shoes"],
          "currency": "EUR",
          "url": "https://example.com/p/sku-2",
          "publishedAt": "2024-01-15T10:30:00Z"
        },
        {
          "id": "SKU-3",
          "name": "Rain Jacket",
          "price": 120.0,
          "available": true,
          "categories": ["jackets"],
          "currency": "EUR",
          "discount": 0.0
        },
        {
          "id": "SKU-4",
          "name": "Cotton Cap",
          "price": 15.0
        }
      ]
    }
    """

    // MARK: - Helpers

    private func decodeRecommender(_ json: String) throws -> RecommenderResponse {
        return try JSONDecoder().decode(RecommenderResponse.self, from: Data(json.utf8))
    }

    private func decodeProduct(_ json: String) throws -> ProductRecommendation {
        return try JSONDecoder().decode(ProductRecommendation.self, from: Data(json.utf8))
    }

    /// A product carrying the three required fields (`price` is 10.0) plus `extraFields`.
    private func decodeProductWith(_ extraFields: String) throws -> ProductRecommendation {
        let required = "\"id\": \"SKU-X\", \"name\": \"Product X\", \"price\": 10.0"
        let fields = extraFields.isEmpty ? required : required + ", " + extraFields
        return try decodeProduct("{ \(fields) }")
    }

    // MARK: - Recommender decoding

    func testDecodesARealisticRecommenderPayload() throws {
        let recommender = try decodeRecommender(recommenderJSON)

        XCTAssertEqual(recommender.token, "similar-products")
        XCTAssertEqual(recommender.name, "Similar products")
        XCTAssertEqual(recommender.tags, ["pdp", "below-fold"])
        XCTAssertEqual(recommender.cssSelector, "#reco-similar")
        XCTAssertEqual(recommender.displayStrategy, "carousel")
        XCTAssertEqual(recommender.template?.id, 42)
        XCTAssertEqual(recommender.template?.body, "<div>{{name}}</div>")
        XCTAssertTrue(recommender.hasTemplate)
        XCTAssertTrue(recommender.hasProducts)
        XCTAssertEqual(recommender.productCount, 4)
        XCTAssertEqual(recommender.productIds, ["SKU-1", "SKU-2", "SKU-3", "SKU-4"], "decoding preserves API order")
    }

    func testMetaIsDroppedEvenWhenThePayloadCarriesIt() throws {
        let recommender = try decodeRecommender(recommenderJSON)

        XCTAssertNil(
            recommender.meta,
            "the decoder deliberately does not decode [String: Any]; callers must not expect meta"
        )
    }

    func testAMissingTokenAndNameDecodeToEmptyStringsRatherThanFailing() throws {
        let recommender = try decodeRecommender("""
        { "response": [] }
        """)

        XCTAssertEqual(recommender.token, "")
        XCTAssertEqual(recommender.name, "")
    }

    func testAMissingResponseArrayDecodesToNoProducts() throws {
        let recommender = try decodeRecommender("""
        { "token": "empty", "name": "Empty" }
        """)

        XCTAssertTrue(recommender.response.isEmpty)
        XCTAssertFalse(recommender.hasProducts)
        XCTAssertEqual(recommender.productCount, 0)
    }

    func testExplicitNullsOnTheRecommenderDecodeAsAbsent() throws {
        let recommender = try decodeRecommender("""
        {
          "token": "t",
          "name": "n",
          "meta": null,
          "tags": null,
          "cssSelector": null,
          "displayStrategy": null,
          "template": null,
          "response": null
        }
        """)

        XCTAssertNil(recommender.tags)
        XCTAssertNil(recommender.cssSelector)
        XCTAssertNil(recommender.displayStrategy)
        XCTAssertNil(recommender.template)
        XCTAssertFalse(recommender.hasTags)
        XCTAssertFalse(recommender.hasTemplate)
        XCTAssertTrue(recommender.response.isEmpty, "a null response must not fail the whole decode")
    }

    func testUnknownRecommenderKeysAreIgnored() throws {
        let recommender = try decodeRecommender("""
        {
          "token": "t",
          "name": "n",
          "experimentId": 7,
          "somethingTheBackendAddedLater": { "nested": [1, 2, 3] },
          "response": []
        }
        """)

        XCTAssertEqual(recommender.token, "t", "a new backend field must not break existing clients")
    }

    func testRecommendersAreEqualByTokenAndNameAlone() throws {
        let withProducts = try decodeRecommender("""
        { "token": "t", "name": "n", "response": [{ "id": "A", "name": "A", "price": 1.0 }] }
        """)
        let withoutProducts = try decodeRecommender("""
        { "token": "t", "name": "n", "response": [] }
        """)

        XCTAssertEqual(
            withProducts,
            withoutProducts,
            "Equatable compares only token and name; products are not part of identity"
        )
    }

    // MARK: - Product decoding

    func testDecodesAFullyPopulatedProduct() throws {
        let recommender = try decodeRecommender(recommenderJSON)
        let decoded = try XCTUnwrap(recommender.response.first)

        XCTAssertEqual(decoded.id, "SKU-1")
        XCTAssertEqual(decoded.name, "Trail Runner")
        XCTAssertEqual(decoded.price, 89.5)
        XCTAssertTrue(decoded.available)
        XCTAssertEqual(decoded.categories, ["shoes", "running"])
        XCTAssertEqual(decoded.currency, "EUR")
        XCTAssertEqual(decoded.locale, "en_GB")
        XCTAssertEqual(decoded.description, "Lightweight trail shoe")
        XCTAssertEqual(decoded.discount, 21.0)
        XCTAssertEqual(decoded.discountPercent, 21.0)
        XCTAssertEqual(decoded.discountPrice, 79.0)
        XCTAssertEqual(decoded.listPrice, 100.0)
        XCTAssertEqual(decoded.imageUrl, "https://cdn.example.com/sku-1.jpg")
        XCTAssertEqual(decoded.url, "https://example.com/p/sku-1")
        XCTAssertEqual(decoded.mergeContext, ["slot": "1", "source": "reco"])
    }

    func testTheRequiredProductFieldsAreEnforced() {
        XCTAssertThrowsError(
            try decodeProduct("""
            { "name": "no id", "price": 1.0 }
            """),
            "a product without an id must not decode"
        )
        XCTAssertThrowsError(
            try decodeProduct("""
            { "id": "A", "price": 1.0 }
            """),
            "a product without a name must not decode"
        )
        XCTAssertThrowsError(
            try decodeProduct("""
            { "id": "A", "name": "no price" }
            """),
            "a product without a price must not decode"
        )
    }

    func testANonNumericPriceIsRejectedRatherThanCoerced() {
        XCTAssertThrowsError(
            try decodeProduct("""
            { "id": "A", "name": "A", "price": "12.99" }
            """),
            "price decodes as a Double, so a stringified price is a contract break rather than a silent zero"
        )
    }

    func testAvailableDefaultsToFalseWhenAbsent() throws {
        XCTAssertFalse(try decodeProductWith("").available, "an unknown availability must not be optimistic")
        XCTAssertTrue(try decodeProductWith("\"available\": true").available)
    }

    func testCustomAndDataAreDroppedEvenWhenThePayloadCarriesThem() throws {
        let decoded = try decodeProductWith("\"custom\": { \"material\": [\"mesh\"] }, \"data\": { \"wh\": \"DE1\" }")

        XCTAssertNil(decoded.custom, "the decoder deliberately does not decode [String: Any]")
        XCTAssertNil(decoded.data, "the decoder deliberately does not decode [String: Any]")
    }

    func testExplicitNullProductFieldsDecodeAsNil() throws {
        let decoded = try decodeProduct("""
        {
          "id": "A",
          "name": "A",
          "price": 1.0,
          "available": null,
          "categories": null,
          "currency": null,
          "description": null,
          "discount": null,
          "discountPercent": null,
          "discountPrice": null,
          "imageUrl": null,
          "listPrice": null,
          "locale": null,
          "createdAt": null,
          "publishedAt": null,
          "updatedAt": null,
          "url": null
        }
        """)

        XCTAssertFalse(decoded.available, "a null availability falls back to the same default as an absent one")
        XCTAssertNil(decoded.categories)
        XCTAssertNil(decoded.currency)
        XCTAssertNil(decoded.description)
        XCTAssertNil(decoded.discount)
        XCTAssertNil(decoded.discountPercent)
        XCTAssertNil(decoded.discountPrice)
        XCTAssertNil(decoded.imageUrl)
        XCTAssertNil(decoded.listPrice)
        XCTAssertNil(decoded.locale)
        XCTAssertNil(decoded.createdAt)
        XCTAssertNil(decoded.publishedAt)
        XCTAssertNil(decoded.updatedAt)
        XCTAssertNil(decoded.url)
    }

    func testUnknownProductKeysAreIgnored() throws {
        let decoded = try decodeProductWith("\"loyaltyPoints\": 120, \"badges\": [\"new\"]")

        XCTAssertEqual(decoded.id, "SKU-X", "a new backend field must not break existing clients")
    }

    func testProductsAreEqualByIdAlone() throws {
        let first = try decodeProduct("""
        { "id": "A", "name": "First", "price": 1.0 }
        """)
        let second = try decodeProduct("""
        { "id": "A", "name": "Second", "price": 999.0 }
        """)

        XCTAssertEqual(first, second, "Equatable compares only the id, so XCTAssertEqual cannot detect field drift")
    }

    // MARK: - Timestamps

    func testInternetDateTimeTimestampsAreParsed() throws {
        let recommender = try decodeRecommender(recommenderJSON)
        let decoded = try XCTUnwrap(recommender.response.first)

        // 2024-01-15T10:30:00Z and 2023-11-02T08:00:00Z as seconds since the epoch.
        XCTAssertEqual(try XCTUnwrap(decoded.createdAt).timeIntervalSince1970, 1_705_314_600, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(decoded.publishedAt).timeIntervalSince1970, 1_698_912_000, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(decoded.updatedAt).timeIntervalSince1970, 1_705_314_600, accuracy: 0.001)
    }

    func testFractionalSecondTimestampsDecodeAsNilRatherThanThrowing() throws {
        let decoded = try decodeProductWith("\"createdAt\": \"2024-01-15T10:30:00.123Z\"")

        XCTAssertNil(
            decoded.createdAt,
            "a default ISO8601DateFormatter rejects fractional seconds and the decoder swallows that as nil"
        )
    }

    func testAnUnparseableTimestampDecodesAsNilRatherThanThrowing() throws {
        let decoded = try decodeProductWith("\"publishedAt\": \"15/01/2024\"")

        XCTAssertNil(decoded.publishedAt)
    }

    // MARK: - mergeContext

    func testAllStringMergeContextDecodesDirectly() throws {
        let decoded = try decodeProductWith("\"mergeContext\": { \"slot\": \"3\", \"source\": \"reco\" }")

        XCTAssertEqual(decoded.mergeContext, ["slot": "3", "source": "reco"])
    }

    func testMixedTypeMergeContextValuesAreStringified() throws {
        let decoded = try decodeProductWith(
            "\"mergeContext\": { \"slot\": \"hero\", \"rank\": 3, \"score\": 4.5, \"fallback\": true }"
        )

        XCTAssertEqual(
            decoded.mergeContext,
            ["slot": "hero", "rank": "3", "score": "4.5", "fallback": "true"],
            "mergeContext is typed [String: String], so non-string values are converted rather than dropped"
        )
    }

    func testMergeContextOfOnlyNullValuesDecodesAsNil() throws {
        let decoded = try decodeProductWith("\"mergeContext\": { \"slot\": null }")

        XCTAssertNil(decoded.mergeContext, "nothing survived the conversion, so the whole dictionary is nil")
    }

    func testAnExplicitlyNullMergeContextDecodesAsNil() throws {
        let decoded = try decodeProductWith("\"mergeContext\": null")

        XCTAssertNil(decoded.mergeContext)
    }

    // MARK: - Derived prices

    func testBestPricePrefersTheDiscountedPrice() throws {
        XCTAssertEqual(try decodeProductWith("\"discountPrice\": 7.5").bestPrice, 7.5)
        XCTAssertEqual(try decodeProductWith("").bestPrice, 10.0, "without a discount price the plain price stands")
    }

    func testHasDiscountRequiresAPositiveDiscount() throws {
        XCTAssertFalse(try decodeProductWith("").hasDiscount, "an absent discount is not a discount")
        XCTAssertFalse(try decodeProductWith("\"discount\": 0.0").hasDiscount, "a zero discount is not a discount")
        XCTAssertTrue(try decodeProductWith("\"discount\": 2.5").hasDiscount)
    }

    func testCalculatedDiscountPercentIsDerivedFromTheListPrice() throws {
        let fromDiscountPrice = try decodeProductWith("\"listPrice\": 100.0, \"discountPrice\": 75.0")
        XCTAssertEqual(try XCTUnwrap(fromDiscountPrice.calculatedDiscountPercent), 25.0, accuracy: 0.0001)

        // The helper fixture prices the product at 10.0, so a list price of 20.0 is half off.
        let fromPrice = try decodeProductWith("\"listPrice\": 20.0")
        XCTAssertEqual(try XCTUnwrap(fromPrice.calculatedDiscountPercent), 50.0, accuracy: 0.0001)
    }

    func testCalculatedDiscountPercentFallsBackToTheReportedPercentWithoutAUsableListPrice() throws {
        XCTAssertEqual(try decodeProductWith("\"discountPercent\": 30.0").calculatedDiscountPercent, 30.0)
        XCTAssertEqual(
            try decodeProductWith("\"listPrice\": 0.0, \"discountPercent\": 30.0").calculatedDiscountPercent,
            30.0,
            "a zero list price must not divide by zero"
        )
        XCTAssertNil(try decodeProductWith("").calculatedDiscountPercent)
    }

    func testHasImageAndHasUrlTreatEmptyStringsAsMissing() throws {
        XCTAssertFalse(try decodeProductWith("").hasImage)
        XCTAssertFalse(try decodeProductWith("\"imageUrl\": \"\"").hasImage, "an empty URL is nothing to render")
        XCTAssertTrue(try decodeProductWith("\"imageUrl\": \"https://cdn.example.com/a.jpg\"").hasImage)

        XCTAssertFalse(try decodeProductWith("").hasUrl)
        XCTAssertFalse(try decodeProductWith("\"url\": \"\"").hasUrl)
        XCTAssertTrue(try decodeProductWith("\"url\": \"https://example.com/p/a\"").hasUrl)
    }

    // MARK: - Recommender queries

    func testRecommenderFiltersProducts() throws {
        let recommender = try decodeRecommender(recommenderJSON)

        XCTAssertEqual(recommender.availableProducts().map { $0.id }, ["SKU-1", "SKU-3"])
        XCTAssertEqual(
            recommender.discountedProducts().map { $0.id },
            ["SKU-1"],
            "SKU-3 reports a zero discount, which is not a discount"
        )
        XCTAssertEqual(recommender.products(withIds: ["SKU-3", "SKU-404"]).map { $0.id }, ["SKU-3"])
        XCTAssertEqual(
            recommender.products(inPriceRange: 40.0, maxPrice: 100.0).map { $0.id },
            ["SKU-1", "SKU-2"],
            "the range is matched against bestPrice, so SKU-1 qualifies on its 79.0 discount price"
        )
    }

    func testRecommenderTagLookup() throws {
        let recommender = try decodeRecommender(recommenderJSON)

        XCTAssertTrue(recommender.hasTags)
        XCTAssertTrue(recommender.hasTag("pdp"))
        XCTAssertFalse(recommender.hasTag("plp"))
    }

    func testRecommenderSortsProductsByPriceAndName() throws {
        let recommender = try decodeRecommender(recommenderJSON)

        XCTAssertEqual(
            recommender.sortedProducts(by: .priceAscending).map { $0.id },
            ["SKU-4", "SKU-2", "SKU-1", "SKU-3"],
            "sorting uses price, not bestPrice"
        )
        XCTAssertEqual(
            recommender.sortedProducts(by: .priceDescending).map { $0.id },
            ["SKU-3", "SKU-1", "SKU-2", "SKU-4"]
        )
        XCTAssertEqual(
            recommender.sortedProducts(by: .nameAscending).map { $0.id },
            ["SKU-2", "SKU-4", "SKU-3", "SKU-1"]
        )
        XCTAssertEqual(
            recommender.sortedProducts(by: .nameDescending).map { $0.id },
            ["SKU-1", "SKU-3", "SKU-4", "SKU-2"]
        )
        XCTAssertEqual(
            recommender.sortedProducts(by: .discountHighestFirst).first?.id,
            "SKU-1",
            "only SKU-1 has a computable discount; the rest tie at zero and their relative order is undefined"
        )
    }

    func testRecommenderSortsDatedProductsByPublicationDate() throws {
        // Every product here carries publishedAt: the comparator has no defined order otherwise.
        let recommender = try decodeRecommender("""
        {
          "token": "t",
          "name": "n",
          "response": [
            { "id": "MID", "name": "Mid", "price": 1.0, "publishedAt": "2023-11-02T08:00:00Z" },
            { "id": "NEW", "name": "New", "price": 1.0, "publishedAt": "2024-01-15T10:30:00Z" },
            { "id": "OLD", "name": "Old", "price": 1.0, "publishedAt": "2022-06-01T00:00:00Z" }
          ]
        }
        """)

        XCTAssertEqual(recommender.sortedProducts(by: .newest).map { $0.id }, ["NEW", "MID", "OLD"])
        XCTAssertEqual(recommender.sortedProducts(by: .oldest).map { $0.id }, ["OLD", "MID", "NEW"])
    }

    // MARK: - Collection helpers

    func testProductArrayHelpers() throws {
        let products = try decodeRecommender(recommenderJSON).response

        XCTAssertEqual(products.available.map { $0.id }, ["SKU-1", "SKU-3"])
        XCTAssertEqual(products.discounted.map { $0.id }, ["SKU-1"])
        XCTAssertEqual(products.sortedByPrice().map { $0.id }, ["SKU-4", "SKU-2", "SKU-1", "SKU-3"])
        XCTAssertEqual(products.sortedByPrice(ascending: false).map { $0.id }, ["SKU-3", "SKU-1", "SKU-2", "SKU-4"])
        XCTAssertEqual(products.sortedByDiscount().first?.id, "SKU-1")
        XCTAssertEqual(products.inCategory("shoes").map { $0.id }, ["SKU-1", "SKU-2"])
        XCTAssertTrue(
            products.inCategory("nonexistent").isEmpty,
            "a product without categories must not match a category filter"
        )
        XCTAssertEqual(products.inPriceRange(min: 40.0, max: 100.0).map { $0.id }, ["SKU-1", "SKU-2"])
    }

    func testRecommenderArrayHelpers() throws {
        let bestsellers = try decodeRecommender("""
        {
          "token": "bestsellers",
          "name": "Bestsellers",
          "tags": ["home", "pdp"],
          "response": [{ "id": "SKU-9", "name": "Nine", "price": 9.0 }]
        }
        """)
        let similar = try decodeRecommender(recommenderJSON)
        let recommenders = [similar, bestsellers]

        XCTAssertEqual(recommenders.withTag("pdp").map { $0.token }, ["similar-products", "bestsellers"])
        XCTAssertEqual(recommenders.withTag("home").map { $0.token }, ["bestsellers"])
        XCTAssertEqual(recommenders.withToken("bestsellers")?.name, "Bestsellers")
        XCTAssertNil(recommenders.withToken("missing"))
        XCTAssertEqual(recommenders.withName("Similar products")?.token, "similar-products")
        XCTAssertEqual(recommenders.allTags, ["pdp", "below-fold", "home"])
        XCTAssertEqual(recommenders.totalProductCount, 5)
    }

    // MARK: - Encoding

    func testEncodingOmitsTheFieldsTheDecoderNeverPopulates() throws {
        let recommender = try decodeRecommender(recommenderJSON)

        let encoded = try JSONEncoder().encode(recommender)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertNil(object["meta"], "meta is never decoded, so re-encoding cannot restore it")

        let products = try XCTUnwrap(object["response"] as? [[String: Any]])
        let first = try XCTUnwrap(products.first)
        XCTAssertNil(first["custom"], "custom is never decoded, so re-encoding cannot restore it")
        XCTAssertNil(first["data"], "data is never decoded, so re-encoding cannot restore it")
        XCTAssertEqual(first["createdAt"] as? String, "2024-01-15T10:30:00Z", "dates round-trip as internet date-time")
        XCTAssertEqual(first["mergeContext"] as? [String: String], ["slot": "1", "source": "reco"])
    }

    func testEncodingAlwaysWritesTheRequiredProductFields() throws {
        let minimal = try decodeProductWith("")

        let encoded = try JSONEncoder().encode(minimal)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual(object["id"] as? String, "SKU-X")
        XCTAssertEqual(object["name"] as? String, "Product X")
        XCTAssertEqual(object["price"] as? Double, 10.0)
        XCTAssertEqual(object["available"] as? Bool, false, "availability is always written, even at its default")
        XCTAssertNil(object["createdAt"], "an absent date must not be encoded")
    }

    func testEncodedProductsDecodeBackToTheSameProducts() throws {
        let original = try decodeRecommender(recommenderJSON)

        let round = try JSONDecoder().decode(RecommenderResponse.self, from: JSONEncoder().encode(original))

        XCTAssertEqual(round.productIds, original.productIds)
        XCTAssertEqual(round.template, original.template)
        XCTAssertEqual(round.tags, original.tags)
        XCTAssertEqual(round.response.first?.createdAt, original.response.first?.createdAt)
    }
}
