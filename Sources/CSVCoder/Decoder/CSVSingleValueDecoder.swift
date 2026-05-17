//
//  CSVSingleValueDecoder.swift
//  CSVCoder
//
//  Implements single value decoding for CSV fields.
//

import Foundation

// MARK: - CSVSingleValueDecoder

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

// MARK: - CSVSingleValueContainer

/// A single value container for CSV decoding.
struct CSVSingleValueContainer: SingleValueDecodingContainer {
    // MARK: Internal

    let value: String
    let configuration: CSVDecoder.Configuration
    let codingPath: [CodingKey]

    func decodeNil() -> Bool {
        value.isEmpty
    }

    func decode(_ type: Bool.Type) throws -> Bool {
        let trimmed = trimmedValue

        if let result = CSVValueParser.parseBoolean(trimmed, strategy: configuration.boolDecodingStrategy) {
            return result
        }

        // For flexible strategy, also try numeric: any non-zero is true
        if case .flexible = configuration.boolDecodingStrategy {
            if let num = Int(trimmed) { return num != 0 }
        }

        throw CSVDecodingError.typeMismatch(expected: "Bool", actual: value, location: location)
    }

    func decode(_ type: String.Type) throws -> String {
        trimmedValue
    }

    func decode(_ type: Double.Type) throws -> Double {
        guard let result = CSVValueParser.parseDouble(trimmedValue, strategy: configuration.numberDecodingStrategy)
        else {
            throw CSVDecodingError.typeMismatch(expected: "Double", actual: trimmedValue, location: location)
        }
        return result
    }

    func decode(_ type: Float.Type) throws -> Float {
        guard let result = CSVValueParser.parseDouble(trimmedValue, strategy: configuration.numberDecodingStrategy)
        else {
            throw CSVDecodingError.typeMismatch(expected: "Float", actual: trimmedValue, location: location)
        }
        return Float(result)
    }

    func decode(_ type: Int.Type) throws -> Int { try decodeFixedWidthInteger(type) }
    func decode(_ type: Int8.Type) throws -> Int8 { try decodeFixedWidthInteger(type) }
    func decode(_ type: Int16.Type) throws -> Int16 { try decodeFixedWidthInteger(type) }
    func decode(_ type: Int32.Type) throws -> Int32 { try decodeFixedWidthInteger(type) }
    func decode(_ type: Int64.Type) throws -> Int64 { try decodeFixedWidthInteger(type) }
    func decode(_ type: UInt.Type) throws -> UInt { try decodeFixedWidthInteger(type) }
    func decode(_ type: UInt8.Type) throws -> UInt8 { try decodeFixedWidthInteger(type) }
    func decode(_ type: UInt16.Type) throws -> UInt16 { try decodeFixedWidthInteger(type) }
    func decode(_ type: UInt32.Type) throws -> UInt32 { try decodeFixedWidthInteger(type) }

    func decode(_ type: UInt64.Type) throws -> UInt64 {
        // UInt64.max exceeds Int64.max, so the generic helper would
        // round-trip through Int64 and lose half the range. Standard
        // strategy parses unsigned directly; other strategies fall
        // back to the shared signed path with narrowing.
        if case .standard = configuration.numberDecodingStrategy, let direct = UInt64(trimmedValue) {
            return direct
        }
        return try decodeFixedWidthInteger(type)
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        // Handle Date specially
        if type == Date.self, let result = try decodeDate() as? T {
            return result
        }

        // Handle Decimal specially
        if type == Decimal.self {
            guard
                let decimal = CSVValueParser.parseDecimal(trimmedValue, strategy: configuration.numberDecodingStrategy)
            else {
                throw CSVDecodingError.typeMismatch(expected: "Decimal", actual: trimmedValue, location: location)
            }
            if let result = decimal as? T { return result }
        }

        // Handle UUID specially
        if type == UUID.self {
            guard let uuid = UUID(uuidString: trimmedValue) else {
                throw CSVDecodingError.typeMismatch(expected: "UUID", actual: trimmedValue, location: location)
            }
            if let result = uuid as? T { return result }
        }

        // Handle URL specially. Use the strict iOS 17+/macOS 14+ overload so
        // malformed values (spaces, control bytes) are rejected outright.
        if type == URL.self {
            guard let url = URL(string: trimmedValue, encodingInvalidCharacters: false) else {
                throw CSVDecodingError.typeMismatch(expected: "URL", actual: trimmedValue, location: location)
            }
            if let result = url as? T { return result }
        }

        // For other types, they need to implement init(from:) properly
        throw CSVDecodingError.unsupportedType("Cannot decode \(type) from single CSV value")
    }

    // MARK: Private

    /// The value with trimWhitespace applied based on configuration.
    private var trimmedValue: String {
        configuration.trimWhitespace ? value.trimmingCharacters(in: .whitespaces) : value
    }

    private var location: CSVLocation {
        CSVLocation(codingPath: codingPath)
    }

    private func decodeDate() throws -> Date {
        try CSVValueParser.parseDate(
            from: trimmedValue,
            strategy: configuration.dateDecodingStrategy,
            codingPath: codingPath,
        )
    }

    /// Shared parse-then-narrow path for `FixedWidthInteger` types.
    ///
    /// Parses
    /// the trimmed field as `Int64`, then narrows via `T(exactly:)`. The
    /// type name in the diagnostic comes from `T` itself so adding a new
    /// integer width never drifts from the error message.
    ///
    /// `@inline(__always)` is required: without it the bench measured a
    /// +5% regression on numeric-heavy decode paths because the generic
    /// helper wasn't fully specialised through all nine call sites.
    @inline(__always)
    private func decodeFixedWidthInteger<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
        guard let raw = CSVValueParser.parseInt64(trimmedValue, strategy: configuration.numberDecodingStrategy),
            let result = T(exactly: raw)
        else {
            throw CSVDecodingError.typeMismatch(
                expected: String(describing: type),
                actual: trimmedValue,
                location: location,
            )
        }
        return result
    }
}
