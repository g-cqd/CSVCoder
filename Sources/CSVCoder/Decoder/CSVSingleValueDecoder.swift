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

    func decode(_ type: Int.Type) throws -> Int {
        guard let result = Int(trimmedValue) else {
            throw CSVDecodingError.typeMismatch(expected: "Int", actual: trimmedValue, location: location)
        }
        return result
    }

    func decode(_ type: Int8.Type) throws -> Int8 {
        guard let result = Int8(trimmedValue) else {
            throw CSVDecodingError.typeMismatch(expected: "Int8", actual: trimmedValue, location: location)
        }
        return result
    }

    func decode(_ type: Int16.Type) throws -> Int16 {
        guard let result = Int16(trimmedValue) else {
            throw CSVDecodingError.typeMismatch(expected: "Int16", actual: trimmedValue, location: location)
        }
        return result
    }

    func decode(_ type: Int32.Type) throws -> Int32 {
        guard let result = Int32(trimmedValue) else {
            throw CSVDecodingError.typeMismatch(expected: "Int32", actual: trimmedValue, location: location)
        }
        return result
    }

    func decode(_ type: Int64.Type) throws -> Int64 {
        guard let result = Int64(trimmedValue) else {
            throw CSVDecodingError.typeMismatch(expected: "Int64", actual: trimmedValue, location: location)
        }
        return result
    }

    func decode(_ type: UInt.Type) throws -> UInt {
        guard let result = UInt(trimmedValue) else {
            throw CSVDecodingError.typeMismatch(expected: "UInt", actual: trimmedValue, location: location)
        }
        return result
    }

    func decode(_ type: UInt8.Type) throws -> UInt8 {
        guard let result = UInt8(trimmedValue) else {
            throw CSVDecodingError.typeMismatch(expected: "UInt8", actual: trimmedValue, location: location)
        }
        return result
    }

    func decode(_ type: UInt16.Type) throws -> UInt16 {
        guard let result = UInt16(trimmedValue) else {
            throw CSVDecodingError.typeMismatch(expected: "UInt16", actual: trimmedValue, location: location)
        }
        return result
    }

    func decode(_ type: UInt32.Type) throws -> UInt32 {
        guard let result = UInt32(trimmedValue) else {
            throw CSVDecodingError.typeMismatch(expected: "UInt32", actual: trimmedValue, location: location)
        }
        return result
    }

    func decode(_ type: UInt64.Type) throws -> UInt64 {
        guard let result = UInt64(trimmedValue) else {
            throw CSVDecodingError.typeMismatch(expected: "UInt64", actual: trimmedValue, location: location)
        }
        return result
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

        // Handle URL specially
        if type == URL.self {
            guard let url = URL(string: trimmedValue) else {
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
        let dateValue = trimmedValue
        switch configuration.dateDecodingStrategy {
        case .deferredToDate:
            throw CSVDecodingError.typeMismatch(
                expected: "Date (use a date strategy)",
                actual: dateValue,
                location: location,
            )

        case .secondsSince1970:
            guard let seconds = Double(dateValue) else {
                throw CSVDecodingError.typeMismatch(expected: "Unix timestamp", actual: dateValue, location: location)
            }
            return Date(timeIntervalSince1970: seconds)

        case .millisecondsSince1970:
            guard let milliseconds = Double(dateValue) else {
                throw CSVDecodingError.typeMismatch(
                    expected: "Unix timestamp (ms)",
                    actual: dateValue,
                    location: location,
                )
            }
            return Date(timeIntervalSince1970: milliseconds / 1000)

        case .iso8601:
            let formatter = ISO8601DateFormatter()
            guard let date = formatter.date(from: dateValue) else {
                throw CSVDecodingError.typeMismatch(expected: "ISO8601 date", actual: dateValue, location: location)
            }
            return date

        case .formatted(let format):
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale.autoupdatingCurrent
            formatter.timeZone = TimeZone.autoupdatingCurrent
            guard let date = formatter.date(from: dateValue) else {
                throw CSVDecodingError.typeMismatch(
                    expected: "Date with format \(format)",
                    actual: dateValue,
                    location: location,
                )
            }
            return date

        case .custom(let closure):
            return try closure(dateValue)

        case .flexible:
            guard let date = CSVValueParser.parseFlexibleDate(dateValue, hint: nil) else {
                throw CSVDecodingError.typeMismatch(
                    expected: "Date (no matching format found)",
                    actual: dateValue,
                    location: location,
                )
            }
            return date

        case .flexibleWithHint(let preferred):
            guard let date = CSVValueParser.parseFlexibleDate(dateValue, hint: preferred) else {
                throw CSVDecodingError.typeMismatch(
                    expected: "Date (no matching format found)",
                    actual: dateValue,
                    location: location,
                )
            }
            return date

        case .localeAware(let locale, let style):
            guard #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) else {
                // Pre-iOS 15: use flexible parsing
                guard let date = CSVValueParser.parseFlexibleDate(dateValue, hint: nil) else {
                    throw CSVDecodingError.typeMismatch(expected: "Date", actual: dateValue, location: location)
                }
                return date
            }
            if let date = LocaleUtilities.parseDate(dateValue, locale: locale, style: style) {
                return date
            }
            // Fall back to flexible parsing if locale-aware fails
            if let date = CSVValueParser.parseFlexibleDate(dateValue, hint: nil) {
                return date
            }
            throw CSVDecodingError.typeMismatch(
                expected: "Date (locale-aware)",
                actual: dateValue,
                location: location,
            )
        }
    }
}
