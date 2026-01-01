//
//  CSVDecoderStreamingTests.swift
//  CSVCoder
//
//  Tests for streaming and async decoding.
//

import Foundation
import Testing

@testable import CSVCoder

@Suite("CSVDecoder Streaming Tests")
struct CSVDecoderStreamingTests {
    struct SimpleRecord: Codable, Equatable {
        let name: String
        let age: Int
        let score: Double
    }

    struct TextRecord: Codable, Equatable {
        let name: String
        let value: String
    }

    struct NameAge: Codable, Equatable {
        let name: String
        let age: Int
    }

    @Test("Stream decode simple records from Data")
    func streamDecodeFromData() async throws {
        let csv = """
            name,age,score
            Alice,30,95.5
            Bob,25,88.0
            Charlie,35,72.0
            """

        let data = Data(csv.utf8)
        let decoder = CSVDecoder()

        var records: [SimpleRecord] = []
        for try await record in decoder.decode(SimpleRecord.self, from: data) {
            records.append(record)
        }

        #expect(records.count == 3)
        #expect(records[0] == SimpleRecord(name: "Alice", age: 30, score: 95.5))
        #expect(records[1] == SimpleRecord(name: "Bob", age: 25, score: 88.0))
        #expect(records[2] == SimpleRecord(name: "Charlie", age: 35, score: 72.0))
    }

    @Test("Stream decode with UTF-8 BOM")
    func streamDecodeWithBOM() async throws {
        // UTF-8 BOM: EF BB BF
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data("name,value\nTest,Value".utf8))

        let decoder = CSVDecoder()

        var records: [TextRecord] = []
        for try await record in decoder.decode(TextRecord.self, from: data) {
            records.append(record)
        }

        #expect(records.count == 1)
        #expect(records[0].name == "Test")
        #expect(records[0].value == "Value")
    }

    @Test("Stream decode matches sync decode")
    func streamDecodeMatchesSync() async throws {
        // Build CSV with embedded quotes manually to avoid multiline string issues
        let csv = "name,value\nCommas,\"a,b,c\"\nQuotes,\"Say \"\"Hi\"\"\"\nNewline,\"Line1\nLine2\""

        let data = Data(csv.utf8)
        let decoder = CSVDecoder()

        // Sync decode
        let syncRecords = try decoder.decode([TextRecord].self, from: csv)

        // Stream decode
        var streamRecords: [TextRecord] = []
        for try await record in decoder.decode(TextRecord.self, from: data) {
            streamRecords.append(record)
        }

        #expect(streamRecords.count == syncRecords.count)
        for (i, record) in streamRecords.enumerated() {
            #expect(record == syncRecords[i])
        }
    }

    @Test("Stream decode with CRLF line endings")
    func streamDecodeWithCRLF() async throws {
        let csv = "name,value\r\nAlice,One\r\nBob,Two\r\n"
        let data = Data(csv.utf8)

        let decoder = CSVDecoder()

        var records: [TextRecord] = []
        for try await record in decoder.decode(TextRecord.self, from: data) {
            records.append(record)
        }

        #expect(records.count == 2)
        #expect(records[0].name == "Alice")
        #expect(records[1].name == "Bob")
    }

    @Test("Stream decode with quoted CRLF in field")
    func streamDecodeQuotedCRLF() async throws {
        let csv = "name,value\r\nTest,\"Line1\r\nLine2\"\r\n"
        let data = Data(csv.utf8)

        let decoder = CSVDecoder()

        var records: [TextRecord] = []
        for try await record in decoder.decode(TextRecord.self, from: data) {
            records.append(record)
        }

        #expect(records.count == 1)
        #expect(records[0].value == "Line1\r\nLine2")
    }

    @Test("Stream decode throws on unterminated quote")
    func streamDecodeUnterminatedQuote() async throws {
        let csv = "name,value\nTest,\"Unterminated"
        let data = Data(csv.utf8)

        let decoder = CSVDecoder()

        var caughtError = false
        do {
            for try await _ in decoder.decode(TextRecord.self, from: data) {
                // consume
            }
        } catch {
            caughtError = true
            #expect(error is CSVDecodingError)
        }
        #expect(caughtError)
    }

    @Test("Stream decode with semicolon delimiter")
    func streamDecodeWithDelimiter() async throws {
        let csv = "name;age\nCharlie;35\nDiana;28"
        let data = Data(csv.utf8)

        let config = CSVDecoder.Configuration(delimiter: ";")
        let decoder = CSVDecoder(configuration: config)

        var records: [NameAge] = []
        for try await record in decoder.decode(NameAge.self, from: data) {
            records.append(record)
        }

        #expect(records.count == 2)
        #expect(records[0].name == "Charlie")
        #expect(records[0].age == 35)
    }

    @Test("Stream decode without headers")
    func streamDecodeNoHeaders() async throws {
        let csv = "Alice,30\nBob,25"
        let data = Data(csv.utf8)

        struct IndexedRecord: Codable {
            let column0: String
            let column1: Int
        }

        let config = CSVDecoder.Configuration(hasHeaders: false)
        let decoder = CSVDecoder(configuration: config)

        var records: [IndexedRecord] = []
        for try await record in decoder.decode(IndexedRecord.self, from: data) {
            records.append(record)
        }

        #expect(records.count == 2)
        #expect(records[0].column0 == "Alice")
        #expect(records[0].column1 == 30)
    }

    @Test("Async collect decode from Data")
    func asyncCollectDecode() async throws {
        let csv = """
            name,age,score
            Alice,30,95.5
            Bob,25,88.0
            """

        let data = Data(csv.utf8)

        // Write to temp file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".csv")
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let decoder = CSVDecoder()
        let records = try await decoder.decode([SimpleRecord].self, from: tempURL)

        #expect(records.count == 2)
        #expect(records[0] == SimpleRecord(name: "Alice", age: 30, score: 95.5))
    }

    // MARK: - Streaming Strict Mode Tests

    @Test("Streaming strict mode rejects quotes in unquoted fields")
    func streamingStrictModeRejectsQuotes() async throws {
        let csv = """
            name,value
            Test,Hello"World
            """
        let data = Data(csv.utf8)

        let config = CSVDecoder.Configuration(parsingMode: .strict)
        let decoder = CSVDecoder(configuration: config)

        var caughtError: Error?
        do {
            for try await _ in decoder.decode(TextRecord.self, from: data) {
                // consume
            }
        } catch {
            caughtError = error
        }

        #expect(caughtError != nil)
        #expect(caughtError is CSVDecodingError)
    }

    @Test("Streaming strict mode validates field count")
    func streamingStrictModeValidatesFieldCount() async throws {
        let csv = """
            name,value
            A,B
            X,Y,Z
            """
        let data = Data(csv.utf8)

        let config = CSVDecoder.Configuration(
            parsingMode: .strict,
            expectedFieldCount: 2,
        )
        let decoder = CSVDecoder(configuration: config)

        var caughtError: Error?
        do {
            for try await _ in decoder.decode(TextRecord.self, from: data) {
                // consume
            }
        } catch {
            caughtError = error
        }

        #expect(caughtError != nil)
        #expect(caughtError is CSVDecodingError)
    }
}
