//
//  CSVEncoderStrategyTests.swift
//  CSVCoder
//
//  Tests for CSVEncoder encoding strategies.
//

import Foundation
import Testing

@testable import CSVCoder

@Suite("CSVEncoder Strategy Tests")
struct CSVEncoderStrategyTests {
    struct CamelCaseRecord: Codable {
        let firstName: String
        let lastName: String
        let phoneNumber: String
    }

    struct BoolRecord: Codable {
        let name: String
        let active: Bool
    }

    struct NumberRecord: Codable {
        let name: String
        let value: Double
    }

    // MARK: - Key Encoding Strategy Tests

    @Test("Key encoding with snake_case")
    func keyEncodingSnakeCase() throws {
        let records = [CamelCaseRecord(firstName: "John", lastName: "Doe", phoneNumber: "555-1234")]

        let config = CSVEncoder.Configuration(keyEncodingStrategy: .convertToSnakeCase)
        let encoder = CSVEncoder(configuration: config)
        let csv = try encoder.encodeToString(records)

        #expect(csv.contains("first_name"))
        #expect(csv.contains("last_name"))
        #expect(csv.contains("phone_number"))
    }

    @Test("Key encoding with kebab-case")
    func keyEncodingKebabCase() throws {
        let records = [CamelCaseRecord(firstName: "John", lastName: "Doe", phoneNumber: "555-1234")]

        let config = CSVEncoder.Configuration(keyEncodingStrategy: .convertToKebabCase)
        let encoder = CSVEncoder(configuration: config)
        let csv = try encoder.encodeToString(records)

        #expect(csv.contains("first-name"))
        #expect(csv.contains("last-name"))
        #expect(csv.contains("phone-number"))
    }

    @Test("Key encoding with SCREAMING_SNAKE_CASE")
    func keyEncodingScreamingSnakeCase() throws {
        let records = [CamelCaseRecord(firstName: "John", lastName: "Doe", phoneNumber: "555-1234")]

        let config = CSVEncoder.Configuration(keyEncodingStrategy: .convertToScreamingSnakeCase)
        let encoder = CSVEncoder(configuration: config)
        let csv = try encoder.encodeToString(records)

        #expect(csv.contains("FIRST_NAME"))
        #expect(csv.contains("LAST_NAME"))
        #expect(csv.contains("PHONE_NUMBER"))
    }

    @Test("Key encoding with custom transform")
    func keyEncodingCustom() throws {
        let records = [CamelCaseRecord(firstName: "John", lastName: "Doe", phoneNumber: "555-1234")]

        let config = CSVEncoder.Configuration(
            keyEncodingStrategy: .custom { key in
                key.uppercased()
            },
        )
        let encoder = CSVEncoder(configuration: config)
        let csv = try encoder.encodeToString(records)

        #expect(csv.contains("FIRSTNAME"))
        #expect(csv.contains("LASTNAME"))
        #expect(csv.contains("PHONENUMBER"))
    }

    // MARK: - Bool Encoding Strategy Tests

    @Test("Bool encoding with true/false")
    func boolEncodingTrueFalse() throws {
        let records = [
            BoolRecord(name: "A", active: true),
            BoolRecord(name: "B", active: false),
        ]

        let config = CSVEncoder.Configuration(boolEncodingStrategy: .trueFalse)
        let encoder = CSVEncoder(configuration: config)
        let csv = try encoder.encodeToString(records)

        #expect(csv.contains("true"))
        #expect(csv.contains("false"))
    }

    @Test("Bool encoding with numeric")
    func boolEncodingNumeric() throws {
        let records = [
            BoolRecord(name: "A", active: true),
            BoolRecord(name: "B", active: false),
        ]

        let config = CSVEncoder.Configuration(boolEncodingStrategy: .numeric)
        let encoder = CSVEncoder(configuration: config)
        let csv = try encoder.encodeToString(records)

        let lines = csv.components(separatedBy: "\n")
        #expect(lines[1].contains(",1"))
        #expect(lines[2].contains(",0"))
    }

    @Test("Bool encoding with yes/no")
    func boolEncodingYesNo() throws {
        let records = [
            BoolRecord(name: "A", active: true),
            BoolRecord(name: "B", active: false),
        ]

        let config = CSVEncoder.Configuration(boolEncodingStrategy: .yesNo)
        let encoder = CSVEncoder(configuration: config)
        let csv = try encoder.encodeToString(records)

        #expect(csv.contains("yes"))
        #expect(csv.contains("no"))
    }

    @Test("Bool encoding with custom values")
    func boolEncodingCustom() throws {
        let records = [
            BoolRecord(name: "A", active: true),
            BoolRecord(name: "B", active: false),
        ]

        let config = CSVEncoder.Configuration(
            boolEncodingStrategy: .custom(trueValue: "ON", falseValue: "OFF"),
        )
        let encoder = CSVEncoder(configuration: config)
        let csv = try encoder.encodeToString(records)

        #expect(csv.contains("ON"))
        #expect(csv.contains("OFF"))
    }

    // MARK: - Number Encoding Strategy Tests

    @Test("Number encoding with standard strategy")
    func numberEncodingStandard() throws {
        let records = [NumberRecord(name: "A", value: 1234.56)]

        let config = CSVEncoder.Configuration(numberEncodingStrategy: .standard)
        let encoder = CSVEncoder(configuration: config)
        let csv = try encoder.encodeToString(records)

        #expect(csv.contains("1234.56"))
    }

    @Test("Number encoding with locale")
    func numberEncodingWithLocale() throws {
        let records = [NumberRecord(name: "A", value: 1234.56)]

        let germanLocale = Locale(identifier: "de_DE")
        let config = CSVEncoder.Configuration(numberEncodingStrategy: .locale(germanLocale))
        let encoder = CSVEncoder(configuration: config)
        let csv = try encoder.encodeToString(records)

        // German locale uses comma as decimal separator
        #expect(csv.contains("1234,56") || csv.contains("1.234,56"))
    }

    // MARK: - CSVRowBuilder Tests

    @Test("CSVRowBuilder escapes fields correctly")
    func csvRowBuilderEscapesFields() {
        let builder = CSVRowBuilder(delimiter: ",", lineEnding: .lf)
        var buffer: [UInt8] = []

        builder.buildRow(["normal", "has,comma", "has\"quote"], into: &buffer)

        let result = String(decoding: buffer, as: UTF8.self)
        #expect(result.contains("normal"))
        #expect(result.contains("\"has,comma\""))
        #expect(result.contains("\"has\"\"quote\""))
    }

    @Test("CSVRowBuilder uses custom delimiter")
    func csvRowBuilderUsesCustomDelimiter() {
        let builder = CSVRowBuilder(delimiter: ";", lineEnding: .lf)
        var buffer: [UInt8] = []

        builder.buildRow(["a", "b", "c"], into: &buffer)

        let result = String(decoding: buffer, as: UTF8.self)
        #expect(result.contains("a;b;c"))
    }

    @Test("CSVRowBuilder uses CRLF line ending")
    func csvRowBuilderUsesCRLFLineEnding() {
        let builder = CSVRowBuilder(delimiter: ",", lineEnding: .crlf)
        var buffer: [UInt8] = []

        builder.buildRow(["a", "b"], into: &buffer)

        let result = String(decoding: buffer, as: UTF8.self)
        #expect(result.hasSuffix("\r\n"))
    }
}
