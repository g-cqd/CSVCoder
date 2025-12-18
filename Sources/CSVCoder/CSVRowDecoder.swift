//
//  CSVRowDecoder.swift
//  CSVCoder
//
//  Implements the Decoder protocol for CSV row decoding.
//

import Foundation

/// A decoder for a single CSV row.
struct CSVRowDecoder: Decoder {
    let row: [String: String]
    let configuration: CSVDecoder.Configuration
    let codingPath: [CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        KeyedDecodingContainer(CSVKeyedDecodingContainer(row: row, configuration: configuration, codingPath: codingPath))
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        throw CSVDecodingError.unsupportedType("Unkeyed containers are not supported in CSV decoding")
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        throw CSVDecodingError.unsupportedType("Single value containers are not supported at root level")
    }
}

/// A keyed decoding container for CSV data.
struct CSVKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let row: [String: String]
    let configuration: CSVDecoder.Configuration
    let codingPath: [CodingKey]
    var allKeys: [Key] { row.keys.compactMap { Key(stringValue: $0) } }

    func contains(_ key: Key) -> Bool {
        row[key.stringValue] != nil
    }

    private func getValue(for key: Key) throws -> String {
        guard let value = row[key.stringValue] else {
            throw CSVDecodingError.keyNotFound(key.stringValue)
        }
        return value
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        guard let value = row[key.stringValue] else { return true }
        return value.isEmpty
    }

    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
        let value = try getValue(for: key).lowercased()
        switch value {
        case "true", "yes", "1": return true
        case "false", "no", "0": return false
        default: throw CSVDecodingError.typeMismatch(expected: "Bool", actual: value)
        }
    }

    func decode(_ type: String.Type, forKey key: Key) throws -> String {
        try getValue(for: key)
    }

    func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
        let value = try getValue(for: key)
        guard let result = Double(value) else {
            throw CSVDecodingError.typeMismatch(expected: "Double", actual: value)
        }
        return result
    }

    func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
        let value = try getValue(for: key)
        guard let result = Float(value) else {
            throw CSVDecodingError.typeMismatch(expected: "Float", actual: value)
        }
        return result
    }

    func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
        let value = try getValue(for: key)
        guard let result = Int(value) else {
            throw CSVDecodingError.typeMismatch(expected: "Int", actual: value)
        }
        return result
    }

    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
        let value = try getValue(for: key)
        guard let result = Int8(value) else {
            throw CSVDecodingError.typeMismatch(expected: "Int8", actual: value)
        }
        return result
    }

    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
        let value = try getValue(for: key)
        guard let result = Int16(value) else {
            throw CSVDecodingError.typeMismatch(expected: "Int16", actual: value)
        }
        return result
    }

    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
        let value = try getValue(for: key)
        guard let result = Int32(value) else {
            throw CSVDecodingError.typeMismatch(expected: "Int32", actual: value)
        }
        return result
    }

    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
        let value = try getValue(for: key)
        guard let result = Int64(value) else {
            throw CSVDecodingError.typeMismatch(expected: "Int64", actual: value)
        }
        return result
    }

    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
        let value = try getValue(for: key)
        guard let result = UInt(value) else {
            throw CSVDecodingError.typeMismatch(expected: "UInt", actual: value)
        }
        return result
    }

    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
        let value = try getValue(for: key)
        guard let result = UInt8(value) else {
            throw CSVDecodingError.typeMismatch(expected: "UInt8", actual: value)
        }
        return result
    }

    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
        let value = try getValue(for: key)
        guard let result = UInt16(value) else {
            throw CSVDecodingError.typeMismatch(expected: "UInt16", actual: value)
        }
        return result
    }

    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
        let value = try getValue(for: key)
        guard let result = UInt32(value) else {
            throw CSVDecodingError.typeMismatch(expected: "UInt32", actual: value)
        }
        return result
    }

    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
        let value = try getValue(for: key)
        guard let result = UInt64(value) else {
            throw CSVDecodingError.typeMismatch(expected: "UInt64", actual: value)
        }
        return result
    }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        let value = try getValue(for: key)

        // Handle Date specially
        if type == Date.self {
            return try decodeDate(from: value) as! T
        }

        // Handle Optional types
        if let optionalType = T.self as? OptionalDecodable.Type {
            if value.isEmpty {
                return optionalType.nilValue as! T
            }
        }

        // Try to decode using single value container
        let singleValueDecoder = CSVSingleValueDecoder(
            value: value,
            configuration: configuration,
            codingPath: codingPath + [key]
        )
        return try T(from: singleValueDecoder)
    }

    private func decodeDate(from value: String) throws -> Date {
        switch configuration.dateDecodingStrategy {
        case .deferredToDate:
            throw CSVDecodingError.typeMismatch(expected: "Date (use a date strategy)", actual: value)

        case .secondsSince1970:
            guard let seconds = Double(value) else {
                throw CSVDecodingError.typeMismatch(expected: "Unix timestamp", actual: value)
            }
            return Date(timeIntervalSince1970: seconds)

        case .millisecondsSince1970:
            guard let milliseconds = Double(value) else {
                throw CSVDecodingError.typeMismatch(expected: "Unix timestamp (ms)", actual: value)
            }
            return Date(timeIntervalSince1970: milliseconds / 1000)

        case .iso8601:
            let formatter = ISO8601DateFormatter()
            guard let date = formatter.date(from: value) else {
                throw CSVDecodingError.typeMismatch(expected: "ISO8601 date", actual: value)
            }
            return date

        case .formatted(let format):
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale.autoupdatingCurrent
            formatter.timeZone = TimeZone.autoupdatingCurrent
            guard let date = formatter.date(from: value) else {
                throw CSVDecodingError.typeMismatch(expected: "Date with format \(format)", actual: value)
            }
            return date

        case .custom(let closure):
            return try closure(value)
        }
    }

    func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
        throw CSVDecodingError.unsupportedType("Nested containers are not supported in CSV")
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        throw CSVDecodingError.unsupportedType("Nested unkeyed containers are not supported in CSV")
    }

    func superDecoder() throws -> Decoder {
        throw CSVDecodingError.unsupportedType("Super decoder is not supported in CSV")
    }

    func superDecoder(forKey key: Key) throws -> Decoder {
        throw CSVDecodingError.unsupportedType("Super decoder is not supported in CSV")
    }
}

/// Protocol for handling optional decoding.
private protocol OptionalDecodable {
    static var nilValue: Any { get }
}

extension Optional: OptionalDecodable {
    static var nilValue: Any { Self.none as Any }
}
