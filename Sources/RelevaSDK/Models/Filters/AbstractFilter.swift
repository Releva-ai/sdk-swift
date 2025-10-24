import Foundation

/// Protocol for all filter types
public protocol AbstractFilter: Codable {
    /// Convert the filter to a dictionary for API requests
    func toDict() -> [String: Any]
}

/// Operators for filter conditions
public enum FilterOperator: String, CaseIterable, Codable {
    /// Equal to
    case eq = "eq"

    /// Less than
    case lt = "lt"

    /// Greater than
    case gt = "gt"

    /// Less than or equal to
    case lte = "lte"

    /// Greater than or equal to
    case gte = "gte"

    /// Greater than or equal to AND less than or equal to
    case gteLte = "gte,lte"

    /// Greater than or equal to AND less than
    case gteLt = "gte,lt"

    /// Greater than AND less than or equal to
    case gtLte = "gt,lte"

    /// Greater than AND less than
    case gtLt = "gt,lt"

    // MARK: - Properties

    /// Get the API value for the operator
    public var value: String {
        return self.rawValue
    }

    /// Human-readable description
    public var description: String {
        switch self {
        case .eq:
            return "Equal to"
        case .lt:
            return "Less than"
        case .gt:
            return "Greater than"
        case .lte:
            return "Less than or equal to"
        case .gte:
            return "Greater than or equal to"
        case .gteLte:
            return "Between (inclusive)"
        case .gteLt:
            return "From (inclusive) to (exclusive)"
        case .gtLte:
            return "From (exclusive) to (inclusive)"
        case .gtLt:
            return "Between (exclusive)"
        }
    }

    /// Check if this is a range operator
    public var isRangeOperator: Bool {
        switch self {
        case .gteLte, .gteLt, .gtLte, .gtLt:
            return true
        default:
            return false
        }
    }
}

/// Actions for filter application
public enum FilterAction: String, CaseIterable, Codable {
    /// Include only products that match the condition
    case include = "include"

    /// Exclude products that match the condition
    case exclude = "exclude"

    /// Make products appear at bottom if they match
    case bury = "bury"

    /// Make products appear at top if they match
    case boost = "boost"

    // MARK: - Properties

    /// Get the API value for the action
    public var value: String {
        return self.rawValue
    }

    /// Human-readable description
    public var description: String {
        switch self {
        case .include:
            return "Include matching items"
        case .exclude:
            return "Exclude matching items"
        case .bury:
            return "Deprioritize matching items"
        case .boost:
            return "Prioritize matching items"
        }
    }

    /// Check if this action affects ranking
    public var affectsRanking: Bool {
        switch self {
        case .bury, .boost:
            return true
        default:
            return false
        }
    }
}

/// Operation types for nested filters
public enum NestedFilterOperation: String, CaseIterable, Codable {
    /// All conditions must be met
    case and = "and"

    /// At least one condition must be met
    case or = "or"

    // MARK: - Properties

    /// Get the API value for the operation
    public var value: String {
        return self.rawValue
    }

    /// Human-readable description
    public var description: String {
        switch self {
        case .and:
            return "All conditions must match"
        case .or:
            return "Any condition must match"
        }
    }
}