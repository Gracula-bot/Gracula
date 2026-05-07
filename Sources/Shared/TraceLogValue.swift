import Foundation

public enum TraceLogValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case integer(Int)
    case bool(Bool)
    case object([String: TraceLogValue])
    case array([TraceLogValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: TraceLogValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([TraceLogValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported trace log value.")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

public extension TraceLogValue {
    init(_ value: String) {
        self = .string(value)
    }

    init(_ value: Int) {
        self = .integer(value)
    }

    init(_ value: Double) {
        self = .number(value)
    }

    init(_ value: Bool) {
        self = .bool(value)
    }

    init(_ value: [String: TraceLogValue]) {
        self = .object(value)
    }

    init(_ value: [TraceLogValue]) {
        self = .array(value)
    }
}
