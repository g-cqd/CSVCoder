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

    // MARK: - Flexible Date Decoding Tests

    @Test("Decode dates with flexible strategy - ISO format")
    func decodeDatesFlexibleISO() throws {
        let csv = """
        event,date
        Meeting,2024-12-25
        """

        let config = CSVDecoder.Configuration(dateDecodingStrategy: .flexible)
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([DateRecord].self, from: csv)

        #expect(records.count == 1)
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: records[0].date)
        #expect(components.year == 2024)
        #expect(components.month == 12)
        #expect(components.day == 25)
    }

    @Test("Decode dates with flexible strategy - European format")
    func decodeDatesFlexibleEuropean() throws {
        let csv = """
        event,date
        Conference,25/12/2024
        """

        let config = CSVDecoder.Configuration(dateDecodingStrategy: .flexible)
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([DateRecord].self, from: csv)

        #expect(records.count == 1)
    }

    @Test("Decode dates with flexible strategy - multiple formats in same file")
    func decodeDatesFlexibleMixed() throws {
        let csv = """
        event,date
        ISO,2024-12-25
        European,25.12.2024
        USFormat,12/25/2024
        """

        let config = CSVDecoder.Configuration(dateDecodingStrategy: .flexible)
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([DateRecord].self, from: csv)

        #expect(records.count == 3)
    }

    @Test("Decode dates with flexibleWithHint strategy")
    func decodeDatesFlexibleWithHint() throws {
        let csv = """
        event,date
        Meeting,25-Dec-2024
        """

        let config = CSVDecoder.Configuration(
            dateDecodingStrategy: .flexibleWithHint(preferred: "dd-MMM-yyyy")
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([DateRecord].self, from: csv)

        #expect(records.count == 1)
    }

    // MARK: - Flexible Number Decoding Tests

    struct PriceRecord: Codable, Equatable {
        let item: String
        let price: Double
    }

    @Test("Decode numbers with flexible strategy - US format")
    func decodeNumbersFlexibleUS() throws {
        let csv = """
        item,price
        Widget,1234.56
        Gadget,"1,234.56"
        """

        let config = CSVDecoder.Configuration(numberDecodingStrategy: .flexible)
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([PriceRecord].self, from: csv)

        #expect(records.count == 2)
        #expect(records[0].price == 1234.56)
        #expect(records[1].price == 1234.56)
    }

    @Test("Decode numbers with flexible strategy - European format")
    func decodeNumbersFlexibleEuropean() throws {
        let csv = """
        item,price
        Widget,"1.234,56"
        Simple,"45,50"
        """

        let config = CSVDecoder.Configuration(numberDecodingStrategy: .flexible)
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([PriceRecord].self, from: csv)

        #expect(records.count == 2)
        #expect(records[0].price == 1234.56)
        #expect(records[1].price == 45.50)
    }

    @Test("Decode numbers with flexible strategy - currency symbols")
    func decodeNumbersFlexibleCurrency() throws {
        let csv = """
        item,price
        US,$45.00
        EU,45€
        UK,£45.00
        """

        let config = CSVDecoder.Configuration(numberDecodingStrategy: .flexible)
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([PriceRecord].self, from: csv)

        #expect(records.count == 3)
        #expect(records[0].price == 45.0)
        #expect(records[1].price == 45.0)
        #expect(records[2].price == 45.0)
    }

    @Test("Decode Decimal with flexible strategy preserves precision")
    func decodeDecimalFlexible() throws {
        let csv = """
        item,price
        Widget,"1.234,56"
        """

        struct DecimalRecord: Codable {
            let item: String
            let price: Decimal
        }

        let config = CSVDecoder.Configuration(numberDecodingStrategy: .flexible)
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([DecimalRecord].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].price == Decimal(string: "1234.56"))
    }

    // MARK: - Flexible Boolean Decoding Tests

    struct BoolRecord: Codable {
        let name: String
        let active: Bool
    }

    @Test("Decode booleans with flexible strategy - standard values")
    func decodeBoolFlexibleStandard() throws {
        let csv = """
        name,active
        A,true
        B,yes
        C,1
        D,false
        E,no
        F,0
        """

        let config = CSVDecoder.Configuration(boolDecodingStrategy: .flexible)
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([BoolRecord].self, from: csv)

        #expect(records.count == 6)
        #expect(records[0].active == true)
        #expect(records[1].active == true)
        #expect(records[2].active == true)
        #expect(records[3].active == false)
        #expect(records[4].active == false)
        #expect(records[5].active == false)
    }

    @Test("Decode booleans with flexible strategy - international values")
    func decodeBoolFlexibleInternational() throws {
        let csv = """
        name,active
        French,oui
        German,ja
        Spanish,si
        FrenchNo,non
        GermanNo,nein
        """

        let config = CSVDecoder.Configuration(boolDecodingStrategy: .flexible)
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([BoolRecord].self, from: csv)

        #expect(records.count == 5)
        #expect(records[0].active == true)
        #expect(records[1].active == true)
        #expect(records[2].active == true)
        #expect(records[3].active == false)
        #expect(records[4].active == false)
    }

    @Test("Decode booleans with custom strategy")
    func decodeBoolCustom() throws {
        let csv = """
        name,active
        A,enabled
        B,disabled
        """

        let config = CSVDecoder.Configuration(
            boolDecodingStrategy: .custom(
                trueValues: ["enabled", "on"],
                falseValues: ["disabled", "off"]
            )
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([BoolRecord].self, from: csv)

        #expect(records.count == 2)
        #expect(records[0].active == true)
        #expect(records[1].active == false)
    }

    // MARK: - RFC 4180 Edge Case Tests

    struct TextRecord: Codable, Equatable {
        let name: String
        let value: String
    }

    @Test("Handle quoted fields with embedded newlines")
    func handleQuotedFieldsWithNewlines() throws {
        let csv = """
        name,value
        Test,"Line1
        Line2
        Line3"
        """

        let decoder = CSVDecoder()
        let records = try decoder.decode([TextRecord].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].name == "Test")
        #expect(records[0].value == "Line1\nLine2\nLine3")
    }

    @Test("Handle escaped quotes within quoted fields")
    func handleEscapedQuotes() throws {
        let csv = """
        name,value
        Test,"Say ""Hello"" World"
        """

        let decoder = CSVDecoder()
        let records = try decoder.decode([TextRecord].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].value == "Say \"Hello\" World")
    }

    @Test("Handle empty quoted field")
    func handleEmptyQuotedField() throws {
        let csv = """
        name,value
        Test,""
        """

        let decoder = CSVDecoder()
        let records = try decoder.decode([TextRecord].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].value == "")
    }

    @Test("Handle quoted field with only quotes")
    func handleQuotedFieldWithOnlyQuotes() throws {
        let csv = """
        name,value
        Test,"\"\""
        """

        let decoder = CSVDecoder()
        let records = try decoder.decode([TextRecord].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].value == "\"")
    }

    @Test("Handle CRLF line endings")
    func handleCRLFLineEndings() throws {
        let csv = "name,value\r\nAlice,One\r\nBob,Two\r\n"

        let decoder = CSVDecoder()
        let records = try decoder.decode([TextRecord].self, from: csv)

        #expect(records.count == 2)
        #expect(records[0].name == "Alice")
        #expect(records[1].name == "Bob")
    }

    @Test("Handle mixed LF and CRLF line endings")
    func handleMixedLineEndings() throws {
        let csv = "name,value\nAlice,One\r\nBob,Two\n"

        let decoder = CSVDecoder()
        let records = try decoder.decode([TextRecord].self, from: csv)

        #expect(records.count == 2)
        #expect(records[0].name == "Alice")
        #expect(records[1].name == "Bob")
    }

    @Test("Handle quoted field containing CRLF")
    func handleQuotedFieldWithCRLF() throws {
        let csv = "name,value\r\nTest,\"Line1\r\nLine2\"\r\n"

        let decoder = CSVDecoder()
        let records = try decoder.decode([TextRecord].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].value == "Line1\r\nLine2")
    }

    @Test("Throw error for unterminated quoted field")
    func throwErrorForUnterminatedQuote() throws {
        let csv = """
        name,value
        Test,"Unterminated
        """

        let decoder = CSVDecoder()

        #expect(throws: CSVDecodingError.self) {
            _ = try decoder.decode([TextRecord].self, from: csv)
        }
    }

    @Test("Handle quote in middle of unquoted field (lenient)")
    func handleQuoteInMiddleOfField() throws {
        let csv = """
        name,value
        Test,Hello"World
        """

        let decoder = CSVDecoder()
        let records = try decoder.decode([TextRecord].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].value == "Hello\"World")
    }

    @Test("Handle multiple consecutive delimiters (empty fields)")
    func handleConsecutiveDelimiters() throws {
        let csv = """
        a,b,c
        1,,3
        ,2,
        ,,
        """

        struct ThreeFields: Codable {
            let a: String?
            let b: String?
            let c: String?
        }

        let decoder = CSVDecoder()
        let records = try decoder.decode([ThreeFields].self, from: csv)

        #expect(records.count == 3)
        #expect(records[0].a == "1")
        #expect(records[0].b == nil)
        #expect(records[0].c == "3")
        #expect(records[1].a == nil)
        #expect(records[1].b == "2")
        #expect(records[1].c == nil)
        #expect(records[2].a == nil)
        #expect(records[2].b == nil)
        #expect(records[2].c == nil)
    }

    @Test("Handle whitespace preservation in quoted fields")
    func handleWhitespaceInQuotedFields() throws {
        // With trimWhitespace = false, spaces should be preserved
        let csv = """
        name,value
        Test,"  spaces  "
        """

        let config = CSVDecoder.Configuration(trimWhitespace: false)
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([TextRecord].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].value == "  spaces  ")
    }

    @Test("Handle complex quoted field with all special characters")
    func handleComplexQuotedField() throws {
        let csv = """
        name,value
        Complex,"Has, commas, ""quotes"", and
        newlines"
        """

        let decoder = CSVDecoder()
        let records = try decoder.decode([TextRecord].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].value == "Has, commas, \"quotes\", and\nnewlines")
    }

    @Test("Roundtrip with all RFC 4180 special characters")
    func roundtripRFC4180() throws {
        let original = [
            TextRecord(name: "Commas", value: "a,b,c"),
            TextRecord(name: "Quotes", value: "Say \"Hi\""),
            TextRecord(name: "Newline", value: "Line1\nLine2"),
            TextRecord(name: "Mixed", value: "All: \", \n together")
        ]

        let encoder = CSVEncoder()
        let csv = try encoder.encodeToString(original)

        let decoder = CSVDecoder()
        let decoded = try decoder.decode([TextRecord].self, from: csv)

        #expect(original == decoded)
    }

    // MARK: - Streaming Decoder Tests

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

    // MARK: - SIMD Scanner Tests

    @Test("SIMD scanner finds structural positions")
    func simdScannerFindsPositions() throws {
        let csv = "name,age\nAlice,30\nBob,25"
        let data = Data(csv.utf8)

        let positions = data.withUnsafeBytes { buffer -> [SIMDScanner.StructuralPosition] in
            let bytes = buffer.baseAddress!.assumingMemoryBound(to: UInt8.self)
            return SIMDScanner.scanStructural(buffer: bytes, count: data.count)
        }

        // Should find: comma, LF, comma, LF, comma
        let commas = positions.filter { $0.isComma }
        let newlines = positions.filter { $0.isNewline }

        #expect(commas.count == 3)
        #expect(newlines.count == 2)
    }

    @Test("SIMD scanner finds row boundaries")
    func simdScannerRowBoundaries() throws {
        let csv = "name,value\nAlice,\"Hello\nWorld\"\nBob,Test"
        let data = Data(csv.utf8)

        let boundaries = data.withUnsafeBytes { buffer -> SIMDScanner.RowBoundaries in
            let bytes = buffer.baseAddress!.assumingMemoryBound(to: UInt8.self)
            return SIMDScanner.findRowBoundaries(buffer: bytes, count: data.count)
        }

        // Should find 3 rows: header, Alice (with quoted newline), Bob
        #expect(boundaries.rowStarts.count == 3)
        #expect(boundaries.endsInQuote == false)
    }

    @Test("SIMD scanner handles quoted fields correctly")
    func simdScannerQuotedFields() throws {
        let csv = "a,\"b,c\",d\n1,\"2\n3\",4"
        let data = Data(csv.utf8)

        let boundaries = data.withUnsafeBytes { buffer -> SIMDScanner.RowBoundaries in
            let bytes = buffer.baseAddress!.assumingMemoryBound(to: UInt8.self)
            return SIMDScanner.findRowBoundaries(buffer: bytes, count: data.count)
        }

        // The newline inside quotes should not create a row boundary
        #expect(boundaries.rowStarts.count == 2)
    }

    @Test("SIMD approximate newline count")
    func simdApproxNewlineCount() throws {
        let csv = "a\nb\nc\nd\ne"
        let data = Data(csv.utf8)

        let count = data.withUnsafeBytes { buffer -> Int in
            let bytes = buffer.baseAddress!.assumingMemoryBound(to: UInt8.self)
            return SIMDScanner.countNewlinesApprox(buffer: bytes, count: data.count)
        }

        #expect(count == 4)
    }

    // MARK: - Parallel Decoding Tests

    @Test("Parallel decode from Data")
    func parallelDecodeFromData() async throws {
        var csvLines = ["name,age,score"]
        for i in 0..<100 {
            csvLines.append("Person\(i),\(20 + i % 50),\(Double(i) * 0.5)")
        }
        let csv = csvLines.joined(separator: "\n")
        let data = Data(csv.utf8)

        let decoder = CSVDecoder()
        let config = CSVDecoder.ParallelConfiguration(
            parallelism: 4,
            chunkSize: 256 // Small chunks to test parallel behavior
        )

        let records = try await decoder.decodeParallel([SimpleRecord].self, from: data, parallelConfig: config)

        #expect(records.count == 100)
        #expect(records[0].name == "Person0")
        #expect(records[99].name == "Person99")
    }

    @Test("Parallel decode preserves order")
    func parallelDecodePreservesOrder() async throws {
        var csvLines = ["name,age,score"]
        for i in 0..<50 {
            csvLines.append("Person\(i),\(i),\(Double(i))")
        }
        let csv = csvLines.joined(separator: "\n")
        let data = Data(csv.utf8)

        let decoder = CSVDecoder()
        let config = CSVDecoder.ParallelConfiguration(
            parallelism: 4,
            chunkSize: 128,
            preserveOrder: true
        )

        let records = try await decoder.decodeParallel([SimpleRecord].self, from: data, parallelConfig: config)

        #expect(records.count == 50)
        for (i, record) in records.enumerated() {
            #expect(record.name == "Person\(i)", "Order mismatch at index \(i)")
            #expect(record.age == i)
        }
    }

    @Test("Parallel decode unordered")
    func parallelDecodeUnordered() async throws {
        var csvLines = ["name,age,score"]
        for i in 0..<50 {
            csvLines.append("Person\(i),\(i),\(Double(i))")
        }
        let csv = csvLines.joined(separator: "\n")
        let data = Data(csv.utf8)

        let decoder = CSVDecoder()
        let config = CSVDecoder.ParallelConfiguration(
            parallelism: 4,
            chunkSize: 128,
            preserveOrder: false
        )

        let records = try await decoder.decodeParallel([SimpleRecord].self, from: data, parallelConfig: config)

        // All records present, but possibly unordered
        #expect(records.count == 50)

        let names = Set(records.map { $0.name })
        for i in 0..<50 {
            #expect(names.contains("Person\(i)"))
        }
    }

    @Test("Parallel batched decode yields batches")
    func parallelBatchedDecode() async throws {
        var csvLines = ["name,age,score"]
        for i in 0..<100 {
            csvLines.append("Person\(i),\(i),\(Double(i))")
        }
        let csv = csvLines.joined(separator: "\n")

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".csv")
        try Data(csv.utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let decoder = CSVDecoder()
        let config = CSVDecoder.ParallelConfiguration(chunkSize: 256)

        var batchCount = 0
        var totalRecords = 0
        for try await batch in decoder.decodeParallelBatched(SimpleRecord.self, from: tempURL, parallelConfig: config) {
            batchCount += 1
            totalRecords += batch.count
        }

        #expect(batchCount >= 1)
        #expect(totalRecords == 100)
    }

    // MARK: - Backpressure Tests

    @Test("Decode with memory configuration")
    func decodeWithMemoryConfig() async throws {
        var csvLines = ["name,age,score"]
        for i in 0..<50 {
            csvLines.append("Person\(i),\(i),\(Double(i))")
        }
        let csv = csvLines.joined(separator: "\n")

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".csv")
        try Data(csv.utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let decoder = CSVDecoder()
        // Use reasonable memory budget that won't trigger early backpressure
        let memoryConfig = CSVDecoder.MemoryLimitConfiguration(
            memoryBudget: 1024 * 1024, // 1MB
            estimatedRowSize: 256,
            batchSize: 25
        )

        var records: [SimpleRecord] = []
        for try await record in decoder.decodeWithBackpressure(SimpleRecord.self, from: tempURL, memoryConfig: memoryConfig) {
            records.append(record)
        }

        #expect(records.count == 50)
    }

    @Test("Batched decode with backpressure")
    func batchedDecodeWithBackpressure() async throws {
        var csvLines = ["name,age,score"]
        for i in 0..<100 {
            csvLines.append("Person\(i),\(i),\(Double(i))")
        }
        let csv = csvLines.joined(separator: "\n")

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".csv")
        try Data(csv.utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let decoder = CSVDecoder()
        let memoryConfig = CSVDecoder.MemoryLimitConfiguration(batchSize: 25)

        var batches: [[SimpleRecord]] = []
        for try await batch in decoder.decodeBatchedWithBackpressure(SimpleRecord.self, from: tempURL, memoryConfig: memoryConfig) {
            batches.append(batch)
        }

        #expect(batches.count == 4) // 100 records / 25 per batch
        #expect(batches.flatMap { $0 }.count == 100)
    }

    @Test("Decode with progress reporting")
    func decodeWithProgress() async throws {
        var csvLines = ["name,age,score"]
        for i in 0..<100 {
            csvLines.append("Person\(i),\(i),\(Double(i))")
        }
        let csv = csvLines.joined(separator: "\n")

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".csv")
        try Data(csv.utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let decoder = CSVDecoder()

        // Track progress with actor for thread safety
        actor ProgressCounter {
            var count = 0
            func increment() { count += 1 }
            func getCount() -> Int { count }
        }

        let counter = ProgressCounter()
        var records: [SimpleRecord] = []

        for try await record in decoder.decodeWithProgress(
            SimpleRecord.self,
            from: tempURL,
            progressHandler: { _ in
                Task { await counter.increment() }
            }
        ) {
            records.append(record)
        }

        #expect(records.count == 100)

        // Small delay to allow async progress handlers to complete
        try await Task.sleep(for: .milliseconds(50))

        // Verify progress handler was called at least once
        let callCount = await counter.getCount()
        #expect(callCount >= 1, "Progress handler should be called at least once")
    }

    @Test("Memory limit configuration defaults")
    func memoryLimitConfigDefaults() {
        let config = CSVDecoder.MemoryLimitConfiguration()

        #expect(config.memoryBudget == 50 * 1024 * 1024) // 50MB
        #expect(config.batchSize == 1000)
        #expect(config.highWaterMark == 0.8)
        #expect(config.lowWaterMark == 0.4)
        #expect(config.maxBufferedRows > 0)
    }

    @Test("Parallel configuration defaults")
    func parallelConfigDefaults() {
        let config = CSVDecoder.ParallelConfiguration()

        #expect(config.parallelism == ProcessInfo.processInfo.activeProcessorCount)
        #expect(config.chunkSize == 1024 * 1024) // 1MB
        #expect(config.preserveOrder == true)
    }

    // MARK: - Key Decoding Strategy Tests

    struct CamelCaseRecord: Codable, Equatable {
        let firstName: String
        let lastName: String
        let emailAddress: String
    }

    @Test("Decode with snake_case to camelCase conversion")
    func decodeSnakeCaseToCamelCase() throws {
        let csv = """
        first_name,last_name,email_address
        John,Doe,john@example.com
        Jane,Smith,jane@example.com
        """

        let config = CSVDecoder.Configuration(
            keyDecodingStrategy: .convertFromSnakeCase
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([CamelCaseRecord].self, from: csv)

        #expect(records.count == 2)
        #expect(records[0] == CamelCaseRecord(firstName: "John", lastName: "Doe", emailAddress: "john@example.com"))
        #expect(records[1] == CamelCaseRecord(firstName: "Jane", lastName: "Smith", emailAddress: "jane@example.com"))
    }

    @Test("Decode with kebab-case to camelCase conversion")
    func decodeKebabCaseToCamelCase() throws {
        let csv = """
        first-name,last-name,email-address
        Alice,Johnson,alice@example.com
        """

        let config = CSVDecoder.Configuration(
            keyDecodingStrategy: .convertFromKebabCase
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([CamelCaseRecord].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].firstName == "Alice")
        #expect(records[0].lastName == "Johnson")
    }

    @Test("Decode with SCREAMING_SNAKE_CASE to camelCase conversion")
    func decodeScreamingSnakeCaseToCamelCase() throws {
        let csv = """
        FIRST_NAME,LAST_NAME,EMAIL_ADDRESS
        Bob,Wilson,bob@example.com
        """

        let config = CSVDecoder.Configuration(
            keyDecodingStrategy: .convertFromScreamingSnakeCase
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([CamelCaseRecord].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].firstName == "Bob")
    }

    @Test("Decode with PascalCase to camelCase conversion")
    func decodePascalCaseToCamelCase() throws {
        let csv = """
        FirstName,LastName,EmailAddress
        Carol,Brown,carol@example.com
        """

        let config = CSVDecoder.Configuration(
            keyDecodingStrategy: .convertFromPascalCase
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([CamelCaseRecord].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].firstName == "Carol")
    }

    @Test("Decode with custom key transformation")
    func decodeWithCustomKeyTransformation() throws {
        let csv = """
        fn,ln,email
        David,Lee,david@example.com
        """

        let config = CSVDecoder.Configuration(
            keyDecodingStrategy: .custom { key in
                switch key {
                case "fn": return "firstName"
                case "ln": return "lastName"
                default: return key + "Address"
                }
            }
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([CamelCaseRecord].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].firstName == "David")
        #expect(records[0].lastName == "Lee")
        #expect(records[0].emailAddress == "david@example.com")
    }

    // MARK: - Column Mapping Tests

    @Test("Decode with explicit column mapping")
    func decodeWithColumnMapping() throws {
        let csv = """
        First Name,Last Name,E-mail
        Emily,Davis,emily@example.com
        """

        let config = CSVDecoder.Configuration(
            columnMapping: [
                "First Name": "firstName",
                "Last Name": "lastName",
                "E-mail": "emailAddress"
            ]
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([CamelCaseRecord].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].firstName == "Emily")
        #expect(records[0].lastName == "Davis")
        #expect(records[0].emailAddress == "emily@example.com")
    }

    @Test("Column mapping takes precedence over key strategy")
    func columnMappingTakesPrecedence() throws {
        let csv = """
        first_name,surname,email_address
        Frank,Miller,frank@example.com
        """

        let config = CSVDecoder.Configuration(
            keyDecodingStrategy: .convertFromSnakeCase,
            columnMapping: [
                "surname": "lastName"  // Override snake_case conversion for this column
            ]
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([CamelCaseRecord].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].firstName == "Frank")
        #expect(records[0].lastName == "Miller")
    }

    // MARK: - Error Location Tests

    @Test("Error includes row and column location")
    func errorIncludesLocation() throws {
        let csv = """
        name,age,score
        Alice,30,95.5
        Bob,invalid,88.0
        Carol,40,77.5
        """

        let decoder = CSVDecoder()

        do {
            _ = try decoder.decode([SimpleRecord].self, from: csv)
            Issue.record("Expected error to be thrown")
        } catch let error as CSVDecodingError {
            let location = error.location
            #expect(location?.row == 3)  // Row 3 (1-based, after header)
            #expect(location?.column == "age")

            let description = error.errorDescription ?? ""
            #expect(description.contains("row 3"))
            #expect(description.contains("age"))
        }
    }

    @Test("Error includes key not found location")
    func keyNotFoundErrorIncludesLocation() throws {
        struct StrictRecord: Codable {
            let name: String
            let requiredField: String
        }

        let csv = """
        name,otherField
        Alice,value
        """

        let decoder = CSVDecoder()

        do {
            _ = try decoder.decode([StrictRecord].self, from: csv)
            Issue.record("Expected error to be thrown")
        } catch let error as CSVDecodingError {
            let location = error.location
            #expect(location?.row == 2)
            #expect(location?.column == "requiredField")
        }
    }

    @Test("CSVLocation description formats correctly")
    func csvLocationDescription() {
        let location1 = CSVLocation(row: 5, column: "name", codingPath: [])
        #expect(location1.description == "row 5, column 'name'")

        let location2 = CSVLocation(row: 10, column: nil, codingPath: [])
        #expect(location2.description == "row 10")

        let location3 = CSVLocation(row: nil, column: "age", codingPath: [])
        #expect(location3.description == "column 'age'")

        let location4 = CSVLocation()
        #expect(location4.description == "unknown location")
    }

    // MARK: - Index-Based Decoding Tests

    @Test("Decode headerless CSV with index mapping")
    func decodeHeaderlessWithIndexMapping() throws {
        let csv = """
        Alice,30,95.5
        Bob,25,88.0
        Carol,35,92.0
        """

        let config = CSVDecoder.Configuration(
            hasHeaders: false,
            indexMapping: [0: "name", 1: "age", 2: "score"]
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([SimpleRecord].self, from: csv)

        #expect(records.count == 3)
        #expect(records[0] == SimpleRecord(name: "Alice", age: 30, score: 95.5))
        #expect(records[1] == SimpleRecord(name: "Bob", age: 25, score: 88.0))
        #expect(records[2] == SimpleRecord(name: "Carol", age: 35, score: 92.0))
    }

    @Test("Index mapping with sparse indices")
    func indexMappingWithSparseIndices() throws {
        // CSV with extra columns we want to skip
        let csv = """
        ignore,Alice,skip,30,extra,95.5
        ignore,Bob,skip,25,extra,88.0
        """

        let config = CSVDecoder.Configuration(
            hasHeaders: false,
            indexMapping: [1: "name", 3: "age", 5: "score"]
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([SimpleRecord].self, from: csv)

        #expect(records.count == 2)
        #expect(records[0].name == "Alice")
        #expect(records[0].age == 30)
        #expect(records[0].score == 95.5)
    }

    @Test("Index mapping overrides header names")
    func indexMappingOverridesHeaders() throws {
        // CSV has headers but we want to use different property names
        let csv = """
        col1,col2,col3
        David,40,77.5
        """

        let config = CSVDecoder.Configuration(
            hasHeaders: true,
            indexMapping: [0: "name", 1: "age", 2: "score"]
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([SimpleRecord].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].name == "David")
        #expect(records[0].age == 40)
    }

    @Test("Index mapping with partial coverage")
    func indexMappingPartialCoverage() throws {
        struct PartialRecord: Codable, Equatable {
            let first: String
            let third: String
        }

        let csv = """
        a,b,c
        value1,value2,value3
        """

        let config = CSVDecoder.Configuration(
            hasHeaders: false,
            indexMapping: [0: "first", 2: "third"]
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([PartialRecord].self, from: csv)

        #expect(records.count == 2) // Header row is treated as data
        #expect(records[0].first == "a")
        #expect(records[0].third == "c")
    }

    // MARK: - CSVIndexedDecodable Tests

    /// Record using CSVIndexedDecodable for automatic column ordering
    struct IndexedRecord: CSVIndexedDecodable, Equatable {
        let name: String
        let age: Int
        let score: Double

        enum CodingKeys: String, CodingKey, CaseIterable {
            case name, age, score
        }

        typealias CSVCodingKeys = CodingKeys
    }

    @Test("Decode headerless CSV with CSVIndexedDecodable")
    func decodeHeaderlessWithCSVIndexedDecodable() throws {
        let csv = """
        Alice,30,95.5
        Bob,25,88.0
        Carol,35,92.0
        """

        // No indexMapping needed - uses CodingKeys order
        let config = CSVDecoder.Configuration(hasHeaders: false)
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([IndexedRecord].self, from: csv)

        #expect(records.count == 3)
        #expect(records[0] == IndexedRecord(name: "Alice", age: 30, score: 95.5))
        #expect(records[1] == IndexedRecord(name: "Bob", age: 25, score: 88.0))
        #expect(records[2] == IndexedRecord(name: "Carol", age: 35, score: 92.0))
    }

    @Test("CSVIndexedDecodable with headers still works")
    func csvIndexedDecodableWithHeaders() throws {
        let csv = """
        name,age,score
        Alice,30,95.5
        """

        let decoder = CSVDecoder()
        let records = try decoder.decode([IndexedRecord].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].name == "Alice")
    }

    @Test("CSVIndexedDecodable column order is correct")
    func csvIndexedDecodableColumnOrder() {
        let order = IndexedRecord.csvColumnOrder
        #expect(order == ["name", "age", "score"])
    }

    @Test("Explicit indexMapping overrides CSVIndexedDecodable")
    func explicitIndexMappingOverridesCSVIndexed() throws {
        let csv = """
        95.5,30,Alice
        """

        // Explicit indexMapping should take precedence
        let config = CSVDecoder.Configuration(
            hasHeaders: false,
            indexMapping: [2: "name", 1: "age", 0: "score"]
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([IndexedRecord].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].name == "Alice")
        #expect(records[0].age == 30)
        #expect(records[0].score == 95.5)
    }

    /// Record with different CodingKeys order than property declaration
    struct ReorderedRecord: CSVIndexedDecodable, Equatable {
        let first: String
        let second: Int
        let third: Double

        enum CodingKeys: String, CodingKey, CaseIterable {
            case third, first, second  // Different order than properties
        }

        typealias CSVCodingKeys = CodingKeys
    }

    @Test("CSVIndexedDecodable respects CodingKeys case order")
    func csvIndexedDecodableRespectsOrder() throws {
        // CSV columns match CodingKeys order: third, first, second
        let csv = """
        99.9,hello,42
        """

        let config = CSVDecoder.Configuration(hasHeaders: false)
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([ReorderedRecord].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].third == 99.9)
        #expect(records[0].first == "hello")
        #expect(records[0].second == 42)
    }

    // MARK: - Phase 6.2: Type Inference Tests

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

    // MARK: - Phase 6.3: Error Suggestion Tests

    @Test("Error suggests similar key for typo")
    func errorSuggestsSimilarKey() throws {
        let csv = """
        naame,age,score
        Alice,30,95.5
        """

        let decoder = CSVDecoder()
        do {
            _ = try decoder.decode([SimpleRecord].self, from: csv)
            Issue.record("Should have thrown an error")
        } catch let error as CSVDecodingError {
            let description = error.errorDescription ?? ""
            // Should suggest 'naame' for 'name'
            #expect(description.contains("Did you mean"))
        }
    }

    @Test("Error lists available columns for unknown key")
    func errorListsAvailableColumns() throws {
        struct TwoFields: Codable {
            let xyz: Int
            let abc: Int
        }

        let csv = """
        foo,bar
        1,2
        """

        let decoder = CSVDecoder()
        do {
            _ = try decoder.decode([TwoFields].self, from: csv)
            Issue.record("Should have thrown an error")
        } catch let error as CSVDecodingError {
            let description = error.errorDescription ?? ""
            // Should list available columns when no close match exists
            #expect(description.contains("Available columns") || description.contains("foo") || description.contains("bar"))
        }
    }

    @Test("Error suggests flexible number strategy for currency")
    func errorSuggestsNumberStrategy() throws {
        struct PriceRecord: Codable {
            let price: Double
        }

        let csv = """
        price
        $1,234.56
        """

        let decoder = CSVDecoder()
        do {
            _ = try decoder.decode([PriceRecord].self, from: csv)
            Issue.record("Should have thrown an error")
        } catch let error as CSVDecodingError {
            let suggestion = error.suggestion ?? ""
            #expect(suggestion.contains("numberDecodingStrategy") || suggestion.contains("currency"))
        }
    }

    @Test("Error suggests date strategy for date-like value")
    func errorSuggestsDateStrategy() throws {
        struct EventRecord: Codable {
            let date: Date
        }

        let csv = """
        date
        2024-12-25
        """

        // Default strategy is deferredToDate which will fail
        let decoder = CSVDecoder()
        do {
            _ = try decoder.decode([EventRecord].self, from: csv)
            Issue.record("Should have thrown an error")
        } catch let error as CSVDecodingError {
            // The error message itself contains strategy advice
            let description = error.errorDescription ?? ""
            #expect(description.contains("date strategy") || description.contains("Date"))
        }
    }

    @Test("Error suggestion for case mismatch")
    func errorSuggestionForCaseMismatch() throws {
        struct CaseSensitive: Codable {
            let Name: String  // uppercase N
        }

        let csv = """
        name
        Alice
        """

        let decoder = CSVDecoder()
        do {
            _ = try decoder.decode([CaseSensitive].self, from: csv)
            Issue.record("Should have thrown an error")
        } catch let error as CSVDecodingError {
            let description = error.errorDescription ?? ""
            #expect(description.contains("case differs") || description.contains("Did you mean"))
        }
    }

    @Test("CSVLocation equality ignores availableKeys")
    func csvLocationEqualityIgnoresAvailableKeys() {
        let loc1 = CSVLocation(row: 1, column: "name", availableKeys: ["a", "b"])
        let loc2 = CSVLocation(row: 1, column: "name", availableKeys: ["c", "d"])
        let loc3 = CSVLocation(row: 1, column: "name", availableKeys: nil)

        #expect(loc1 == loc2)
        #expect(loc2 == loc3)
    }

    // MARK: - Strict Mode Tests

    @Test("Strict mode rejects quotes in unquoted fields")
    func strictModeRejectsQuotesInUnquoted() throws {
        let csv = """
        name,value
        Test,Hello"World
        """

        let config = CSVDecoder.Configuration(parsingMode: .strict)
        let decoder = CSVDecoder(configuration: config)

        #expect(throws: CSVDecodingError.self) {
            _ = try decoder.decode([TextRecord].self, from: csv)
        }
    }

    @Test("Strict mode validates field count")
    func strictModeValidatesFieldCount() throws {
        let csv = """
        name,value
        A,B
        X,Y,Z
        """

        let config = CSVDecoder.Configuration(
            parsingMode: .strict,
            expectedFieldCount: 2
        )
        let decoder = CSVDecoder(configuration: config)

        #expect(throws: CSVDecodingError.self) {
            _ = try decoder.decode([TextRecord].self, from: csv)
        }
    }

    @Test("Lenient mode allows quotes in unquoted fields")
    func lenientModeAllowsQuotesInUnquoted() throws {
        let csv = """
        name,value
        Test,Hello"World
        """

        let config = CSVDecoder.Configuration(parsingMode: .lenient)
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([TextRecord].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].value == "Hello\"World")
    }

    // MARK: - NilDecodingStrategy Tests

    @Test("Nil decoding with empty string strategy")
    func nilDecodingEmptyString() throws {
        struct OptionalRecord: Codable {
            let name: String
            let value: String?
        }

        let csv = """
        name,value
        A,present
        B,
        """

        let config = CSVDecoder.Configuration(nilDecodingStrategy: .emptyString)
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([OptionalRecord].self, from: csv)

        #expect(records[0].value == "present")
        #expect(records[1].value == nil)
    }

    @Test("Nil decoding with null literal strategy")
    func nilDecodingNullLiteral() throws {
        struct OptionalRecord: Codable {
            let name: String
            let value: String?
        }

        let csv = """
        name,value
        A,present
        B,null
        C,NULL
        """

        let config = CSVDecoder.Configuration(nilDecodingStrategy: .nullLiteral)
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([OptionalRecord].self, from: csv)

        #expect(records[0].value == "present")
        #expect(records[1].value == nil)
        #expect(records[2].value == nil)
    }

    @Test("Nil decoding with custom values")
    func nilDecodingCustom() throws {
        struct OptionalRecord: Codable {
            let name: String
            let value: String?
        }

        let csv = """
        name,value
        A,present
        B,N/A
        C,-
        """

        let config = CSVDecoder.Configuration(
            nilDecodingStrategy: .custom(["N/A", "-", "n/a"])
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([OptionalRecord].self, from: csv)

        #expect(records[0].value == "present")
        #expect(records[1].value == nil)
        #expect(records[2].value == nil)
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
            expectedFieldCount: 2
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
