//
//  CSVValueParser.swift
//  CSVCoder
//
//  Provides centralized value parsing utilities for CSV decoding.
//  Eliminates duplication between CSVRowDecoder and CSVSingleValueDecoder.
//

import Foundation

// MARK: - CSVValueParser

/// Internal utilities for parsing CSV values according to decoding strategies.
///
/// `CSVValueParser` provides a single source of truth for parsing booleans,
/// numbers, and dates from CSV string values. Both `CSVRowDecoder` and
/// `CSVSingleValueDecoder` delegate to this type for consistent behavior.
///
/// ## Thread Safety
///
/// All methods are thread-safe. Static data (formats, value sets) is immutable
/// after initialization.
enum CSVValueParser {
    // MARK: - Boolean Values

    /// Standard boolean true values.
    static let standardTrueValues: Set<String> = ["true", "yes", "1", "y", "t", "on"]

    /// Standard boolean false values.
    static let standardFalseValues: Set<String> = ["false", "no", "0", "n", "f", "off"]

    /// Extended i18n true values for flexible parsing.
    static let flexibleTrueValues: Set<String> = [
        "true", "yes", "1", "y", "t", "on", "full", "fulltank",
        "oui", "si", "ja", "да", "是", "満", "voll", "真", "sí",
    ]

    /// Extended i18n false values for flexible parsing.
    static let flexibleFalseValues: Set<String> = [
        "false", "no", "0", "n", "f", "off", "partial", "partialtank",
        "non", "nein", "нет", "否", "部分", "假",
    ]

    // MARK: - Date Formats

    /// Common date formats to try, in order of prevalence.
    static let dateFormats: [String] = [
        // ISO 8601
        "yyyy-MM-dd",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd'T'HH:mm:ssZ",
        "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd HH:mm",

        // European (day first)
        "dd/MM/yyyy",
        "dd-MM-yyyy",
        "dd.MM.yyyy",
        "dd/MM/yy",
        "dd-MM-yy",
        "dd.MM.yy",

        // US (month first)
        "MM/dd/yyyy",
        "MM-dd-yyyy",
        "MM/dd/yy",
        "MM-dd-yy",

        // With time
        "dd/MM/yyyy HH:mm",
        "dd/MM/yyyy HH:mm:ss",
        "MM/dd/yyyy HH:mm",
        "MM/dd/yyyy HH:mm:ss",

        // Compact
        "yyyyMMdd",
        "ddMMyyyy",

        // Verbose
        "MMMM d, yyyy",
        "d MMMM yyyy",
        "MMM d, yyyy",
        "d MMM yyyy",
    ]

    // MARK: - Boolean Parsing

    /// Parses a boolean value using the specified strategy.
    static func parseBoolean(
        _ value: String,
        strategy: CSVDecoder.BoolDecodingStrategy
    ) -> Bool? {
        let lowercased = value.lowercased()

        switch strategy {
        case .standard:
            if standardTrueValues.contains(lowercased) { return true }
            if standardFalseValues.contains(lowercased) { return false }
            return nil

        case .flexible:
            if flexibleTrueValues.contains(lowercased) { return true }
            if flexibleFalseValues.contains(lowercased) { return false }
            return nil

        case .custom(let trueValues, let falseValues):
            if trueValues.contains(where: { $0.lowercased() == lowercased }) { return true }
            if falseValues.contains(where: { $0.lowercased() == lowercased }) { return false }
            return nil
        }
    }

    // MARK: - Number Parsing

    /// Parses a Double value using the specified strategy.
    static func parseDouble(
        _ value: String,
        strategy: CSVDecoder.NumberDecodingStrategy
    ) -> Double? {
        switch strategy {
        case .standard:
            return Double(value)

        case .flexible:
            return parseFlexibleDouble(value)

        case .locale(let locale):
            let formatter = NumberFormatter()
            formatter.locale = locale
            formatter.numberStyle = .decimal
            return formatter.number(from: value)?.doubleValue

        case .parseStrategy(let locale):
            return LocaleUtilities.parseDouble(value, locale: locale)

        case .currency(_, let locale):
            return LocaleUtilities.parseDecimal(value, locale: locale)
                .flatMap { Double(truncating: $0 as NSDecimalNumber) }
        }
    }

    /// Parses a Decimal value using the specified strategy.
    static func parseDecimal(
        _ value: String,
        strategy: CSVDecoder.NumberDecodingStrategy
    ) -> Decimal? {
        switch strategy {
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

        case .parseStrategy(let locale):
            return LocaleUtilities.parseDecimal(value, locale: locale)

        case .currency(let code, let locale):
            return LocaleUtilities.parseCurrency(value, code: code, locale: locale)
        }
    }

    /// Parses a numeric value handling various decimal separators and currency symbols.
    /// Supports both US (1,234.56) and EU (1.234,56) formats.
    static func parseFlexibleDouble(_ value: String) -> Double? {
        guard let normalized = normalizeNumberString(value) else { return nil }
        return Double(normalized)
    }

    /// Normalizes a number string by removing currency and fixing decimal separators.
    /// Supports both US (1,234.56) and EU (1.234,56) formats.
    static func normalizeNumberString(_ value: String) -> String? {
        var cleaned = LocaleUtilities.stripCurrencyAndUnits(value)
        guard !cleaned.isEmpty else { return nil }

        let hasComma = cleaned.contains(",")
        let hasDot = cleaned.contains(".")

        if hasComma, hasDot {
            if let lastComma = cleaned.lastIndex(of: ","),
                let lastDot = cleaned.lastIndex(of: ".")
            {
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

    // MARK: - Date Decoding (Strategy-Based)

    /// Parses a date string according to the specified decoding strategy.
    /// Shared implementation used by both `CSVRowDecoder` and `CSVSingleValueDecoder`.
    static func parseDate(
        from value: String,
        strategy: CSVDecoder.DateDecodingStrategy,
        codingPath: [CodingKey],
        row: Int? = nil,
        column: String? = nil,
    ) throws -> Date {
        let location = CSVLocation(row: row, column: column, codingPath: codingPath)

        switch strategy {
        case .deferredToDate:
            throw CSVDecodingError.typeMismatch(
                expected: "Date (use a date strategy)",
                actual: value,
                location: location,
            )

        case .secondsSince1970:
            guard let seconds = Double(value) else {
                throw CSVDecodingError.typeMismatch(expected: "Unix timestamp", actual: value, location: location)
            }
            return Date(timeIntervalSince1970: seconds)

        case .millisecondsSince1970:
            guard let milliseconds = Double(value) else {
                throw CSVDecodingError.typeMismatch(expected: "Unix timestamp (ms)", actual: value, location: location)
            }
            return Date(timeIntervalSince1970: milliseconds / 1000)

        case .iso8601:
            do {
                return try Date.ISO8601FormatStyle().parse(value)
            } catch {
                throw CSVDecodingError.typeMismatch(expected: "ISO8601 date", actual: value, location: location)
            }

        case .formatted(let format):
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale.autoupdatingCurrent
            formatter.timeZone = TimeZone.autoupdatingCurrent
            guard let date = formatter.date(from: value) else {
                throw CSVDecodingError.typeMismatch(
                    expected: "Date with format \(format)",
                    actual: value,
                    location: location,
                )
            }
            return date

        case .custom(let closure):
            return try closure(value)

        case .flexible:
            guard let date = parseFlexibleDate(value, hint: nil) else {
                throw CSVDecodingError.typeMismatch(
                    expected: "Date (no matching format found)",
                    actual: value,
                    location: location,
                )
            }
            return date

        case .flexibleWithHint(let preferred):
            guard let date = parseFlexibleDate(value, hint: preferred) else {
                throw CSVDecodingError.typeMismatch(
                    expected: "Date (no matching format found)",
                    actual: value,
                    location: location,
                )
            }
            return date

        case .localeAware(let locale, let style):
            if let date = LocaleUtilities.parseDate(value, locale: locale, style: style) {
                return date
            }
            if let date = parseFlexibleDate(value, hint: nil) {
                return date
            }
            throw CSVDecodingError.typeMismatch(expected: "Date (locale-aware)", actual: value, location: location)
        }
    }

    // MARK: - Date Parsing

    /// Attempts to parse a date string using multiple formats.
    static func parseFlexibleDate(_ value: String, hint: String?) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        // Try hint first if provided
        if let hint {
            formatter.dateFormat = hint
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }

        // Try all known formats
        for format in dateFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }

        // Try relative date expressions
        return parseRelativeDate(trimmed)
    }

    /// Parses relative date expressions like "today", "yesterday".
    static func parseRelativeDate(_ value: String) -> Date? {
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
