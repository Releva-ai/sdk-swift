import Foundation

/// Helper type for decoding arbitrary JSON values within Codable containers.
/// Used for banner responses which contain [String: Any] fields like `design` and `cssStyles`.
struct RawJSON: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([RawJSON].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: RawJSON].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode RawJSON")
        }
    }
}
