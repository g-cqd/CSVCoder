//
//  LocaleUtilities.swift
//  CSVCoder
//
//  Provides locale-aware parsing utilities using Foundation APIs.
//

import Foundation

// MARK: - LocaleUtilities

/// Internal utilities for locale-aware value parsing.
///
/// `LocaleUtilities` provides parsing capabilities that adapt to regional number
/// and date formats. It leverages Foundation's `FormatStyle.ParseStrategy` for
/// comprehensive locale support across 300+ locales.
///
/// ## Supported Features
///
/// - **Number Parsing**: Handles US (`1,234.56`) and EU (`1.234,56`) formats
/// - **Currency Stripping**: Removes all known currency symbols before parsing
/// - **Unit Stripping**: Removes common measurement units (km, lbs, etc.)
/// - **Date Parsing**: Locale-aware date interpretation (DD/MM vs MM/DD)
///
/// ## Usage
///
/// These utilities are used internally by ``CSVDecoder`` when configured with
/// locale-aware decoding strategies:
///
/// ```swift
/// var config = CSVDecoder.Configuration()
/// config.numberDecodingStrategy = .parseStrategy(locale: .current)
/// config.dateDecodingStrategy = .localeAware(locale: .current, style: .numeric)
/// ```
///
/// ## Thread Safety
///
/// All methods are thread-safe. The `allCurrencySymbols` set is lazily computed
/// once and cached for subsequent access.
enum LocaleUtilities {
    // MARK: Internal

    // MARK: - Currency Symbol Enumeration

    /// All known currency symbols from system locales.
    ///
    /// This set is lazily computed on first access by iterating all available
    /// locale identifiers. Includes both symbols (€, $, £) and common codes
    /// (USD, EUR, GBP).
    ///
    /// - Note: Cached after first computation for O(1) subsequent access.
    static let allCurrencySymbols: Set<String> = {
        var symbols = Set<String>()
        for identifier in Locale.availableIdentifiers {
            let locale = Locale(identifier: identifier)
            if let symbol = locale.currencySymbol {
                symbols.insert(symbol)
            }
        }
        // Add common currency codes as well (USD, EUR, etc.)
        symbols.formUnion(["USD", "EUR", "GBP", "JPY", "CHF", "CAD", "AUD", "CNY", "INR", "BRL"])
        return symbols
    }()

    /// Common unit suffixes to strip from numeric values.
    static let unitSuffixes: Set<String> = [
        "km", "mi", "m", "ft", "yd",
        "l", "L", "gal", "liters", "litres", "gallons",
        "kg", "lb", "lbs", "g", "oz",
        "miles", "kilometers", "metres", "meters",
    ]

    // MARK: - Number Parsing

    /// Strips currency symbols and unit suffixes from a string.
    /// Uses system locale data for comprehensive currency coverage.
    static func stripCurrencyAndUnits(_ value: String) -> String {
        var cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)

        // First, strip unit suffixes (longest first to handle "liters" before "l")
        // Do this before currency to avoid partial matches
        let sortedUnits = unitSuffixes.sorted { $0.count > $1.count }
        for suffix in sortedUnits {
            let lowercased = cleaned.lowercased()
            // Check for suffix with space before it (most common case)
            if lowercased.hasSuffix(" " + suffix.lowercased()) {
                let endIndex = cleaned.index(cleaned.endIndex, offsetBy: -(suffix.count + 1))
                cleaned = String(cleaned[..<endIndex])
                break // Only strip one suffix
            } else if lowercased.hasSuffix(suffix.lowercased()), suffix.count > 1 {
                // For suffixes without space, only match multi-char ones to avoid false positives
                let endIndex = cleaned.index(cleaned.endIndex, offsetBy: -suffix.count)
                let prefix = String(cleaned[..<endIndex]).trimmingCharacters(in: .whitespaces)
                if !prefix.isEmpty, prefix.last?.isNumber == true || prefix.last == "." || prefix.last == "," {
                    cleaned = prefix
                    break
                }
            }
        }

        // Then strip currency symbols (longest first to handle "R$" before "$")
        // Only strip symbols that are at boundaries (start/end or next to space/number)
        let sortedSymbols = allCurrencySymbols.sorted { $0.count > $1.count }
        for symbol in sortedSymbols {
            // Skip single-letter symbols to avoid false positives in unit names
            if symbol.count == 1, symbol.first?.isLetter == true {
                // Only strip single letters if at very start or end
                if cleaned.hasPrefix(symbol) {
                    let rest = String(cleaned.dropFirst(symbol.count)).trimmingCharacters(in: .whitespaces)
                    if rest.first?.isNumber == true || rest.first == "-" {
                        cleaned = rest
                    }
                } else if cleaned.hasSuffix(symbol) {
                    let rest = String(cleaned.dropLast(symbol.count)).trimmingCharacters(in: .whitespaces)
                    if rest.last?.isNumber == true {
                        cleaned = rest
                    }
                }
            } else {
                // Multi-char symbols can be replaced more freely
                cleaned = cleaned.replacingOccurrences(of: symbol, with: "", options: .caseInsensitive)
            }
        }

        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    /// Parses a Double using Foundation's FormatStyle.ParseStrategy.
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
    static func parseDouble(_ value: String, locale: Locale) -> Double? {
        let cleaned = stripCurrencyAndUnits(value)
        guard !cleaned.isEmpty else { return nil }

        // Try locale-specific parsing first
        do {
            let strategy = FloatingPointFormatStyle<Double>.number
                .locale(locale)
                .parseStrategy
            return try strategy.parse(cleaned)
        } catch {
            // Fall back to normalized parsing for mixed formats
            return parseNormalizedDouble(cleaned)
        }
    }

    /// Parses a Decimal using Foundation's FormatStyle.ParseStrategy.
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
    static func parseDecimal(_ value: String, locale: Locale) -> Decimal? {
        let cleaned = stripCurrencyAndUnits(value)
        guard !cleaned.isEmpty else { return nil }

        do {
            let strategy = Decimal.FormatStyle.number
                .locale(locale)
                .parseStrategy
            return try strategy.parse(cleaned)
        } catch {
            return parseNormalizedDecimal(cleaned)
        }
    }

    /// Parses currency value, stripping the currency symbol first.
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
    static func parseCurrency(_ value: String, code: String?, locale: Locale) -> Decimal? {
        let cleaned = stripCurrencyAndUnits(value)
        guard !cleaned.isEmpty else { return nil }

        // Try parsing as a plain decimal with locale
        return parseDecimal(value, locale: locale)
    }

    // MARK: - Date Parsing

    /// Parses a date using locale-aware strategy.
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
    static func parseDate(_ value: String, locale: Locale, style: CSVDecoder.DateDecodingStrategy.DateStyle) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let dateStyle: Date.FormatStyle.DateStyle = switch style {
        case .numeric:
            .numeric

        case .abbreviated:
            .abbreviated

        case .long:
            .long
        }

        // Try strict parsing first
        do {
            let strategy = Date.FormatStyle(date: dateStyle, time: .omitted)
                .locale(locale)
                .parseStrategy
            return try strategy.parse(trimmed)
        } catch {
            // Try with time component
            do {
                let strategy = Date.FormatStyle(date: dateStyle, time: .shortened)
                    .locale(locale)
                    .parseStrategy
                return try strategy.parse(trimmed)
            } catch {
                return nil
            }
        }
    }

    // MARK: Private

    // MARK: - Fallback Parsing (Pre-iOS 15 compatible)

    /// Normalizes a number string by detecting and converting decimal/grouping separators.
    private static func parseNormalizedDouble(_ value: String) -> Double? {
        var cleaned = value

        let hasComma = cleaned.contains(",")
        let hasDot = cleaned.contains(".")

        if hasComma, hasDot {
            if let lastComma = cleaned.lastIndex(of: ","),
               let lastDot = cleaned.lastIndex(of: ".") {
                if lastComma > lastDot {
                    // European: 1.234,56
                    cleaned = cleaned.replacingOccurrences(of: ".", with: "")
                    cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
                } else {
                    // US: 1,234.56
                    cleaned = cleaned.replacingOccurrences(of: ",", with: "")
                }
            }
        } else if hasComma, !hasDot {
            let parts = cleaned.split(separator: ",")
            if parts.count == 2, parts[1].count <= 2 {
                // Likely decimal: 45,50
                cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
            } else {
                // Likely thousands: 1,234,567
                cleaned = cleaned.replacingOccurrences(of: ",", with: "")
            }
        }

        cleaned = String(cleaned.filter { $0.isNumber || $0 == "." || $0 == "-" })
        return Double(cleaned)
    }

    private static func parseNormalizedDecimal(_ value: String) -> Decimal? {
        guard let double = parseNormalizedDouble(value) else { return nil }
        return Decimal(double)
    }
}
