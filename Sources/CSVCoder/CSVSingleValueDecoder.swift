//
//  CSVSingleValueDecoder.swift
//  CSVCoder
//
//  Implements single value decoding for CSV fields.
//

import Foundation

/// A decoder for single values in CSV fields.
struct CSVSingleValueDecoder: Decoder {
    let value: String
    let configuration: CSVDecoder.Configuration
    let codingPath: [CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        throw CSVDecodingError.unsupportedType("Keyed containers not supported for single values")
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        throw CSVDecodingError.unsupportedType("Unkeyed containers not supported for single values")
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        CSVSingleValueContainer(value: value, configuration: configuration, codingPath: codingPath)
    }
}

/// A single value container for CSV decoding.
struct CSVSingleValueContainer: SingleValueDecodingContainer {
    let value: String
    let configuration: CSVDecoder.Configuration
    let codingPath: [CodingKey]

    func decodeNil() -> Bool {
        value.isEmpty
    }

    func decode(_ type: Bool.Type) throws -> Bool {
        switch value.lowercased() {
        case "true", "yes", "1": return true
        case "false", "no", "0": return false
        default: throw CSVDecodingError.typeMismatch(expected: "Bool", actual: value)
        }
    }

    func decode(_ type: String.Type) throws -> String {
        value
    }

    func decode(_ type: Double.Type) throws -> Double {
        guard let result = Double(value) else {
            throw CSVDecodingError.typeMismatch(expected: "Double", actual: value)
        }
        return result
    }

    func decode(_ type: Float.Type) throws -> Float {
        guard let result = Float(value) else {
            throw CSVDecodingError.typeMismatch(expected: "Float", actual: value)
        }
        return result
    }

    func decode(_ type: Int.Type) throws -> Int {
        guard let result = Int(value) else {
            throw CSVDecodingError.typeMismatch(expected: "Int", actual: value)
        }
        return result
    }

    func decode(_ type: Int8.Type) throws -> Int8 {
        guard let result = Int8(value) else {
            throw CSVDecodingError.typeMismatch(expected: "Int8", actual: value)
        }
        return result
    }

    func decode(_ type: Int16.Type) throws -> Int16 {
        guard let result = Int16(value) else {
            throw CSVDecodingError.typeMismatch(expected: "Int16", actual: value)
        }
        return result
    }

    func decode(_ type: Int32.Type) throws -> Int32 {
        guard let result = Int32(value) else {
            throw CSVDecodingError.typeMismatch(expected: "Int32", actual: value)
        }
        return result
    }

    func decode(_ type: Int64.Type) throws -> Int64 {
        guard let result = Int64(value) else {
            throw CSVDecodingError.typeMismatch(expected: "Int64", actual: value)
        }
        return result
    }

    func decode(_ type: UInt.Type) throws -> UInt {
        guard let result = UInt(value) else {
            throw CSVDecodingError.typeMismatch(expected: "UInt", actual: value)
        }
        return result
    }

    func decode(_ type: UInt8.Type) throws -> UInt8 {
        guard let result = UInt8(value) else {
            throw CSVDecodingError.typeMismatch(expected: "UInt8", actual: value)
        }
        return result
    }

    func decode(_ type: UInt16.Type) throws -> UInt16 {
        guard let result = UInt16(value) else {
            throw CSVDecodingError.typeMismatch(expected: "UInt16", actual: value)
        }
        return result
    }

    func decode(_ type: UInt32.Type) throws -> UInt32 {
        guard let result = UInt32(value) else {
            throw CSVDecodingError.typeMismatch(expected: "UInt32", actual: value)
        }
        return result
    }

    func decode(_ type: UInt64.Type) throws -> UInt64 {
        guard let result = UInt64(value) else {
            throw CSVDecodingError.typeMismatch(expected: "UInt64", actual: value)
        }
        return result
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        // Handle Date specially
        if type == Date.self {
            return try decodeDate() as! T
        }

        // For other types, they need to implement init(from:) properly
        throw CSVDecodingError.unsupportedType("Cannot decode \(type) from single CSV value")
    }

    private func decodeDate() throws -> Date {
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
}
