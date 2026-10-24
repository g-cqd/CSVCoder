//
//  CSVParserQuoteInUnquotedFieldTests.swift
//  CSVCoder
//
//  Strict mode rejects a quote inside an unquoted field (RFC 4180). The parser must report it
//  wherever the field sits in the buffer, not only in the last 64 bytes.
//

import Foundation
import Testing

@testable import CSVCoder

@Suite("CSVParser quote in an unquoted field")
struct CSVParserQuoteInUnquotedFieldTests {
    private static func flags(of csv: String) -> [Bool] {
        let bytes = Array(csv.utf8)
        return bytes.withUnsafeBufferPointer { buffer in
            CSVParser(buffer: buffer, delimiter: 0x2C).map(\.hasQuoteInUnquotedField)
        }
    }

    @Test("Every row with a stray quote is flagged, early or late in the buffer", arguments: [1, 3, 20, 200])
    func strayQuoteIsFlaggedInEveryRow(rows: Int) {
        let csv = String(repeating: "ab\"cd,ef\n", count: rows)
        #expect(Self.flags(of: csv) == Array(repeating: true, count: rows))
    }

    @Test("A stray quote after a long unquoted prefix is flagged", arguments: [10, 63, 64, 65, 200])
    func strayQuoteAfterPrefixIsFlagged(prefix: Int) {
        let field = String(repeating: "x", count: prefix) + "\"y"
        let csv = "\(field),b\n\(field),b\n"
        #expect(Self.flags(of: csv) == [true, true])
    }

    @Test("A well-formed row is not flagged, and neither is a quoted field with an escaped quote")
    func wellFormedRowsAreNotFlagged() {
        let csv = String(repeating: "abc,\"d\"\"e\",fgh\n", count: 50)
        #expect(Self.flags(of: csv) == Array(repeating: false, count: 50))
    }
}
