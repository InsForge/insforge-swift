import Foundation

// MARK: - Postgres Change Actions

/// Base protocol for all postgres change actions
public protocol PostgresChangeAction: Codable, Sendable {
    associatedtype Record: Codable & Sendable
}

/// Represents any type of postgres change (insert, update, delete, select)
public enum AnyAction<Record: Codable & Sendable>: Codable, Sendable {
    case insert(InsertAction<Record>)
    case update(UpdateAction<Record>)
    case delete(DeleteAction<Record>)
    case select(SelectAction<Record>)

    enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "INSERT":
            self = .insert(try InsertAction<Record>(from: decoder))
        case "UPDATE":
            self = .update(try UpdateAction<Record>(from: decoder))
        case "DELETE":
            self = .delete(try DeleteAction<Record>(from: decoder))
        case "SELECT":
            self = .select(try SelectAction<Record>(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown postgres action type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .insert(let action):
            try action.encode(to: encoder)
        case .update(let action):
            try action.encode(to: encoder)
        case .delete(let action):
            try action.encode(to: encoder)
        case .select(let action):
            try action.encode(to: encoder)
        }
    }
}

/// Insert action - triggered when a new record is inserted
public struct InsertAction<Record: Codable & Sendable>: PostgresChangeAction, Codable, Sendable {
    public let type: String = "INSERT"
    public let schema: String
    public let table: String
    public let record: Record
    public let commitTimestamp: String?

    enum CodingKeys: String, CodingKey {
        case type, schema, table, record
        case commitTimestamp = "commit_timestamp"
    }
}

/// Update action - triggered when a record is updated
public struct UpdateAction<Record: Codable & Sendable>: PostgresChangeAction, Codable, Sendable {
    public let type: String = "UPDATE"
    public let schema: String
    public let table: String
    public let record: Record
    public let oldRecord: Record
    public let commitTimestamp: String?

    enum CodingKeys: String, CodingKey {
        case type, schema, table, record
        case oldRecord = "old_record"
        case commitTimestamp = "commit_timestamp"
    }
}

/// Delete action - triggered when a record is deleted
public struct DeleteAction<Record: Codable & Sendable>: PostgresChangeAction, Codable, Sendable {
    public let type: String = "DELETE"
    public let schema: String
    public let table: String
    public let oldRecord: Record
    public let commitTimestamp: String?

    enum CodingKeys: String, CodingKey {
        case type, schema, table
        case oldRecord = "old_record"
        case commitTimestamp = "commit_timestamp"
    }
}

/// Select action - triggered when a record is selected (if configured)
public struct SelectAction<Record: Codable & Sendable>: PostgresChangeAction, Codable, Sendable {
    public let type: String = "SELECT"
    public let schema: String
    public let table: String
    public let record: Record
    public let commitTimestamp: String?

    enum CodingKeys: String, CodingKey {
        case type, schema, table, record
        case commitTimestamp = "commit_timestamp"
    }
}
