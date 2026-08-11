import Foundation

/// A type-safe representation of an arbitrary JSON value.
///
/// The API returns a few genuinely open-ended payloads — Unlayer banner and story designs,
/// inbox message bodies, recommender `meta`, product `custom`/`data` — whose shape the SDK does
/// not control. Modelling them as `[String: Any]` made the enclosing types unable to conform to
/// `Codable` or `Sendable`, so this enum stands in for `Any` instead.
///
/// Integers and floating-point numbers are kept as separate cases so that a JSON integer decoded
/// here and re-encoded comes back out as an integer rather than as `1.0`. The guarantee is "a JSON
/// integer stays an integer", not "every number round-trips byte-for-byte": `Int` decoding on
/// Apple platforms also accepts a whole-number `Double` token, so a source `1.0` decodes as
/// `.int(1)` too and re-encodes as `1`, losing the trailing `.0`
/// (`JSONValueTests.testAnIntegralDoubleNormalizesToInt` pins this).
///
/// Because `.int` and `.double` are distinct cases, `Hashable`/`Equatable` treat `.int(1)` and
/// `.double(1.0)` as unequal — correct for the enum's shape, but worth knowing if you use a
/// `JSONValue` as a dictionary key or `Set` element built from mixed sources.
public enum JSONValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

// MARK: - Accessors

extension JSONValue {
    /// The wrapped string, or `nil` if this is not a `.string`.
    public var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    /// The wrapped boolean, or `nil` if this is not a `.bool`.
    public var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    /// The wrapped number as an `Int`, truncating a `.double` the way `NSNumber.intValue` does.
    public var intValue: Int? {
        switch self {
        case .int(let value):
            return value
        case .double(let value):
            return Int(exactly: value.rounded(.towardZero))
        default:
            return nil
        }
    }

    /// The wrapped number as a `Double`, widening an `.int` the way `NSNumber.doubleValue` does.
    public var doubleValue: Double? {
        switch self {
        case .int(let value):
            return Double(value)
        case .double(let value):
            return value
        default:
            return nil
        }
    }

    /// The wrapped array, or `nil` if this is not an `.array`.
    public var arrayValue: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    /// The wrapped object, or `nil` if this is not an `.object`.
    public var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    /// Whether this is JSON `null`.
    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    /// Look up a key, or `nil` if this is not an object or the key is absent.
    public subscript(key: String) -> JSONValue? {
        guard case .object(let object) = self else { return nil }
        return object[key]
    }

    /// Look up an index, or `nil` if this is not an array or the index is out of bounds.
    public subscript(index: Int) -> JSONValue? {
        guard case .array(let array) = self, array.indices.contains(index) else { return nil }
        return array[index]
    }
}

// MARK: - Codable

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Value is not representable as JSON"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

// MARK: - Foundation bridging

extension JSONValue {
    /// Wrap a Foundation JSON object of the kind `JSONSerialization` produces.
    ///
    /// Anything that is not a JSON value — which `JSONSerialization` cannot produce — becomes `.null`.
    /// A `JSONValue` passed in by mistake (it satisfies `Any`, so this is easy to do with an
    /// already-typed `[String: JSONValue]`) is passed through unchanged instead of falling into
    /// that `.null` bucket, which would otherwise silently null every leaf.
    public init(any value: Any) {
        switch value {
        case let value as JSONValue:
            self = value
        case is NSNull:
            self = .null
        case let number as NSNumber:
            // `JSONSerialization` reports booleans as `CFBoolean`, which is otherwise
            // indistinguishable from the number 0 or 1 once bridged to `NSNumber`.
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else if let integer = number as? Int {
                self = .int(integer)
            } else {
                self = .double(number.doubleValue)
            }
        case let string as String:
            self = .string(string)
        case let array as [Any]:
            self = .array(array.map { JSONValue(any: $0) })
        case let object as [String: Any]:
            self = .object(object.mapValues { JSONValue(any: $0) })
        default:
            self = .null
        }
    }

    /// Unwrap into the Foundation representation `JSONSerialization` accepts.
    ///
    /// Numbers and booleans come back as `NSNumber` so that callers reading the result with
    /// `as? Int` / `as? Bool` see what they would have seen from `JSONSerialization` itself.
    /// A non-finite `.double` (`.nan`/`.infinity`) cannot reach this from decoding, but `JSONValue`
    /// is public and `ExpressibleByFloatLiteral`, so a consumer can construct one; it maps to
    /// `NSNull` here rather than an `NSNumber` that fails `JSONSerialization.isValidJSONObject` and
    /// would raise an uncatchable Objective-C exception where `anyValue` output is serialized with
    /// `try?` (see `InboxService`).
    public var anyValue: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let value): return NSNumber(value: value)
        case .int(let value): return NSNumber(value: value)
        case .double(let value): return value.isFinite ? NSNumber(value: value) : NSNull()
        case .string(let value): return value
        case .array(let value): return value.map { $0.anyValue }
        case .object(let value): return value.mapValues { $0.anyValue }
        }
    }
}

extension Dictionary where Key == String, Value == JSONValue {
    /// Wrap a Foundation JSON dictionary.
    public init(any dictionary: [String: Any]) {
        self = dictionary.mapValues { JSONValue(any: $0) }
    }

    /// Unwrap into the Foundation representation `JSONSerialization` accepts.
    public var anyValue: [String: Any] {
        mapValues { $0.anyValue }
    }
}

// MARK: - Literals

extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .int(value) }
}

extension JSONValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .double(value) }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension JSONValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements) { _, last in last })
    }
}
