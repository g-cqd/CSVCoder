//
//  CSVValueFormatter.swift
//  CSVCoder
//
//  Centralized formatting utilities for CSV encoding.
//  Eliminates duplication between CSVRowEncoder and CSVSingleValueEncoder.
//

import Foundation
import Synchronization

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
                return date.formatted(.iso8601)

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
                // `FloatingPointFormatStyle` is `Sendable` and value-typed, so no
                // cross-thread cache is needed — Foundation's internal ICU cache
                // amortises pattern parsing per locale.
                return value.formatted(
                    .number
                        .locale(locale)
                        .precision(.fractionLength(0...15))
                )

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

    private static func makeDateFormatter(format: String) -> DateFormatter {
        FormatterCache.dateFormatter(for: format)
    }
}

// MARK: - FormatterCache

/// Caches heavyweight Foundation formatters so decoders/encoders that touch
/// many rows don't pay the per-row construction cost (NumberFormatter and
/// DateFormatter both go through ICU initialisation, ~5–50µs each).
///
/// Thread safety: the cache itself is `Mutex`-protected, but the cached
/// instances are `DateFormatter` / `NumberFormatter`, neither of which is
/// safe for concurrent formatting calls. The cache therefore stores
/// canonical templates and hands each caller a `.copy()` so the parallel
/// decode pipeline (which fans out across `TaskGroup`) can format
/// independently. The copy cost is a small fraction of fresh init —
/// the ICU pattern is reused.
enum FormatterCache {
    private static let dateCache = Mutex<[String: DateFormatter]>([:])
    private static let formatDateAutoupdatingCache = Mutex<[String: DateFormatter]>([:])

    static func dateFormatter(for format: String) -> DateFormatter {
        let template = dateCache.withLock { cache -> DateFormatter in
            if let cached = cache[format] {
                return cached
            }
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            cache[format] = formatter
            return formatter
        }
        return (template.copy() as? DateFormatter) ?? template
    }

    /// DateFormatter pinned to `Locale.autoupdatingCurrent` / `TimeZone.autoupdatingCurrent`,.
    ///
    /// for the decoder's `.formatted(_:)` strategy which is expected to honour the user's
    /// locale. Cached separately from the POSIX variant.
    static func userLocaleDateFormatter(for format: String) -> DateFormatter {
        let template = formatDateAutoupdatingCache.withLock { cache -> DateFormatter in
            if let cached = cache[format] {
                return cached
            }
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale.autoupdatingCurrent
            formatter.timeZone = TimeZone.autoupdatingCurrent
            cache[format] = formatter
            return formatter
        }
        return (template.copy() as? DateFormatter) ?? template
    }
}
