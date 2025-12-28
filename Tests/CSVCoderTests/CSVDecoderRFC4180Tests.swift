//
//  CSVDecoderRFC4180Tests.swift
//  CSVCoder
//
//  Tests for RFC 4180 compliance: quoted fields, line endings, strict/lenient mode, nil decoding.
//

import Testing
@testable import CSVCoder
import Foundation

@Suite("CSVDecoder RFC 4180 Tests")
struct CSVDecoderRFC4180Tests {

    struct TextRecord: Codable, Equatable {
        let name: String
        let value: String
    }

    // MARK: - Quoted Field Tests

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

    // MARK: - Line Ending Tests

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

    // MARK: - Error Cases

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

    // MARK: - Edge Cases

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

    @Test("TrimWhitespace applies to all field types including numeric")
    func trimWhitespaceAppliesToNumericFields() throws {
        struct Vehicle: Decodable, Equatable {
            let make: String
            let year: Int
            let price: Double
        }

        // CSV with whitespace around string and numeric fields
        let csv = """
        make,year,price
         Toyota , 2024 , 45000.50
        """

        // Default: trimWhitespace = true should trim all fields
        let decoder = CSVDecoder()
        let vehicles = try decoder.decode([Vehicle].self, from: csv)

        #expect(vehicles.count == 1)
        #expect(vehicles[0].make == "Toyota")
        #expect(vehicles[0].year == 2024)
        #expect(vehicles[0].price == 45000.50)
    }

    @Test("TrimWhitespace false preserves whitespace in all fields")
    func trimWhitespaceFalsePreservesAllWhitespace() throws {
        struct Record: Decodable, Equatable {
            let name: String
            let value: String
        }

        // Use explicit quotes to preserve trailing whitespace
        let csv = """
        name,value
        " padded "," text "
        """

        let config = CSVDecoder.Configuration(trimWhitespace: false)
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([Record].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].name == " padded ")
        #expect(records[0].value == " text ")
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

    // MARK: - Safe Parser Wrapper Tests

    @Test("Safe parser wrapper prevents escaping")
    func safeParserWrapper() throws {
        let csv = """
        name,age
        Alice,30
        Bob,25
        """
        let data = Data(csv.utf8)

        // Count rows safely
        let rowCount = try CSVParser.parse(data: data) { parser in
            parser.reduce(0) { count, _ in count + 1 }
        }
        #expect(rowCount == 3) // header + 2 rows

        // Extract values safely
        let names = try CSVParser.parse(data: data) { parser -> [String] in
            var results: [String] = []
            for row in parser {
                if let name = row.string(at: 0) {
                    results.append(name)
                }
            }
            return results
        }
        #expect(names == ["name", "Alice", "Bob"])
    }
}
