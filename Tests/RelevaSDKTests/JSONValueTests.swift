import XCTest
@testable import RelevaSDK

/// `JSONValue` is the `Sendable` stand-in for the `[String: Any]` payloads the API returns with a
/// shape the SDK does not control (Unlayer designs, inbox bodies, recommender `meta`, product
/// `custom`/`data`). It sits between the network and every model, so this suite pins the two
/// things the rest of the SDK relies on: number fidelity and the Foundation bridge.
final class JSONValueTests: XCTestCase {

    // MARK: - Number fidelity

    /// `.int` and `.double` are separate cases precisely so that a JSON integer does not come back
    /// out of a re-encode as `3.0`. Sorted keys make the encoded text deterministic.
    func testAJsonIntegerSurvivesDecodeThenEncodeUnchanged() throws {
        let data = Data(#"{"count":3,"ratio":0.5}"#.utf8)

        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded["count"], JSONValue.int(3))
        XCTAssertEqual(decoded["ratio"], JSONValue.double(0.5))

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let reEncoded = try encoder.encode(decoded)

        XCTAssertEqual(String(decoding: reEncoded, as: UTF8.self), #"{"count":3,"ratio":0.5}"#)
    }

    /// The numeric accessors match what the `from(dict:)` factories used to get out of `NSNumber`,
    /// which is what lets those factories keep their `as? NSNumber` reads.
    func testTheNumericAccessorsWidenAndTruncateLikeNSNumber() {
        XCTAssertEqual(JSONValue.int(7).doubleValue, 7.0)
        XCTAssertEqual(JSONValue.double(7.9).intValue, 7)
        XCTAssertEqual(JSONValue.double(-7.9).intValue, -7)
        XCTAssertNil(JSONValue.string("7").intValue, "a numeric string is not a number")
        XCTAssertNil(JSONValue.bool(true).intValue, "a boolean is not a number")
    }

    // MARK: - Accessors

    func testAccessorsReturnNilForTheWrongCase() {
        XCTAssertEqual(JSONValue.string("x").stringValue, "x")
        XCTAssertNil(JSONValue.int(1).stringValue)

        XCTAssertEqual(JSONValue.bool(false).boolValue, false)
        XCTAssertNil(JSONValue.int(0).boolValue, "the number 0 is not the boolean false")

        XCTAssertEqual(JSONValue.array([.int(1)]).arrayValue?.count, 1)
        XCTAssertNil(JSONValue.object([:]).arrayValue)

        XCTAssertEqual(JSONValue.object(["k": .int(1)]).objectValue?.count, 1)
        XCTAssertNil(JSONValue.array([]).objectValue)

        XCTAssertTrue(JSONValue.null.isNull)
        XCTAssertFalse(JSONValue.bool(false).isNull)
    }

    /// The subscripts are what let design lookups collapse to a single optional chain
    /// (`design["body"]?["values"]?["backgroundColor"]?.stringValue`).
    func testSubscriptsReturnNilRatherThanTrappingOnAMismatch() {
        let value = JSONValue.object(["items": .array([.string("first")])])

        XCTAssertEqual(value["items"]?[0], JSONValue.string("first"))
        XCTAssertNil(value["missing"])
        XCTAssertNil(value["items"]?[9], "an out-of-bounds index is nil, not a crash")
        XCTAssertNil(value[0], "an object has no integer index")
        XCTAssertNil(JSONValue.array([])["key"], "an array has no string key")
    }

    // MARK: - Foundation bridge

    /// The `from(dict:)` factories still take `[String: Any]`, and `toDict()` still returns it, so
    /// the bridge in both directions has to agree with what `JSONSerialization` itself produces.
    func testTheBridgeRoundTripsWhatJsonSerializationProduces() throws {
        let data = Data(#"{"s":"x","i":7,"d":1.5,"b":true,"n":null,"a":[1,"two"],"o":{"k":"v"}}"#.utf8)
        let foundation = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        let wrapped = [String: JSONValue](any: foundation)

        XCTAssertEqual(wrapped["s"], JSONValue.string("x"))
        XCTAssertEqual(wrapped["i"], JSONValue.int(7))
        XCTAssertEqual(wrapped["d"], JSONValue.double(1.5))
        XCTAssertEqual(wrapped["b"], JSONValue.bool(true), "a JSON boolean must not become the number 1")
        XCTAssertEqual(wrapped["n"], JSONValue.null)
        XCTAssertEqual(wrapped["a"], JSONValue.array([.int(1), .string("two")]))
        XCTAssertEqual(wrapped["o"], JSONValue.object(["k": .string("v")]))

        let unwrapped = wrapped.anyValue

        XCTAssertTrue(JSONSerialization.isValidJSONObject(unwrapped), "toDict() output must stay serialisable")
        XCTAssertEqual(unwrapped["s"] as? String, "x")
        XCTAssertEqual(unwrapped["i"] as? Int, 7)
        XCTAssertEqual(unwrapped["d"] as? Double, 1.5)
        XCTAssertEqual(unwrapped["b"] as? Bool, true)
        XCTAssertNotNil(unwrapped["n"] as? NSNull)
        XCTAssertEqual((unwrapped["o"] as? [String: Any])?["k"] as? String, "v")
    }

    /// `init(any:)` takes `Any`, so it needs a fallback. Anything outside the JSON types becomes
    /// `.null` rather than being smuggled through as an opaque object.
    func testANonJsonValueBecomesNull() {
        XCTAssertEqual(JSONValue(any: Date()), JSONValue.null)
    }
}
