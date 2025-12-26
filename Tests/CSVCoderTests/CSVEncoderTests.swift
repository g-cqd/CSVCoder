//
//  CSVEncoderTests.swift
//  CSVCoder
//
//  Tests for CSVEncoder.
//

import Testing
@testable import CSVCoder
import Foundation

@Suite("CSVEncoder Tests")
struct CSVEncoderTests {

    struct SimpleRecord: Codable, Equatable {
        let name: String
        let age: Int
        let score: Double
    }

    @Test("Encode simple records")
    func encodeSimpleRecords() throws {
        let records = [
            SimpleRecord(name: "Alice", age: 30, score: 95.5),
            SimpleRecord(name: "Bob", age: 25, score: 88.0)
        ]

        let encoder = CSVEncoder()
        let csv = try encoder.encodeToString(records)

        #expect(csv.contains("name,age,score"))
        #expect(csv.contains("Alice,30,95.5"))
        #expect(csv.contains("Bob,25,88.0"))
    }

    @Test("Encode with semicolon delimiter")
    func encodeWithSemicolonDelimiter() throws {
        let records = [SimpleRecord(name: "Charlie", age: 35, score: 90.0)]

        let config = CSVEncoder.Configuration(delimiter: ";")
        let encoder = CSVEncoder(configuration: config)
        let csv = try encoder.encodeToString(records)

        #expect(csv.contains("name;age;score"))
        #expect(csv.contains("Charlie;35;90.0"))
    }

    @Test("Encode without headers")
    func encodeWithoutHeaders() throws {
        let records = [SimpleRecord(name: "Dave", age: 40, score: 85.0)]

        let config = CSVEncoder.Configuration(includeHeaders: false)
        let encoder = CSVEncoder(configuration: config)
        let csv = try encoder.encodeToString(records)

        #expect(!csv.contains("name"))
        #expect(csv.contains("Dave"))
    }

    struct DateRecord: Codable {
        let event: String
        let date: Date
    }

    @Test("Encode dates with ISO8601")
    func encodeDatesISO8601() throws {
        let date = Date(timeIntervalSince1970: 0)
        let records = [DateRecord(event: "Launch", date: date)]

        let encoder = CSVEncoder()
        let csv = try encoder.encodeToString(records)

        #expect(csv.contains("1970-01-01"))
    }

    @Test("Encode dates with custom format")
    func encodeDatesCustomFormat() throws {
        let date = Date(timeIntervalSince1970: 1735084800) // 2024-12-25
        let records = [DateRecord(event: "Christmas", date: date)]

        let config = CSVEncoder.Configuration(dateEncodingStrategy: .formatted("dd/MM/yyyy"))
        let encoder = CSVEncoder(configuration: config)
        let csv = try encoder.encodeToString(records)

        #expect(csv.contains("25/12/2024"))
    }

    struct QuotedRecord: Codable {
        let name: String
        let description: String
    }

    @Test("Escape fields with delimiter")
    func escapeFieldsWithDelimiter() throws {
        let records = [QuotedRecord(name: "Test", description: "Value,with,commas")]

        let encoder = CSVEncoder()
        let csv = try encoder.encodeToString(records)

        #expect(csv.contains("\"Value,with,commas\""))
    }

    @Test("Escape fields with quotes")
    func escapeFieldsWithQuotes() throws {
        let records = [QuotedRecord(name: "Test", description: "Say \"Hello\"")]

        let encoder = CSVEncoder()
        let csv = try encoder.encodeToString(records)

        #expect(csv.contains("\"Say \"\"Hello\"\"\""))
    }

    @Test("Escape fields with newlines")
    func escapeFieldsWithNewlines() throws {
        let records = [QuotedRecord(name: "Test", description: "Line1\nLine2")]

        let encoder = CSVEncoder()
        let csv = try encoder.encodeToString(records)

        #expect(csv.contains("\"Line1\nLine2\""))
    }

    struct OptionalRecord: Codable {
        let name: String
        let value: String?
    }

    @Test("Encode nil as empty string")
    func encodeNilAsEmptyString() throws {
        let records = [OptionalRecord(name: "Test", value: nil)]

        let encoder = CSVEncoder()
        let csv = try encoder.encodeToString(records)

        #expect(csv.contains("Test,"))
    }

    struct BoolRecord: Codable {
        let name: String
        let active: Bool
    }

    @Test("Encode boolean values")
    func encodeBooleanValues() throws {
        let records = [
            BoolRecord(name: "Yes", active: true),
            BoolRecord(name: "No", active: false)
        ]

        let encoder = CSVEncoder()
        let csv = try encoder.encodeToString(records)

        #expect(csv.contains("Yes,1"))
        #expect(csv.contains("No,0"))
    }

    struct DecimalRecord: Codable, Equatable {
        let price: Decimal
        let quantity: Int
    }

    @Test("Encode Decimal values")
    func encodeDecimalValues() throws {
        let records = [
            DecimalRecord(price: Decimal(string: "19.99")!, quantity: 100),
            DecimalRecord(price: Decimal(string: "0.001")!, quantity: 999999)
        ]

        let encoder = CSVEncoder()
        let csv = try encoder.encodeToString(records)

        #expect(csv.contains("19.99"))
        #expect(csv.contains("0.001"))
    }

    struct UUIDRecord: Codable {
        let id: UUID
        let name: String
    }

    @Test("Encode UUID values")
    func encodeUUIDValues() throws {
        let uuid = UUID()
        let records = [UUIDRecord(id: uuid, name: "Item")]

        let encoder = CSVEncoder()
        let csv = try encoder.encodeToString(records)

        #expect(csv.contains(uuid.uuidString))
    }

    struct URLRecord: Codable {
        let name: String
        let website: URL
    }

    @Test("Encode URL values")
    func encodeURLValues() throws {
        let url = URL(string: "https://example.com/path?query=1")!
        let records = [URLRecord(name: "Example", website: url)]

        let encoder = CSVEncoder()
        let csv = try encoder.encodeToString(records)

        #expect(csv.contains(url.absoluteString))
    }

    @Test("Encode to Data")
    func encodeToData() throws {
        let records = [SimpleRecord(name: "Test", age: 25, score: 90.0)]

        let encoder = CSVEncoder()
        let data = try encoder.encode(records)

        let string = String(data: data, encoding: .utf8)
        #expect(string?.contains("Test") == true)
    }

    @Test("Encode single row")
    func encodeSingleRow() throws {
        let record = SimpleRecord(name: "Single", age: 30, score: 85.0)

        let encoder = CSVEncoder()
        let row = try encoder.encodeRow(record)

        #expect(!row.contains("name"))  // No header
        #expect(row.contains("Single"))
        #expect(row.contains("30"))
    }

    @Test("Encode to dictionary")
    func encodeToDictionary() throws {
        let record = SimpleRecord(name: "Dict", age: 28, score: 92.5)

        let encoder = CSVEncoder()
        let dict = try encoder.encodeToDictionary(record)

        #expect(dict["name"] == "Dict")
        #expect(dict["age"] == "28")
        #expect(dict["score"] == "92.5")
    }

    @Test("Roundtrip encode-decode")
    func roundtripEncodeDecode() throws {
        let original = [
            SimpleRecord(name: "Alice", age: 30, score: 95.5),
            SimpleRecord(name: "Bob", age: 25, score: 88.0)
        ]

        let encoder = CSVEncoder()
        let csv = try encoder.encodeToString(original)

        let decoder = CSVDecoder()
        let decoded = try decoder.decode([SimpleRecord].self, from: csv)

        #expect(original == decoded)
    }

    @Test("Roundtrip with special characters")
    func roundtripWithSpecialCharacters() throws {
        let original = [
            QuotedRecord(name: "Special", description: "Has, commas and \"quotes\"")
        ]

        let encoder = CSVEncoder()
        let csv = try encoder.encodeToString(original)

        let decoder = CSVDecoder()
        let decoded = try decoder.decode([QuotedRecord].self, from: csv)

        #expect(decoded[0].description == original[0].description)
    }

    @Test("Roundtrip Decimal preserves precision")
    func roundtripDecimalPreservesPrecision() throws {
        let original = [
            DecimalRecord(price: Decimal(string: "123.456789")!, quantity: 1)
        ]

        let encoder = CSVEncoder()
        let csv = try encoder.encodeToString(original)

        let decoder = CSVDecoder()
        let decoded = try decoder.decode([DecimalRecord].self, from: csv)

        #expect(original == decoded)
    }

    @Test("Encode empty array")
    func encodeEmptyArray() throws {
        let records: [SimpleRecord] = []

        let encoder = CSVEncoder()
        let csv = try encoder.encodeToString(records)

        #expect(csv.isEmpty)
    }

    struct AllNumericTypes: Codable, Equatable {
        let int: Int
        let int8: Int8
        let int16: Int16
        let int32: Int32
        let int64: Int64
        let uint: UInt
        let uint8: UInt8
        let uint16: UInt16
        let uint32: UInt32
        let uint64: UInt64
        let float: Float
        let double: Double
    }

    @Test("Roundtrip all numeric types")
    func roundtripAllNumericTypes() throws {
        let original = [
            AllNumericTypes(
                int: -42,
                int8: -8,
                int16: -16,
                int32: -32,
                int64: -64,
                uint: 42,
                uint8: 8,
                uint16: 16,
                uint32: 32,
                uint64: 64,
                float: 3.14,
                double: 2.718281828
            )
        ]

        let encoder = CSVEncoder()
        let csv = try encoder.encodeToString(original)

        let decoder = CSVDecoder()
        let decoded = try decoder.decode([AllNumericTypes].self, from: csv)

        #expect(original == decoded)
    }

    @Test("CRLF line endings")
    func crlfLineEndings() throws {
        let records = [
            SimpleRecord(name: "A", age: 1, score: 1.0),
            SimpleRecord(name: "B", age: 2, score: 2.0)
        ]

        let config = CSVEncoder.Configuration(lineEnding: .crlf)
        let encoder = CSVEncoder(configuration: config)
        let csv = try encoder.encodeToString(records)

        #expect(csv.contains("\r\n"))
        #expect(!csv.contains("\n") || csv.components(separatedBy: "\r\n").count > 1)
    }
}
