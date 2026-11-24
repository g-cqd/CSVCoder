import Foundation
import Testing

@testable import CSVCoder

/// A delimiter ends a field, so the data that ends on one has an empty field after it (RFC 4180: `a,` is two fields). The parser stopped at
/// the end of the data and dropped it, when there was no line ending to end the row (found 2026-11-24 by a round-trip property in Sunset).
@Suite("The last field after a final delimiter")
struct CSVParserTrailingFieldTests {
    private func rows(_ text: String) -> [[String]] {
        CSVParser.parse(data: Data(text.utf8), delimiter: 0x2C) { parser in
            parser.map { row in (0 ..< row.count).map { row.string(at: $0) ?? "?" } }
        }
    }

    @Test func `the data ends on a delimiter: the last field is empty, whether or not a row came before`() {
        #expect(rows("b ,") == [["b ", ""]])
        #expect(rows("a,b\r\nc,") == [["a", "b"], ["c", ""]])
        #expect(rows("a,b\nc,d,") == [["a", "b"], ["c", "d", ""]])
        #expect(rows("\"q\",") == [["q", ""]])
        #expect(rows(",") == [["", ""]])
        #expect(rows(",,") == [["", "", ""]])
    }

    @Test func `what was right stays right: a row ending on its line ending, on a field, or on nothing`() {
        #expect(rows("b ,\r\n") == [["b ", ""]])
        #expect(rows("a,b") == [["a", "b"]])
        #expect(rows("a,b\r\n") == [["a", "b"]])
        #expect(rows("") == [])
        #expect(rows("\r\n") == [])
        #expect(rows("a\r\n\r\nb") == [["a"], [""], ["b"]] || rows("a\r\n\r\nb") == [["a"], ["b"]])
    }
}
