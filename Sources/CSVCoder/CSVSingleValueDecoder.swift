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
        let lower = value.lowercased().trimmingCharacters(in: .whitespaces)

        switch configuration.boolDecodingStrategy {
        case .standard:
            switch lower {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: throw CSVDecodingError.typeMismatch(expected: "Bool", actual: value)
            }

        case .flexible:
            if flexibleTrueValues.contains(lower) { return true }
            if flexibleFalseValues.contains(lower) { return false }
            if let num = Int(lower) { return num != 0 }
            throw CSVDecodingError.typeMismatch(expected: "Bool", actual: value)

        case .custom(let trueValues, let falseValues):
            if trueValues.contains(lower) { return true }
            if falseValues.contains(lower) { return false }
            throw CSVDecodingError.typeMismatch(expected: "Bool", actual: value)
        }
    }

    private var flexibleTrueValues: Set<String> {
        ["true", "yes", "1", "y", "t", "on", "full", "fulltank",
         "oui", "si", "ja", "да", "是", "満", "voll", "真", "sí"]
    }

    private var flexibleFalseValues: Set<String> {
        ["false", "no", "0", "n", "f", "off", "partial", "partialtank",
         "non", "nein", "нет", "否", "部分", "假"]
    }

    func decode(_ type: String.Type) throws -> String {
        value
    }

    func decode(_ type: Double.Type) throws -> Double {
        guard let result = parseDouble(value) else {
            throw CSVDecodingError.typeMismatch(expected: "Double", actual: value)
        }
        return result
    }

    func decode(_ type: Float.Type) throws -> Float {
        guard let result = parseDouble(value) else {
            throw CSVDecodingError.typeMismatch(expected: "Float", actual: value)
        }
        return Float(result)
    }

    // MARK: - Flexible Number Parsing

    private func parseDouble(_ value: String) -> Double? {
        switch configuration.numberDecodingStrategy {
        case .standard:
            return Double(value)

        case .flexible:
            return parseFlexibleDouble(value)

        case .locale(let locale):
            let formatter = NumberFormatter()
            formatter.locale = locale
            formatter.numberStyle = .decimal
            return formatter.number(from: value)?.doubleValue
        }
    }

    private func parseFlexibleDouble(_ value: String) -> Double? {
        var cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        let removePatterns = ["$", "€", "£", "¥", "kr", "zł", "₹", "R$", "CHF", "CAD", "USD", "EUR", "GBP",
                              "km", "mi", "l", "L", "gal", "liters", "litres", "gallons", "miles", "kilometers"]
        for pattern in removePatterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: .caseInsensitive)
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)

        let hasComma = cleaned.contains(",")
        let hasDot = cleaned.contains(".")

        if hasComma && hasDot {
            if let lastComma = cleaned.lastIndex(of: ","),
               let lastDot = cleaned.lastIndex(of: ".") {
                if lastComma > lastDot {
                    cleaned = cleaned.replacingOccurrences(of: ".", with: "")
                    cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
                } else {
                    cleaned = cleaned.replacingOccurrences(of: ",", with: "")
                }
            }
        } else if hasComma && !hasDot {
            let parts = cleaned.split(separator: ",")
            if parts.count == 2 && parts[1].count <= 2 {
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

        case .locale(let locale):
            let formatter = NumberFormatter()
            formatter.locale = locale
            formatter.numberStyle = .decimal
            return formatter.number(from: value)?.decimalValue
        }
    }

    private func normalizeNumberString(_ value: String) -> String? {
        var cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        let removePatterns = ["$", "€", "£", "¥", "kr", "zł", "₹", "R$", "CHF", "CAD", "USD", "EUR", "GBP",
                              "km", "mi", "l", "L", "gal", "liters", "litres", "gallons", "miles", "kilometers"]
        for pattern in removePatterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: .caseInsensitive)
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)

        let hasComma = cleaned.contains(",")
        let hasDot = cleaned.contains(".")

        if hasComma && hasDot {
            if let lastComma = cleaned.lastIndex(of: ","),
               let lastDot = cleaned.lastIndex(of: ".") {
                if lastComma > lastDot {
                    cleaned = cleaned.replacingOccurrences(of: ".", with: "")
                    cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
                } else {
                    cleaned = cleaned.replacingOccurrences(of: ",", with: "")
                }
            }
        } else if hasComma && !hasDot {
            let parts = cleaned.split(separator: ",")
            if parts.count == 2 && parts[1].count <= 2 {
                cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
            } else {
                cleaned = cleaned.replacingOccurrences(of: ",", with: "")
            }
        }

        cleaned = String(cleaned.filter { $0.isNumber || $0 == "." || $0 == "-" })
        return cleaned.isEmpty ? nil : cleaned
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

        // Handle Decimal specially
        if type == Decimal.self {
            guard let decimal = parseDecimal(value) else {
                throw CSVDecodingError.typeMismatch(expected: "Decimal", actual: value)
            }
            return decimal as! T
        }

        // Handle UUID specially
        if type == UUID.self {
            guard let uuid = UUID(uuidString: value) else {
                throw CSVDecodingError.typeMismatch(expected: "UUID", actual: value)
            }
            return uuid as! T
        }

        // Handle URL specially
        if type == URL.self {
            guard let url = URL(string: value) else {
                throw CSVDecodingError.typeMismatch(expected: "URL", actual: value)
            }
            return url as! T
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

        case .flexible:
            guard let date = parseFlexibleDate(value, hint: nil) else {
                throw CSVDecodingError.typeMismatch(expected: "Date (no matching format found)", actual: value)
            }
            return date

        case .flexibleWithHint(let preferred):
            guard let date = parseFlexibleDate(value, hint: preferred) else {
                throw CSVDecodingError.typeMismatch(expected: "Date (no matching format found)", actual: value)
            }
            return date
        }
    }

    // MARK: - Flexible Date Parsing

    private var dateFormats: [String] {[
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
        "d MMM yyyy"
    ]}

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
