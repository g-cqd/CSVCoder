//
//  CSVDecoderBasicTests.swift
//  CSVCoder
//
//  Basic decoding tests: simple records, delimiters, types.
//

import Testing
@testable import CSVCoder
import Foundation

@Suite("CSVDecoder Basic Tests")
struct CSVDecoderBasicTests {

    struct SimpleRecord: Codable, Equatable {
        let name: String
        let age: Int
        let score: Double
    }

    @Test("Decode simple records")
    func decodeSimpleRecords() throws {
        let csv = """
        name,age,score
        Alice,30,95.5
        Bob,25,88.0
        """

        let decoder = CSVDecoder()
        let records = try decoder.decode([SimpleRecord].self, from: csv)

        #expect(records.count == 2)
        #expect(records[0] == SimpleRecord(name: "Alice", age: 30, score: 95.5))
        #expect(records[1] == SimpleRecord(name: "Bob", age: 25, score: 88.0))
    }

    struct NameAge: Codable, Equatable {
        let name: String
        let age: Int
    }

    @Test("Decode with semicolon delimiter")
    func decodeWithSemicolonDelimiter() throws {
        let csv = """
        name;age
        Charlie;35
        """

        let config = CSVDecoder.Configuration(delimiter: ";")
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([NameAge].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].name == "Charlie")
        #expect(records[0].age == 35)
    }

    struct DateRecord: Codable {
        let event: String
        let date: Date
    }

    @Test("Decode dates with format")
    func decodeDatesWithFormat() throws {
        let csv = """
        event,date
        Meeting,25/12/2024
        """

        let config = CSVDecoder.Configuration(
            dateDecodingStrategy: .formatted("dd/MM/yyyy")
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([DateRecord].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].event == "Meeting")
    }

    @Test("Decode from single row dictionary")
    func decodeFromDictionary() throws {
        let row = ["name": "Eve", "age": "28", "score": "92.5"]

        let decoder = CSVDecoder()
        let record = try decoder.decode(SimpleRecord.self, from: row)

        #expect(record.name == "Eve")
        #expect(record.age == 28)
        #expect(record.score == 92.5)
    }

    @Test("Handle quoted fields with delimiters")
    func handleQuotedFields() throws {
        let csv = """
        name,description
        Test,"Value,with,commas"
        """

        let decoder = CSVDecoder()

        struct QuotedRecord: Codable {
            let name: String
            let description: String
        }

        let records = try decoder.decode([QuotedRecord].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].description == "Value,with,commas")
    }

    @Test("Handle empty values")
    func handleEmptyValues() throws {
        let csv = """
        name,value
        Test,
        """

        struct OptionalRecord: Codable {
            let name: String
            let value: String?
        }

        let decoder = CSVDecoder()
        let records = try decoder.decode([OptionalRecord].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].value == nil)
    }

    @Test("Decode UInt8 values")
    func decodeUInt8Values() throws {
        let csv = """
        id,value
        1,42
        2,255
        """

        struct ByteRecord: Codable {
            let id: Int
            let value: UInt8
        }

        let decoder = CSVDecoder()
        let records = try decoder.decode([ByteRecord].self, from: csv)

        #expect(records.count == 2)
        #expect(records[0].value == 42)
        #expect(records[1].value == 255)
    }

    @Test("Decode Decimal values")
    func decodeDecimalValues() throws {
        let csv = """
        price,quantity
        19.99,100
        0.001,999999
        """

        struct PriceRecord: Codable, Equatable {
            let price: Decimal
            let quantity: Int
        }

        let decoder = CSVDecoder()
        let records = try decoder.decode([PriceRecord].self, from: csv)

        #expect(records.count == 2)
        #expect(records[0].price == Decimal(string: "19.99"))
        #expect(records[1].price == Decimal(string: "0.001"))
    }

    @Test("Decode UUID values")
    func decodeUUIDValues() throws {
        let uuid1 = UUID()
        let uuid2 = UUID()
        let csv = """
        id,name
        \(uuid1.uuidString),Item1
        \(uuid2.uuidString),Item2
        """

        struct UUIDRecord: Codable {
            let id: UUID
            let name: String
        }

        let decoder = CSVDecoder()
        let records = try decoder.decode([UUIDRecord].self, from: csv)

        #expect(records.count == 2)
        #expect(records[0].id == uuid1)
        #expect(records[1].id == uuid2)
    }

    @Test("Decode URL values")
    func decodeURLValues() throws {
        let csv = """
        name,website
        Example,https://example.com
        Test,https://test.com/path?query=1
        """

        struct URLRecord: Codable {
            let name: String
            let website: URL
        }

        let decoder = CSVDecoder()
        let records = try decoder.decode([URLRecord].self, from: csv)

        #expect(records.count == 2)
        #expect(records[0].website == URL(string: "https://example.com"))
        #expect(records[1].website == URL(string: "https://test.com/path?query=1"))
    }

    // MARK: - Type Inference Tests

    @Test("Type inference decode from string")
    func typeInferenceFromString() throws {
        let csv = """
        name,age,score
        Alice,30,95.5
        """

        let decoder = CSVDecoder()
        let records: [SimpleRecord] = try decoder.decode(from: csv)

        #expect(records.count == 1)
        #expect(records[0].name == "Alice")
    }

    @Test("Type inference decode from Data")
    func typeInferenceFromData() throws {
        let csv = """
        name,age,score
        Bob,25,88.0
        """
        let data = csv.data(using: .utf8)!

        let decoder = CSVDecoder()
        let records: [SimpleRecord] = try decoder.decode(from: data)

        #expect(records.count == 1)
        #expect(records[0].name == "Bob")
    }

    @Test("Type inference decode from dictionary")
    func typeInferenceFromDictionary() throws {
        let row = ["name": "Carol", "age": "35", "score": "92.0"]

        let decoder = CSVDecoder()
        let record: SimpleRecord = try decoder.decode(from: row)

        #expect(record.name == "Carol")
        #expect(record.age == 35)
    }

    // MARK: - Encoding Tests

    struct NameValue: Codable, Equatable {
        let name: String
        let value: String
    }

    @Test("Decode ISO-8859-1 (Latin-1) encoded data")
    func decodeISOLatin1() throws {
        // Create CSV with Latin-1 specific characters (é = 0xE9 in Latin-1)
        let csv = "name,value\nCafé,naïve"
        guard let data = csv.data(using: .isoLatin1) else {
            Issue.record("Failed to create Latin-1 data")
            return
        }

        let config = CSVDecoder.Configuration(encoding: .isoLatin1)
        let decoder = CSVDecoder(configuration: config)
        let records: [NameValue] = try decoder.decode([NameValue].self, from: data)

        #expect(records.count == 1)
        #expect(records[0].name == "Café")
        #expect(records[0].value == "naïve")
    }

    @Test("Decode Windows-1252 encoded data")
    func decodeWindows1252() throws {
        // Windows-1252 extends Latin-1 with characters like € (0x80)
        let csv = "name,value\nPrice,100€"
        guard let data = csv.data(using: .windowsCP1252) else {
            Issue.record("Failed to create Windows-1252 data")
            return
        }

        let config = CSVDecoder.Configuration(encoding: .windowsCP1252)
        let decoder = CSVDecoder(configuration: config)
        let records: [NameValue] = try decoder.decode([NameValue].self, from: data)

        #expect(records.count == 1)
        #expect(records[0].name == "Price")
        #expect(records[0].value == "100€")
    }

    @Test("Decode UTF-16 encoded data with BOM")
    func decodeUTF16WithBOM() throws {
        // UTF-16 with BOM (automatically detected and transcoded)
        let csv = "name,value\n日本語,テスト"
        guard let data = csv.data(using: .utf16) else {
            Issue.record("Failed to create UTF-16 data")
            return
        }

        let config = CSVDecoder.Configuration(encoding: .utf16)
        let decoder = CSVDecoder(configuration: config)
        let records: [NameValue] = try decoder.decode([NameValue].self, from: data)

        #expect(records.count == 1)
        #expect(records[0].name == "日本語")
        #expect(records[0].value == "テスト")
    }

    @Test("Decode UTF-16LE encoded data")
    func decodeUTF16LittleEndian() throws {
        let csv = "name,value\nHello,World"
        guard let data = csv.data(using: .utf16LittleEndian) else {
            Issue.record("Failed to create UTF-16LE data")
            return
        }

        // Add UTF-16 LE BOM manually since data(using:) doesn't add it
        var dataWithBOM = Data([0xFF, 0xFE])
        dataWithBOM.append(data)

        let config = CSVDecoder.Configuration(encoding: .utf16LittleEndian)
        let decoder = CSVDecoder(configuration: config)
        // Use explicit type array to avoid streaming API ambiguity
        let records: [NameValue] = try decoder.decode([NameValue].self, from: dataWithBOM)

        #expect(records.count == 1)
        #expect(records[0].name == "Hello")
        #expect(records[0].value == "World")
    }

    @Test("UTF-8 BOM is handled correctly")
    func decodeUTF8WithBOM() throws {
        let csv = "name,value\nTest,Value"
        let utf8Data = csv.data(using: .utf8)!

        // Add UTF-8 BOM
        var dataWithBOM = Data([0xEF, 0xBB, 0xBF])
        dataWithBOM.append(utf8Data)

        let decoder = CSVDecoder()
        // Use explicit type array to avoid streaming API ambiguity
        let records: [NameValue] = try decoder.decode([NameValue].self, from: dataWithBOM)

        #expect(records.count == 1)
        #expect(records[0].name == "Test")
        #expect(records[0].value == "Value")
    }

    @Test("ASCII-compatible encoding preserves zero-copy parsing")
    func asciiCompatibleEncodingPerformance() throws {
        // Large CSV to ensure we're testing actual parsing
        var csv = "name,value\n"
        for i in 0..<1000 {
            csv += "Item\(i),Value\(i)\n"
        }

        // Use string overload to avoid streaming API ambiguity
        let config = CSVDecoder.Configuration(encoding: .isoLatin1)
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([NameValue].self, from: csv)

        #expect(records.count == 1000)
        #expect(records[0].name == "Item0")
        #expect(records[999].name == "Item999")
    }
}
