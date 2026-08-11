import XCTest
@testable import RelevaSDK

/// Covers the wire shape produced by the filter models.
///
/// `toDict()` is what actually reaches the API (`PushRequest.pageFilter` embeds it, and
/// `NetworkService` JSON-encodes the result), so these tests assert on that rather than
/// on the `Codable` conformance.
final class FilterSerializationTests: XCTestCase {
    // MARK: - Helpers

    private func string(_ dict: [String: Any], _ key: String) throws -> String {
        try XCTUnwrap(dict[key] as? String, "expected a String under \"\(key)\" in \(dict)")
    }

    private func nested(_ dict: [String: Any]) throws -> [[String: Any]] {
        try XCTUnwrap(dict["nested"] as? [[String: Any]], "expected a nested array in \(dict)")
    }

    // MARK: - SimpleFilter encoding

    func testSimpleFilterEncodesEveryOperatorRawValue() throws {
        let expected: [FilterOperator: String] = [
            .eq: "eq",
            .lt: "lt",
            .gt: "gt",
            .lte: "lte",
            .gte: "gte",
            .gteLte: "gte,lte",
            .gteLt: "gte,lt",
            .gtLte: "gt,lte",
            .gtLt: "gt,lt"
        ]

        XCTAssertEqual(
            Set(expected.keys),
            Set(FilterOperator.allCases),
            "a new FilterOperator case needs its encoded value pinned here"
        )

        for (op, wireValue) in expected {
            let dict = SimpleFilter(key: "price", operator: op, value: "1,2", action: .include).toDict()
            XCTAssertEqual(try string(dict, "operator"), wireValue, "wrong encoding for \(op)")
        }
    }

    func testSimpleFilterEncodesEveryActionRawValue() throws {
        let expected: [FilterAction: String] = [
            .include: "include",
            .exclude: "exclude",
            .bury: "bury",
            .boost: "boost"
        ]

        XCTAssertEqual(
            Set(expected.keys),
            Set(FilterAction.allCases),
            "a new FilterAction case needs its encoded value pinned here"
        )

        for (action, wireValue) in expected {
            let dict = SimpleFilter(key: "brand", operator: .eq, value: "acme", action: action).toDict()
            XCTAssertEqual(try string(dict, "action"), wireValue, "wrong encoding for \(action)")
        }
    }

    func testSimpleFilterOmitsWeightWhenUnset() {
        let dict = SimpleFilter(key: "price", operator: .gte, value: "10", action: .include).toDict()

        XCTAssertEqual(dict.keys.sorted(), ["action", "key", "operator", "value"])
        XCTAssertNil(dict["weight"])
    }

    func testSimpleFilterEncodesWeightAsAString() throws {
        let dict = SimpleFilter(key: "brand", operator: .eq, value: "acme", action: .boost, weight: 5).toDict()

        XCTAssertEqual(try string(dict, "weight"), "5", "the API expects weight as a string, not a number")
    }

    // MARK: - SimpleFilter field-key factories

    func testCustomFieldFactoriesPrefixTheKeyByType() throws {
        let stringFilter = SimpleFilter.customString(
            fieldName: "material",
            operator: .eq,
            value: "cotton",
            action: .include
        )
        let numericFilter = SimpleFilter.customNumeric(
            fieldName: "weight_kg",
            operator: .lte,
            value: "2",
            action: .include
        )
        let dateFilter = SimpleFilter.customDate(
            fieldName: "released_at",
            operator: .gte,
            value: "2024-01-01T00:00:00Z",
            action: .include
        )
        let standardFilter = SimpleFilter.standardField(
            fieldName: "price",
            operator: .gte,
            value: "10",
            action: .include
        )

        XCTAssertEqual(try string(stringFilter.toDict(), "key"), "custom.string.material")
        XCTAssertEqual(try string(numericFilter.toDict(), "key"), "custom.numeric.weight_kg")
        XCTAssertEqual(try string(dateFilter.toDict(), "key"), "custom.date.released_at")
        XCTAssertEqual(try string(dateFilter.toDict(), "value"), "2024-01-01T00:00:00Z")
        XCTAssertEqual(try string(standardFilter.toDict(), "key"), "price", "standard fields are not prefixed")
    }

    // MARK: - SimpleFilter presets and value stringification

    func testPriceRangePresetJoinsBoundsWithAComma() throws {
        let dict = SimpleFilter.priceRange(minPrice: 10, maxPrice: 49.99).toDict()

        XCTAssertEqual(try string(dict, "key"), "price")
        XCTAssertEqual(try string(dict, "operator"), "gte,lte")
        XCTAssertEqual(try string(dict, "value"), "10.0,49.99", "Double interpolation keeps the .0 on whole numbers")
        XCTAssertEqual(try string(dict, "action"), "include", "presets default to include")
    }

    func testMinAndMaxPricePresetsUseOneSidedOperators() throws {
        let min = SimpleFilter.minPrice(25).toDict()
        let max = SimpleFilter.maxPrice(100, action: .exclude).toDict()

        XCTAssertEqual(try string(min, "operator"), "gte")
        XCTAssertEqual(try string(min, "value"), "25.0")
        XCTAssertEqual(try string(max, "operator"), "lte")
        XCTAssertEqual(try string(max, "value"), "100.0")
        XCTAssertEqual(try string(max, "action"), "exclude")
    }

    func testAvailabilityPresetMapsBoolToTheApiVocabulary() throws {
        XCTAssertEqual(try string(SimpleFilter.availability(inStock: true).toDict(), "value"), "in_stock")
        XCTAssertEqual(try string(SimpleFilter.availability(inStock: false).toDict(), "value"), "out_of_stock")
        XCTAssertEqual(
            try string(SimpleFilter.availability(inStock: true).toDict(), "key"),
            "custom.string.availability"
        )
    }

    func testAttributePresetsTargetCustomStringFields() throws {
        XCTAssertEqual(try string(SimpleFilter.size("XL").toDict(), "key"), "custom.string.size")
        XCTAssertEqual(try string(SimpleFilter.brand("Acme").toDict(), "key"), "custom.string.brand")
        XCTAssertEqual(try string(SimpleFilter.color("red").toDict(), "key"), "custom.string.color")
        XCTAssertEqual(try string(SimpleFilter.category("shoes").toDict(), "key"), "custom.string.category")
        XCTAssertEqual(try string(SimpleFilter.brand("Acme").toDict(), "value"), "Acme")
    }

    func testRatingPresetTargetsACustomNumericField() throws {
        let dict = SimpleFilter.rating(minRating: 4, action: .boost, weight: 3).toDict()

        XCTAssertEqual(try string(dict, "key"), "custom.numeric.rating")
        XCTAssertEqual(try string(dict, "operator"), "gte")
        XCTAssertEqual(try string(dict, "value"), "4.0")
        XCTAssertEqual(try string(dict, "weight"), "3")
    }

    // MARK: - SimpleFilter validation

    func testValidatePassesForAWellFormedFilter() {
        XCTAssertNoThrow(try SimpleFilter.priceRange(minPrice: 1, maxPrice: 2).validate())
        XCTAssertNoThrow(try SimpleFilter.brand("Acme", action: .boost, weight: 1).validate())
    }

    func testValidateRejectsAnEmptyKey() {
        let filter = SimpleFilter(key: "", operator: .eq, value: "acme", action: .include)

        XCTAssertThrowsError(try filter.validate()) { error in
            XCTAssertEqual(RelevaErrorKind(error), .missingRequiredField, "unexpected error: \(error)")
        }
    }

    func testValidateRejectsAnEmptyValue() {
        let filter = SimpleFilter(key: "brand", operator: .eq, value: "", action: .include)

        XCTAssertThrowsError(try filter.validate()) { error in
            XCTAssertEqual(RelevaErrorKind(error), .missingRequiredField, "unexpected error: \(error)")
        }
    }

    func testValidateRejectsARangeOperatorWithoutASecondBound() {
        for op in FilterOperator.allCases where op.isRangeOperator {
            let filter = SimpleFilter(key: "price", operator: op, value: "10", action: .include)

            XCTAssertThrowsError(try filter.validate(), "\(op) should require two bounds") { error in
                XCTAssertEqual(RelevaErrorKind(error), .invalidConfiguration, "unexpected error for \(op): \(error)")
            }
        }
    }

    func testValidateRejectsANonPositiveWeight() {
        for weight in [0, -1] {
            let filter = SimpleFilter(key: "brand", operator: .eq, value: "acme", action: .boost, weight: weight)

            XCTAssertThrowsError(try filter.validate(), "weight \(weight) should be rejected") { error in
                XCTAssertEqual(RelevaErrorKind(error), .invalidConfiguration, "unexpected error: \(error)")
            }
        }
    }

    // MARK: - Operator and action metadata

    func testOnlyTwoBoundOperatorsAreRangeOperators() {
        let rangeOperators = FilterOperator.allCases.filter { $0.isRangeOperator }

        XCTAssertEqual(Set(rangeOperators), Set([.gteLte, .gteLt, .gtLte, .gtLt]))
    }

    func testOnlyBuryAndBoostAffectRanking() {
        let rankingActions = FilterAction.allCases.filter { $0.affectsRanking }

        XCTAssertEqual(Set(rankingActions), Set([.bury, .boost]))
    }

    func testOperatorAndActionValuesMatchTheirRawValues() {
        for op in FilterOperator.allCases {
            XCTAssertEqual(op.value, op.rawValue)
        }
        for action in FilterAction.allCases {
            XCTAssertEqual(action.value, action.rawValue)
        }
        for operation in NestedFilterOperation.allCases {
            XCTAssertEqual(operation.value, operation.rawValue)
        }
    }

    // MARK: - NestedFilter composition

    func testNestedFilterEncodesOperationUnderTheOperatorKey() throws {
        let and = NestedFilter.and([SimpleFilter.brand("Acme")]).toDict()
        let or = NestedFilter.or([SimpleFilter.brand("Acme")]).toDict()

        XCTAssertEqual(try string(and, "operator"), "and")
        XCTAssertEqual(try string(or, "operator"), "or")
        XCTAssertEqual(and.keys.sorted(), ["nested", "operator"])
    }

    func testNestedFilterEncodesChildrenInOrder() throws {
        let filter = NestedFilter.and([
            SimpleFilter.priceRange(minPrice: 10, maxPrice: 20),
            SimpleFilter.brand("Acme")
        ])
        let dict = filter.toDict()

        let children = try nested(dict)
        XCTAssertEqual(children.count, 2)
        XCTAssertEqual(try string(children[0], "key"), "price")
        XCTAssertEqual(try string(children[1], "key"), "custom.string.brand")
    }

    func testVariadicFactoriesMatchTheArrayFactories() throws {
        let variadic = NestedFilter.or(SimpleFilter.brand("A"), SimpleFilter.brand("B")).toDict()
        let fromArray = NestedFilter.or([SimpleFilter.brand("A"), SimpleFilter.brand("B")]).toDict()

        XCTAssertEqual(try string(variadic, "operator"), try string(fromArray, "operator"))
        XCTAssertEqual(try nested(variadic).count, try nested(fromArray).count)
    }

    func testNestedFilterNestsThreeLevelsDeep() throws {
        let innermost = NestedFilter.or([SimpleFilter.color("red"), SimpleFilter.color("blue")])
        let middle = NestedFilter.and([SimpleFilter.brand("Acme"), innermost])
        let outer = NestedFilter.or([SimpleFilter.category("shoes"), middle])

        let dict = outer.toDict()
        let level1 = try nested(dict)
        XCTAssertEqual(try string(dict, "operator"), "or")
        XCTAssertEqual(level1.count, 2)

        let level2 = try nested(level1[1])
        XCTAssertEqual(try string(level1[1], "operator"), "and")
        XCTAssertEqual(level2.count, 2)

        let level3 = try nested(level2[1])
        XCTAssertEqual(try string(level2[1], "operator"), "or")
        XCTAssertEqual(level3.map { $0["value"] as? String }, ["red", "blue"])

        XCTAssertEqual(outer.depth, 3)
        XCTAssertEqual(outer.filterCount, 4, "filterCount counts leaves, not nesting nodes")
    }

    func testAddingReturnsANewFilterAndLeavesTheOriginalUntouched() {
        let original = NestedFilter.and([SimpleFilter.brand("Acme")])

        let withOne = original.adding(SimpleFilter.color("red"))
        let withTwo = original.adding([SimpleFilter.color("red"), SimpleFilter.size("XL")])

        XCTAssertEqual(original.filterCount, 1, "adding() must not mutate the receiver")
        XCTAssertEqual(withOne.filterCount, 2)
        XCTAssertEqual(withTwo.filterCount, 3)
        XCTAssertEqual(withOne.operation, .and, "adding() keeps the operation")
    }

    func testEmptyNestedFilterEncodesAnEmptyArrayAndFailsValidation() throws {
        // Spelled out because `and` is also overloaded on a variadic parameter.
        let empty = NestedFilter.and([AbstractFilter]())

        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(empty.filterCount, 0)
        XCTAssertEqual(empty.depth, 1, "an empty node is still one level deep")
        XCTAssertTrue(try nested(empty.toDict()).isEmpty)

        XCTAssertThrowsError(try empty.validate()) { error in
            XCTAssertEqual(RelevaErrorKind(error), .invalidConfiguration, "unexpected error: \(error)")
        }
    }

    func testNestedValidationRecursesIntoChildren() {
        let broken = SimpleFilter(key: "brand", operator: .eq, value: "", action: .include)
        let filter = NestedFilter.and([SimpleFilter.brand("Acme"), NestedFilter.or([broken])])

        XCTAssertThrowsError(try filter.validate()) { error in
            XCTAssertEqual(
                RelevaErrorKind(error),
                .missingRequiredField,
                "the child's validation error should propagate, got \(error)"
            )
        }
        XCTAssertNoThrow(try NestedFilter.and([SimpleFilter.brand("Acme")]).validate())
    }

    // MARK: - NestedFilter combination presets

    func testPriceAndBrandPresetCombinesBothConditionsWithAnd() throws {
        let dict = NestedFilter.priceAndBrand(minPrice: 10, maxPrice: 20, brand: "Acme", action: .exclude).toDict()

        let children = try nested(dict)
        XCTAssertEqual(try string(dict, "operator"), "and")
        XCTAssertEqual(children.count, 2)
        XCTAssertEqual(try string(children[0], "value"), "10.0,20.0")
        XCTAssertEqual(try string(children[0], "action"), "exclude", "the action reaches both children")
        XCTAssertEqual(try string(children[1], "action"), "exclude")
    }

    func testMultiValuePresetsBuildOrGroups() throws {
        let brands = NestedFilter.brands(["A", "B", "C"]).toDict()
        let sizes = NestedFilter.sizes(["S", "M"]).toDict()
        let colors = NestedFilter.colors(["red"]).toDict()

        XCTAssertEqual(try string(brands, "operator"), "or")
        XCTAssertEqual(try nested(brands).map { $0["value"] as? String }, ["A", "B", "C"])
        XCTAssertEqual(try nested(sizes).map { $0["key"] as? String }, ["custom.string.size", "custom.string.size"])
        XCTAssertEqual(try nested(colors).count, 1)
    }

    func testMultiValuePresetsWithNoValuesProduceAnEmptyGroup() throws {
        let brands = NestedFilter.brands([])

        XCTAssertTrue(brands.isEmpty)
        XCTAssertTrue(try nested(brands.toDict()).isEmpty)
    }

    func testPriceWithBrandsOrCategoriesGroupsBothListsIntoOneOrNode() throws {
        let filter = NestedFilter.priceWithBrandsOrCategories(
            minPrice: 10,
            maxPrice: 20,
            brands: ["Acme"],
            categories: ["shoes", "boots"]
        )
        let dict = filter.toDict()

        let children = try nested(dict)
        XCTAssertEqual(children.count, 2, "price, plus a single OR node for brands and categories")
        XCTAssertEqual(try string(children[0], "key"), "price")

        let orGroup = try nested(children[1])
        XCTAssertEqual(try string(children[1], "operator"), "or")
        XCTAssertEqual(
            orGroup.map { $0["key"] as? String },
            ["custom.string.brand", "custom.string.category", "custom.string.category"]
        )
    }

    func testPriceWithBrandsOrCategoriesOmitsTheOrNodeWhenBothListsAreEmpty() throws {
        let dict = NestedFilter.priceWithBrandsOrCategories(minPrice: 10, maxPrice: 20).toDict()

        let children = try nested(dict)
        XCTAssertEqual(children.count, 1, "no OR node when there is nothing to OR")
        XCTAssertEqual(try string(children[0], "key"), "price")
    }

    // MARK: - JSON-serializability of the encoded form

    func testEncodedFilterTreeIsJsonSerializable() throws {
        let filter = NestedFilter.priceWithBrandsOrCategories(
            minPrice: 10,
            maxPrice: 20,
            brands: ["Acme"],
            categories: ["shoes"]
        )
        let dict = filter.toDict()

        XCTAssertTrue(
            JSONSerialization.isValidJSONObject(dict),
            "toDict() must contain only JSON types; NetworkService serializes it directly"
        )

        let data = try JSONSerialization.data(withJSONObject: dict)
        let roundTripped = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(roundTripped["operator"] as? String, "and")
    }
}
