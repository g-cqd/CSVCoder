//
//  CSVValueFormatter.swift
//  CSVCoder
//
//  Centralized formatting utilities for CSV encoding.
//  Eliminates duplication between CSVRowEncoder and CSVSingleValueEncoder.
//

import Foundation

// MARK: - CSVValueFormatter

/// Shared utilities for formatting values during CSV encoding.
enum CSVValueFormatter {
    // MARK: - Date Formatting

    /// Formats a Date according to the specified encoding strategy.
    ///
    /// - Parameters:
    ///   - date: The date to format.
    ///   - strategy: The date encoding strategy to use.
    /// - Returns: The formatted date string.
    /// - Throws: `CSVEncodingError` if the strategy is unsupported.
    static func formatDate(_ date: Date, strategy: CSVEncoder.DateEncodingStrategy) throws -> String {
        switch strategy {
        case .deferredToDate:
            throw CSVEncodingError.unsupportedType("deferredToDate requires a date encoding strategy")

        case .secondsSince1970:
            return String(date.timeIntervalSince1970)

        case .millisecondsSince1970:
            return String(date.timeIntervalSince1970 * 1000)

        case .iso8601:
            let formatter = ISO8601DateFormatter()
            return formatter.string(from: date)

        case .formatted(let format):
            let formatter = makeDateFormatter(format: format)
            return formatter.string(from: date)

        case .custom(let closure):
            return try closure(date)
        }
    }

    // MARK: - Number Formatting

    /// Formats a Double according to the specified encoding strategy.
    ///
    /// - Parameters:
    ///   - value: The value to format.
    ///   - strategy: The number encoding strategy to use.
    /// - Returns: The formatted number string.
    /// - Throws: `CSVEncodingError` if custom transform fails.
    static func formatNumber(_ value: Double, strategy: CSVEncoder.NumberEncodingStrategy) throws -> String {
        switch strategy {
        case .standard:
            return String(value)

        case .locale(let locale):
            let formatter = NumberFormatter()
            formatter.locale = locale
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 15
            return formatter.string(from: NSNumber(value: value)) ?? String(value)

        case .custom(let transform):
            return try transform(value)
        }
    }

    // MARK: - Boolean Formatting

    /// Formats a Bool according to the specified encoding strategy.
    ///
    /// - Parameters:
    ///   - value: The boolean value to format.
    ///   - strategy: The bool encoding strategy to use.
    /// - Returns: The formatted boolean string.
    static func formatBool(_ value: Bool, strategy: CSVEncoder.BoolEncodingStrategy) -> String {
        switch strategy {
        case .trueFalse:
            return value ? "true" : "false"

        case .numeric:
            return value ? "1" : "0"

        case .yesNo:
            return value ? "yes" : "no"

        case .custom(let trueValue, let falseValue):
            return value ? trueValue : falseValue
        }
    }

    // MARK: - Private

    /// Creates a DateFormatter with the specified format string.
    private static func makeDateFormatter(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }
}
