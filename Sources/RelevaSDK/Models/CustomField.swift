import Foundation

/// A custom field with a key and list of values
public struct CustomField<T: Codable & Equatable & Hashable>: Codable, Equatable, Hashable {

    // MARK: - Properties

    /// The field key
    public let key: String

    /// The field values
    public let values: [T]

    // MARK: - Initializers

    /// Initialize a custom field
    /// - Parameters:
    ///   - key: The field key
    ///   - values: The field values
    public init(key: String, values: [T]) {
        self.key = key
        self.values = values
    }

    /// Initialize with a single value
    /// - Parameters:
    ///   - key: The field key
    ///   - value: The single field value
    public init(key: String, value: T) {
        self.key = key
        self.values = [value]
    }

    // MARK: - Serialization

    /// Convert to dictionary for API requests
    public func toDict() -> [String: Any] {
        var dict: [String: Any] = ["key": key]

        if T.self == Date.self {
            // Convert dates to ISO8601 strings
            let dateValues = values as! [Date]
            dict["values"] = dateValues.map { ISO8601DateFormatter().string(from: $0) }
        } else {
            dict["values"] = values
        }

        return dict
    }
}

/// A collection of custom fields organized by type
public struct CustomFields: Codable, Equatable, Hashable {

    // MARK: - Properties

    /// String custom fields
    public let string: [CustomField<String>]

    /// Numeric custom fields
    public let numeric: [CustomField<Double>]

    /// Date custom fields
    public let date: [CustomField<Date>]

    // MARK: - Initializers

    /// Initialize with empty fields
    public init() {
        self.string = []
        self.numeric = []
        self.date = []
    }

    /// Initialize with specific fields
    /// - Parameters:
    ///   - string: String custom fields
    ///   - numeric: Numeric custom fields
    ///   - date: Date custom fields
    public init(
        string: [CustomField<String>] = [],
        numeric: [CustomField<Double>] = [],
        date: [CustomField<Date>] = []
    ) {
        self.string = string
        self.numeric = numeric
        self.date = date
    }

    // MARK: - Serialization

    /// Convert to dictionary for API requests
    public func toDict() -> [String: Any] {
        return [
            "string": string.map { $0.toDict() },
            "numeric": numeric.map { $0.toDict() },
            "date": date.map { $0.toDict() }
        ]
    }

    // MARK: - Builder Methods

    /// Add a string field
    public func withStringField(key: String, values: [String]) -> CustomFields {
        var newString = self.string
        newString.append(CustomField(key: key, values: values))
        return CustomFields(string: newString, numeric: self.numeric, date: self.date)
    }

    /// Add a numeric field
    public func withNumericField(key: String, values: [Double]) -> CustomFields {
        var newNumeric = self.numeric
        newNumeric.append(CustomField(key: key, values: values))
        return CustomFields(string: self.string, numeric: newNumeric, date: self.date)
    }

    /// Add a date field
    public func withDateField(key: String, values: [Date]) -> CustomFields {
        var newDate = self.date
        newDate.append(CustomField(key: key, values: values))
        return CustomFields(string: self.string, numeric: self.numeric, date: newDate)
    }

    // MARK: - Convenience Methods

    /// Check if fields are empty
    public var isEmpty: Bool {
        return string.isEmpty && numeric.isEmpty && date.isEmpty
    }

    /// Get total number of fields
    public var count: Int {
        return string.count + numeric.count + date.count
    }
}