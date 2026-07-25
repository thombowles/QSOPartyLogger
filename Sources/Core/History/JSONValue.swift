import Foundation

/// A JSON fragment carried opaquely. The contest archive lives in one iCloud
/// file shared by whatever app versions Tom's Macs are running, so fields an
/// older build doesn't know about must survive its rewrites (the additive-
/// schema law applied to a shared file).
indirect enum JSONValue: Codable, Equatable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Value is not representable JSON"
            ))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

/// String-keyed coding key for capturing fields outside a type's known set.
struct UnknownCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        nil
    }
}

extension KeyedDecodingContainer where Key == UnknownCodingKey {
    /// Every field not in `known`, decoded opaquely for round-tripping.
    func decodeUnknownFields(besides known: Set<String>) throws -> [String: JSONValue] {
        var extras: [String: JSONValue] = [:]
        for key in allKeys where !known.contains(key.stringValue) {
            extras[key.stringValue] = try decode(JSONValue.self, forKey: key)
        }
        return extras
    }
}

extension KeyedEncodingContainer where K == UnknownCodingKey {
    mutating func encodeUnknownFields(_ extras: [String: JSONValue]) throws {
        for (name, value) in extras {
            try encode(value, forKey: UnknownCodingKey(stringValue: name))
        }
    }
}
