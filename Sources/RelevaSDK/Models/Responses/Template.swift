import Foundation

/// Represents a display template for recommendations
public struct Template: Codable, Equatable {

    // MARK: - Properties

    /// Template ID
    public let id: Int

    /// Template body content (HTML/text)
    public let body: String

    // MARK: - Initializers

    /// Initialize a template
    /// - Parameters:
    ///   - id: Template ID
    ///   - body: Template body content
    public init(id: Int, body: String) {
        self.id = id
        self.body = body
    }

    // MARK: - Computed Properties

    /// Check if template has content
    public var hasContent: Bool {
        return !body.isEmpty
    }

    /// Get the template body length
    public var contentLength: Int {
        return body.count
    }

    // MARK: - Serialization

    /// Convert to dictionary for API responses
    public func toDict() -> [String: Any] {
        return [
            "id": id,
            "body": body
        ]
    }

    // MARK: - Factory Methods

    /// Create from dictionary
    /// - Parameter dict: Dictionary containing template data
    /// - Returns: Template instance or nil if invalid
    public static func from(dict: [String: Any]) -> Template? {
        guard let id = dict["id"] as? Int,
              let body = dict["body"] as? String else {
            return nil
        }
        return Template(id: id, body: body)
    }
}