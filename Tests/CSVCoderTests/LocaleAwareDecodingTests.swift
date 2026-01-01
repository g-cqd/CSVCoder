//
//  LocaleAwareDecodingTests.swift
//  CSVCoder
//
//  Tests for locale-aware decoding strategies.
//

import Foundation
import Testing

@testable import CSVCoder

@Suite("Locale-Aware Decoding Tests")
struct LocaleAwareDecodingTests {
    // MARK: - Test Models

    struct PriceRecord: Codable, Equatable {
        let item: String
        let price: Double
    }

    struct DecimalRecord: Codable, Equatable {
        let item: String
        let amount: Decimal
    }

    struct DateRecord: Codable, Equatable {
        let event: String
        let date: Date
    }

    // MARK: - NumberDecodingStrategy.parseStrategy Tests

    @Test("ParseStrategy decodes US format numbers")
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
    func parseStrategyUSFormat() throws {
        let csv = """
            item,price
            Widget,1234.56
            Gadget,999.99
            """

        let config = CSVDecoder.Configuration(
            numberDecodingStrategy: .parseStrategy(locale: Locale(identifier: "en_US")),
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([PriceRecord].self, from: csv)

        #expect(records.count == 2)
        #expect(records[0].price == 1234.56)
        #expect(records[1].price == 999.99)
    }

    @Test("ParseStrategy decodes German format numbers")
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
    func parseStrategyGermanFormat() throws {
        let csv = """
            item,price
            Widget,"1.234,56"
            Gadget,"999,99"
            """

        let config = CSVDecoder.Configuration(
            numberDecodingStrategy: .parseStrategy(locale: Locale(identifier: "de_DE")),
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([PriceRecord].self, from: csv)

        #expect(records.count == 2)
        #expect(records[0].price == 1234.56)
        #expect(records[1].price == 999.99)
    }

    @Test("ParseStrategy strips currency symbols automatically")
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
    func parseStrategyStripsCurrency() throws {
        let csv = """
            item,price
            Widget,$45.99
            Gadget,€29.99
            Gizmo,£19.99
            """

        let config = CSVDecoder.Configuration(
            numberDecodingStrategy: .parseStrategy(locale: Locale(identifier: "en_US")),
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([PriceRecord].self, from: csv)

        #expect(records.count == 3)
        #expect(records[0].price == 45.99)
        #expect(records[1].price == 29.99)
        #expect(records[2].price == 19.99)
    }

    @Test("ParseStrategy handles unit suffixes")
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
    func parseStrategyStripsUnits() throws {
        let csv = """
            item,price
            Distance,100 km
            Fuel,45.5 L
            """

        let config = CSVDecoder.Configuration(
            numberDecodingStrategy: .parseStrategy(locale: Locale(identifier: "en_US")),
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([PriceRecord].self, from: csv)

        #expect(records.count == 2)
        #expect(records[0].price == 100.0)
        #expect(records[1].price == 45.5)
    }

    // MARK: - NumberDecodingStrategy.currency Tests

    @Test("Currency strategy decodes prices with symbols")
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
    func currencyStrategyWithSymbols() throws {
        let csv = """
            item,amount
            Sale,$1234.56
            Refund,-$50.00
            """

        let config = CSVDecoder.Configuration(
            numberDecodingStrategy: .currency(code: "USD", locale: Locale(identifier: "en_US")),
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([DecimalRecord].self, from: csv)

        #expect(records.count == 2)
        #expect(records[0].amount == Decimal(string: "1234.56"))
        #expect(records[1].amount == Decimal(string: "-50.00"))
    }

    @Test("Currency strategy handles European format")
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
    func currencyStrategyEuropeanFormat() throws {
        let csv = """
            item,amount
            Sale,"1.234,56 €"
            Tax,"99,99 €"
            """

        let config = CSVDecoder.Configuration(
            numberDecodingStrategy: .currency(code: "EUR", locale: Locale(identifier: "de_DE")),
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([DecimalRecord].self, from: csv)

        #expect(records.count == 2)
        #expect(records[0].amount == Decimal(string: "1234.56"))
        #expect(records[1].amount == Decimal(string: "99.99"))
    }

    // MARK: - DateDecodingStrategy.localeAware Tests

    @Test("LocaleAware decodes US date format")
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
    func localeAwareUSDateFormat() throws {
        let csv = """
            event,date
            Birthday,12/25/2024
            Anniversary,01/15/2025
            """

        let config = CSVDecoder.Configuration(
            dateDecodingStrategy: .localeAware(locale: Locale(identifier: "en_US"), style: .numeric),
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([DateRecord].self, from: csv)

        #expect(records.count == 2)

        let calendar = Calendar.current
        let date1 = records[0].date
        #expect(calendar.component(.month, from: date1) == 12)
        #expect(calendar.component(.day, from: date1) == 25)
        #expect(calendar.component(.year, from: date1) == 2024)
    }

    @Test("LocaleAware decodes UK date format")
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
    func localeAwareUKDateFormat() throws {
        let csv = """
            event,date
            Birthday,25/12/2024
            Anniversary,15/01/2025
            """

        let config = CSVDecoder.Configuration(
            dateDecodingStrategy: .localeAware(locale: Locale(identifier: "en_GB"), style: .numeric),
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([DateRecord].self, from: csv)

        #expect(records.count == 2)

        let calendar = Calendar.current
        let date1 = records[0].date
        #expect(calendar.component(.month, from: date1) == 12)
        #expect(calendar.component(.day, from: date1) == 25)
        #expect(calendar.component(.year, from: date1) == 2024)
    }

    @Test("LocaleAware falls back to flexible parsing")
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
    func localeAwareFallback() throws {
        let csv = """
            event,date
            Birthday,2024-12-25
            """

        let config = CSVDecoder.Configuration(
            dateDecodingStrategy: .localeAware(locale: Locale(identifier: "en_US"), style: .numeric),
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([DateRecord].self, from: csv)

        #expect(records.count == 1)

        let calendar = Calendar.current
        let date1 = records[0].date
        #expect(calendar.component(.month, from: date1) == 12)
        #expect(calendar.component(.day, from: date1) == 25)
    }

    // MARK: - LocaleUtilities Tests

    @Test("LocaleUtilities strips various currency symbols")
    func localeUtilitiesStripsCurrencies() {
        let testCases = [
            ("$100", "100"),
            ("€50", "50"),
            ("£75", "75"),
            ("¥1000", "1000"),
            ("100 USD", "100"),
            ("EUR 200", "200"),
            ("CHF 150", "150"),
            ("R$ 500", "500"),
        ]

        for (input, expected) in testCases {
            let result = LocaleUtilities.stripCurrencyAndUnits(input)
            #expect(result == expected, "Expected '\(expected)' for '\(input)', got '\(result)'")
        }
    }

    @Test("LocaleUtilities strips unit suffixes")
    func localeUtilitiesStripsUnits() {
        let testCases = [
            ("100 km", "100"),
            ("50 mi", "50"),
            ("45.5 L", "45.5"),
            ("10 gal", "10"),
            ("75 liters", "75"),
        ]

        for (input, expected) in testCases {
            let result = LocaleUtilities.stripCurrencyAndUnits(input)
            #expect(result == expected, "Expected '\(expected)' for '\(input)', got '\(result)'")
        }
    }

    @Test("LocaleUtilities preserves numbers without symbols")
    func localeUtilitiesPreservesPlainNumbers() {
        let testCases = [
            ("100", "100"),
            ("1234.56", "1234.56"),
            ("-50", "-50"),
            ("0.99", "0.99"),
        ]

        for (input, expected) in testCases {
            let result = LocaleUtilities.stripCurrencyAndUnits(input)
            #expect(result == expected, "Expected '\(expected)' for '\(input)', got '\(result)'")
        }
    }

    @Test("AllCurrencySymbols contains common symbols")
    func allCurrencySymbolsContainsCommon() {
        let symbols = LocaleUtilities.allCurrencySymbols

        // These should be present from system locales
        #expect(symbols.contains("$"))
        #expect(symbols.contains("€"))
        #expect(symbols.contains("£"))
        #expect(symbols.contains("¥"))

        // Should have many symbols (180+ from all locales)
        #expect(symbols.count >= 50)
    }
}
