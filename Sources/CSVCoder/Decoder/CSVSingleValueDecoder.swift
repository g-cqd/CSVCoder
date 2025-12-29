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
        let lower = trimmedValue.lowercased()

        switch configuration.boolDecodingStrategy {
        case .standard:
            switch lower {
            case "1",
                 "true",
                 "yes": return true
            case "0",
                 "false",
                 "no": return false
            default: throw CSVDecodingError.typeMismatch(expected: "Bool", actual: value, location: location)
            }

        case .flexible:
            if flexibleTrueValues.contains(lower) { return true }
            if flexibleFalseValues.contains(lower) { return false }
            if let num = Int(lower) { return num != 0 }
            throw CSVDecodingError.typeMismatch(expected: "Bool", actual: value, location: location)

        case let .custom(trueValues, falseValues):
            if trueValues.contains(lower) { return true }
            if falseValues.contains(lower) { return false }
            throw CSVDecodingError.typeMismatch(expected: "Bool", actual: value, location: location)
        }
    }

    func decode(_ type: String.Type) throws -> String {
        trimmedValue
    }

    func decode(_ type: Double.Type) throws -> Double {
        guard let result = parseDouble(trimmedValue) else {
            throw CSVDecodingError.typeMismatch(expected: "Double", actual: trimmedValue, location: location)
        }
        return result
    }

    func decode(_ type: Float.Type) throws -> Float {
        guard let result = parseDouble(trimmedValue) else {
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
        if type == Date.self {
            return try decodeDate() as! T
        }

        // Handle Decimal specially
        if type == Decimal.self {
            guard let decimal = parseDecimal(trimmedValue) else {
                throw CSVDecodingError.typeMismatch(expected: "Decimal", actual: trimmedValue, location: location)
            }
            return decimal as! T
        }

        // Handle UUID specially
        if type == UUID.self {
            guard let uuid = UUID(uuidString: trimmedValue) else {
                throw CSVDecodingError.typeMismatch(expected: "UUID", actual: trimmedValue, location: location)
            }
            return uuid as! T
        }

        // Handle URL specially
        if type == URL.self {
            guard let url = URL(string: trimmedValue) else {
                throw CSVDecodingError.typeMismatch(expected: "URL", actual: trimmedValue, location: location)
            }
            return url as! T
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

    private var flexibleTrueValues: Set<String> {
        ["true", "yes", "1", "y", "t", "on", "full", "fulltank",
         "oui", "si", "ja", "да", "是", "満", "voll", "真", "sí"]
    }

    private var flexibleFalseValues: Set<String> {
        ["false", "no", "0", "n", "f", "off", "partial", "partialtank",
         "non", "nein", "нет", "否", "部分", "假"]
    }

    // MARK: - Flexible Date Parsing

    private var dateFormats: [String] { [
        "yyyy-MM-dd",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd'T'HH:mm:ssZ",
        "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd HH:mm",
        "dd/MM/yyyy",
        "dd-MM-yyyy",
        "dd.MM.yyyy",
        "dd/MM/yy",
        "dd-MM-yy",
        "dd.MM.yy",
        "MM/dd/yyyy",
        "MM-dd-yyyy",
        "MM/dd/yy",
        "MM-dd-yy",
        "dd/MM/yyyy HH:mm",
        "dd/MM/yyyy HH:mm:ss",
        "MM/dd/yyyy HH:mm",
        "MM/dd/yyyy HH:mm:ss",
        "yyyyMMdd",
        "ddMMyyyy",
        "MMMM d, yyyy",
        "d MMMM yyyy",
        "MMM d, yyyy",
        "d MMM yyyy",
    ] }

    // MARK: - Flexible Number Parsing

    private func parseDouble(_ value: String) -> Double? {
        switch configuration.numberDecodingStrategy {
        case .standard:
            return Double(value)

        case .flexible:
            return parseFlexibleDouble(value)

        case let .locale(locale):
            let formatter = NumberFormatter()
            formatter.locale = locale
            formatter.numberStyle = .decimal
            return formatter.number(from: value)?.doubleValue

        case let .parseStrategy(locale):
            if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
                return LocaleUtilities.parseDouble(value, locale: locale)
            } else {
                return parseFlexibleDouble(value)
            }

        case let .currency(_, locale):
            if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
                return LocaleUtilities.parseDecimal(value, locale: locale)
                    .flatMap { Double(truncating: $0 as NSDecimalNumber) }
            } else {
                return parseFlexibleDouble(value)
            }
        }
    }

    private func parseFlexibleDouble(_ value: String) -> Double? {
        // Use LocaleUtilities to strip currency symbols and units
        var cleaned = LocaleUtilities.stripCurrencyAndUnits(value)
        guard !cleaned.isEmpty else { return nil }

        let hasComma = cleaned.contains(",")
        let hasDot = cleaned.contains(".")

        if hasComma, hasDot {
            if let lastComma = cleaned.lastIndex(of: ","),
               let lastDot = cleaned.lastIndex(of: ".") {
                if lastComma > lastDot {
                    cleaned = cleaned.replacingOccurrences(of: ".", with: "")
                    cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
                } else {
                    cleaned = cleaned.replacingOccurrences(of: ",", with: "")
                }
            }
        } else if hasComma, !hasDot {
            let parts = cleaned.split(separator: ",")
            if parts.count == 2, parts[1].count <= 2 {
                cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
            } else {
                cleaned = cleaned.replacingOccurrences(of: ",", with: "")
            }
        }

        cleaned = String(cleaned.filter { $0.isNumber || $0 == "." || $0 == "-" })
        return Double(cleaned)
    }

    private func parseDecimal(_ value: String) -> Decimal? {
        switch configuration.numberDecodingStrategy {
        case .standard:
            return Decimal(string: value)

        case .flexible:
            guard let cleaned = normalizeNumberString(value) else { return nil }
            return Decimal(string: cleaned)

        case let .locale(locale):
            let formatter = NumberFormatter()
            formatter.locale = locale
            formatter.numberStyle = .decimal
            return formatter.number(from: value)?.decimalValue

        case let .parseStrategy(locale):
            if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
                return LocaleUtilities.parseDecimal(value, locale: locale)
            } else {
                guard let cleaned = normalizeNumberString(value) else { return nil }
                return Decimal(string: cleaned)
            }

        case let .currency(code, locale):
            if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
                return LocaleUtilities.parseCurrency(value, code: code, locale: locale)
            } else {
                guard let cleaned = normalizeNumberString(value) else { return nil }
                return Decimal(string: cleaned)
            }
        }
    }

    private func normalizeNumberString(_ value: String) -> String? {
        // Use LocaleUtilities to strip currency symbols and units
        var cleaned = LocaleUtilities.stripCurrencyAndUnits(value)
        guard !cleaned.isEmpty else { return nil }

        let hasComma = cleaned.contains(",")
        let hasDot = cleaned.contains(".")

        if hasComma, hasDot {
            if let lastComma = cleaned.lastIndex(of: ","),
               let lastDot = cleaned.lastIndex(of: ".") {
                if lastComma > lastDot {
                    cleaned = cleaned.replacingOccurrences(of: ".", with: "")
                    cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
                } else {
                    cleaned = cleaned.replacingOccurrences(of: ",", with: "")
                }
            }
        } else if hasComma, !hasDot {
            let parts = cleaned.split(separator: ",")
            if parts.count == 2, parts[1].count <= 2 {
                cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
            } else {
                cleaned = cleaned.replacingOccurrences(of: ",", with: "")
            }
        }

        cleaned = String(cleaned.filter { $0.isNumber || $0 == "." || $0 == "-" })
        return cleaned.isEmpty ? nil : cleaned
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

        case let .formatted(format):
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

        case let .custom(closure):
            return try closure(dateValue)

        case .flexible:
            guard let date = parseFlexibleDate(dateValue, hint: nil) else {
                throw CSVDecodingError.typeMismatch(
                    expected: "Date (no matching format found)",
                    actual: dateValue,
                    location: location,
                )
            }
            return date

        case let .flexibleWithHint(preferred):
            guard let date = parseFlexibleDate(dateValue, hint: preferred) else {
                throw CSVDecodingError.typeMismatch(
                    expected: "Date (no matching format found)",
                    actual: dateValue,
                    location: location,
                )
            }
            return date

        case let .localeAware(locale, style):
            if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
                if let date = LocaleUtilities.parseDate(dateValue, locale: locale, style: style) {
                    return date
                }
                // Fall back to flexible parsing if locale-aware fails
                if let date = parseFlexibleDate(dateValue, hint: nil) {
                    return date
                }
                throw CSVDecodingError.typeMismatch(
                    expected: "Date (locale-aware)",
                    actual: dateValue,
                    location: location,
                )
            } else {
                // Pre-iOS 15: use flexible parsing
                guard let date = parseFlexibleDate(dateValue, hint: nil) else {
                    throw CSVDecodingError.typeMismatch(expected: "Date", actual: dateValue, location: location)
                }
                return date
            }
        }
    }

    private func parseFlexibleDate(_ value: String, hint: String?) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        if let hint = hint {
            formatter.dateFormat = hint
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }

        for format in dateFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }

        return parseRelativeDate(trimmed)
    }

    private func parseRelativeDate(_ value: String) -> Date? {
        let lower = value.lowercased()
        let calendar = Calendar.current

        switch lower {
        case "today":
            return calendar.startOfDay(for: Date())

        case "yesterday":
            return calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))

        default:
            return nil
        }
    }
}
