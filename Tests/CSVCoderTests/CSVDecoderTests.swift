//
//  CSVDecoderTests.swift
//  CSVCoder
//
//  Tests for CSVDecoder.
//

import Testing
@testable import CSVCoder
import Foundation

@Suite("CSVDecoder Tests")
struct CSVDecoderTests {

    struct SimpleRecord: Codable, Equatable {
        let name: String
        let age: Int
        let score: Double
    }

    @Test("Decode simple records")
    func decodeSimpleRecords() throws {
        let csv = """
        name;age;score
        Alice;30;95.5
        Bob;25;88.0
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

    @Test("Decode with comma delimiter")
    func decodeWithCommaDelimiter() throws {
        let csv = """
        name,age
        Charlie,35
        """

        let config = CSVDecoder.Configuration(delimiter: ",")
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
        event;date
        Meeting;25/12/2024
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
        name;description
        Test;"Value;with;semicolons"
        """

        let decoder = CSVDecoder()

        struct QuotedRecord: Codable {
            let name: String
            let description: String
        }

        let records = try decoder.decode([QuotedRecord].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].description == "Value;with;semicolons")
    }

    @Test("Handle empty values")
    func handleEmptyValues() throws {
        let csv = """
        name;value
        Test;
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
        id;value
        1;42
        2;255
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
}
