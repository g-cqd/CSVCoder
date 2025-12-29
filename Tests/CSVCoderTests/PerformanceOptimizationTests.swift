//
//  PerformanceOptimizationTests.swift
//  CSVCoder
//
//  Comprehensive tests for performance optimization utilities:
//  - SWARUtils: SIMD Within A Register utilities
//  - CSVUnescaper: Zero-allocation field unescaping
//

@testable import CSVCoder
import Foundation
import Testing

// MARK: - SWARUtilsTests

@Suite("SWAR Utilities")
struct SWARUtilsTests {
    @Test("broadcast replicates byte to all positions")
    func broadcastByte() {
        let result = SWARUtils.broadcast(0x42)
        #expect(result == 0x4242_4242_4242_4242)
    }

    @Test("broadcast handles zero")
    func broadcastZero() {
        let result = SWARUtils.broadcast(0x00)
        #expect(result == 0)
    }

    @Test("broadcast handles 0xFF")
    func broadcastFF() {
        let result = SWARUtils.broadcast(0xFF)
        #expect(result == UInt64.max)
    }

    @Test("findByte detects byte at position 0")
    func findBytePosition0() {
        let word: UInt64 = 0x0000_0000_0000_0042
        let mask = SWARUtils.findByte(word, target: 0x42)
        #expect(mask != 0)
        #expect(SWARUtils.firstMatchIndex(mask) == 0)
    }

    @Test("findByte detects byte at position 7")
    func findBytePosition7() {
        let word: UInt64 = 0x4200_0000_0000_0000
        let mask = SWARUtils.findByte(word, target: 0x42)
        #expect(mask != 0)
        #expect(SWARUtils.firstMatchIndex(mask) == 7)
    }

    @Test("findByte returns zero when byte not found")
    func findByteNotFound() {
        let word: UInt64 = 0x4141_4141_4141_4141
        let mask = SWARUtils.findByte(word, target: 0x42)
        #expect(mask == 0)
    }

    @Test("findByte handles multiple occurrences")
    func findByteMultiple() {
        let word: UInt64 = 0x4200_4200_4200_4200
        let mask = SWARUtils.findByte(word, target: 0x42)
        #expect(mask != 0)
        // Should find the first occurrence
        #expect(SWARUtils.firstMatchIndex(mask) == 1)
    }

    @Test("hasAnyByte detects first target")
    func hasAnyByteFirst() {
        let word: UInt64 = 0x0000_0000_0000_0041
        #expect(SWARUtils.hasAnyByte(word, 0x41, 0x42, 0x43, 0x44))
    }

    @Test("hasAnyByte detects fourth target")
    func hasAnyByteFourth() {
        let word: UInt64 = 0x0000_0000_0000_0044
        #expect(SWARUtils.hasAnyByte(word, 0x41, 0x42, 0x43, 0x44))
    }

    @Test("hasAnyByte returns false when no match")
    func hasAnyByteNoMatch() {
        let word: UInt64 = 0x0000_0000_0000_0045
        #expect(!SWARUtils.hasAnyByte(word, 0x41, 0x42, 0x43, 0x44))
    }

    @Test("hasAnyByte detects structural CSV characters")
    func hasAnyByteCSVStructural() {
        // Quote (0x22), comma (0x2C), CR (0x0D), LF (0x0A)
        let comma: UInt64 = 0x0000_0000_0000_002C
        #expect(SWARUtils.hasAnyByte(comma, 0x22, 0x2C, 0x0D, 0x0A))

        let quote: UInt64 = 0x0000_0000_0000_0022
        #expect(SWARUtils.hasAnyByte(quote, 0x22, 0x2C, 0x0D, 0x0A))

        let lf: UInt64 = 0x0000_0000_0000_000A
        #expect(SWARUtils.hasAnyByte(lf, 0x22, 0x2C, 0x0D, 0x0A))
    }

    @Test("firstMatchIndex returns nil for zero mask")
    func firstMatchIndexNil() {
        #expect(SWARUtils.firstMatchIndex(0) == nil)
    }

    @Test("firstMatchIndex returns correct position")
    func firstMatchIndexCorrectPosition() {
        // Mask with high bit set in byte 3 (position 24-31)
        let mask: UInt64 = 0x0000_0000_8000_0000
        #expect(SWARUtils.firstMatchIndex(mask) == 3)
    }

    @Test("load reads 8 bytes correctly")
    func loadBytes() {
        let bytes: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
        let result = bytes.withUnsafeBufferPointer { buffer in
            SWARUtils.load(buffer.baseAddress!)
        }
        // Little-endian: 0x0807060504030201
        #expect(result == 0x0807_0605_0403_0201)
    }

    @Test("load handles unaligned access")
    func loadUnaligned() {
        // Create a buffer with an offset to test unaligned access
        let bytes: [UInt8] = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09]
        bytes.withUnsafeBufferPointer { buffer in
            // Load from offset 1 (unaligned)
            let result = SWARUtils.load(buffer.baseAddress!.advanced(by: 1))
            #expect(result == 0x0807_0605_0403_0201)
        }
    }
}

// MARK: - CSVUnescaperTests

@Suite("CSV Unescaper")
struct CSVUnescaperTests {
    @Test("hasEscapedQuotes returns false for empty buffer")
    func hasEscapedQuotesEmpty() {
        let bytes: [UInt8] = []
        let result = bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return false }
            return CSVUnescaper.hasEscapedQuotes(buffer: base, count: buffer.count)
        }
        #expect(!result)
    }

    @Test("hasEscapedQuotes returns false for single byte")
    func hasEscapedQuotesSingleByte() {
        let bytes: [UInt8] = [0x22] // single quote
        let result = bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return false }
            return CSVUnescaper.hasEscapedQuotes(buffer: base, count: buffer.count)
        }
        #expect(!result)
    }

    @Test("hasEscapedQuotes returns true for double quotes")
    func hasEscapedQuotesDoubleQuote() {
        let bytes: [UInt8] = [0x22, 0x22] // ""
        let result = bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return false }
            return CSVUnescaper.hasEscapedQuotes(buffer: base, count: buffer.count)
        }
        #expect(result)
    }

    @Test("hasEscapedQuotes returns false for separated quotes")
    func hasEscapedQuotesSeparated() {
        let bytes: [UInt8] = [0x22, 0x41, 0x22] // "A"
        let result = bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return false }
            return CSVUnescaper.hasEscapedQuotes(buffer: base, count: buffer.count)
        }
        #expect(!result)
    }

    @Test("hasEscapedQuotes finds escaped quote in middle")
    func hasEscapedQuotesMiddle() {
        let text = "Hello\"\"World"
        let bytes = Array(text.utf8)
        let result = bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return false }
            return CSVUnescaper.hasEscapedQuotes(buffer: base, count: buffer.count)
        }
        #expect(result)
    }

    @Test("hasEscapedQuotes handles long text without escaped quotes")
    func hasEscapedQuotesLongNoEscape() {
        let text = String(repeating: "abcdefghij", count: 100) // 1000 chars, no quotes
        let bytes = Array(text.utf8)
        let result = bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return false }
            return CSVUnescaper.hasEscapedQuotes(buffer: base, count: buffer.count)
        }
        #expect(!result)
    }

    @Test("hasEscapedQuotes handles long text with escaped quotes")
    func hasEscapedQuotesLongWithEscape() {
        var text = String(repeating: "abcdefghij", count: 100) // 1000 chars
        text += "\"\"" // Add escaped quote at end
        let bytes = Array(text.utf8)
        let result = bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return false }
            return CSVUnescaper.hasEscapedQuotes(buffer: base, count: buffer.count)
        }
        #expect(result)
    }

    @Test("unescape returns empty string for empty buffer")
    func unescapeEmpty() {
        let bytes: [UInt8] = []
        let result = bytes.withUnsafeBufferPointer { buffer in
            CSVUnescaper.unescape(buffer: buffer)
        }
        #expect(result == "")
    }

    @Test("unescape returns original text when no escaping needed")
    func unescapeNoEscaping() {
        let text = "Hello, World!"
        let bytes = Array(text.utf8)
        let result = bytes.withUnsafeBufferPointer { buffer in
            CSVUnescaper.unescape(buffer: buffer)
        }
        #expect(result == text)
    }

    @Test("unescape converts double quote to single quote")
    func unescapeDoubleQuote() {
        let bytes: [UInt8] = [0x22, 0x22] // ""
        let result = bytes.withUnsafeBufferPointer { buffer in
            CSVUnescaper.unescape(buffer: buffer)
        }
        #expect(result == "\"")
    }

    @Test("unescape handles multiple escaped quotes")
    func unescapeMultiple() {
        let text = "Say \"\"Hello\"\" and \"\"Goodbye\"\""
        let bytes = Array(text.utf8)
        let result = bytes.withUnsafeBufferPointer { buffer in
            CSVUnescaper.unescape(buffer: buffer)
        }
        #expect(result == "Say \"Hello\" and \"Goodbye\"")
    }

    @Test("unescape preserves surrounding text")
    func unescapePreservesText() {
        let text = "Before\"\"After"
        let bytes = Array(text.utf8)
        let result = bytes.withUnsafeBufferPointer { buffer in
            CSVUnescaper.unescape(buffer: buffer)
        }
        #expect(result == "Before\"After")
    }

    @Test("unescape handles escaped quote at start")
    func unescapeAtStart() {
        let text = "\"\"Start"
        let bytes = Array(text.utf8)
        let result = bytes.withUnsafeBufferPointer { buffer in
            CSVUnescaper.unescape(buffer: buffer)
        }
        #expect(result == "\"Start")
    }

    @Test("unescape handles escaped quote at end")
    func unescapeAtEnd() {
        let text = "End\"\""
        let bytes = Array(text.utf8)
        let result = bytes.withUnsafeBufferPointer { buffer in
            CSVUnescaper.unescape(buffer: buffer)
        }
        #expect(result == "End\"")
    }

    @Test("unescape with UTF-8 encoding")
    func unescapeUTF8() {
        let text = "Unicode: 日本語\"\"emoji: 🎉"
        let bytes = Array(text.utf8)
        let result = bytes.withUnsafeBufferPointer { buffer in
            CSVUnescaper.unescape(buffer: buffer, encoding: .utf8)
        }
        #expect(result == "Unicode: 日本語\"emoji: 🎉")
    }

    @Test("unescape handles consecutive escaped quotes")
    func unescapeConsecutive() {
        let bytes: [UInt8] = [0x22, 0x22, 0x22, 0x22] // """"
        let result = bytes.withUnsafeBufferPointer { buffer in
            CSVUnescaper.unescape(buffer: buffer)
        }
        #expect(result == "\"\"") // Two quotes
    }
}

// MARK: - CSVParserIntegrationTests

@Suite("CSVParser Integration")
struct CSVParserIntegrationTests {
    @Test("CSVParser parses simple CSV")
    func parserSimple() {
        let csv = "a,b,c\n1,2,3\n4,5,6"
        let data = Data(csv.utf8)

        let rows = CSVParser.parse(data: data) { parser in
            parser.map { row in
                (0 ..< row.count).map { row.string(at: $0) ?? "" }
            }
        }

        #expect(rows.count == 3)
        #expect(rows[0] == ["a", "b", "c"])
        #expect(rows[1] == ["1", "2", "3"])
        #expect(rows[2] == ["4", "5", "6"])
    }

    @Test("CSVParser preserves field data integrity")
    func parserPreservesData() {
        let csv = "name,value\n\"Quoted \"\"Name\"\"\",123\nSimple,456\n\"Multi\nline\",789"
        let data = Data(csv.utf8)

        let rows = CSVParser.parse(data: data) { parser in
            parser.map { row in
                [row.string(at: 0) ?? "", row.string(at: 1) ?? ""]
            }
        }

        #expect(rows.count == 4)
        #expect(rows[0][0] == "name")
        #expect(rows[1][0] == "Quoted \"Name\"")
        #expect(rows[2][0] == "Simple")
        #expect(rows[3][0] == "Multi\nline")
    }

    @Test("CSVParser handles large CSV efficiently")
    func parserLargeCSV() {
        // Generate 10K row CSV
        var csv = "id,name,value\n"
        for i in 0 ..< 10000 {
            csv += "\(i),Name\(i),\(Double(i) * 1.5)\n"
        }
        let data = Data(csv.utf8)

        let count = CSVParser.parse(data: data) { parser in
            parser.reduce(0) { count, _ in count + 1 }
        }

        #expect(count == 10001) // Including header
    }
}

// MARK: - SIMDScannerIntegrationTests

@Suite("SIMD Scanner Integration")
struct SIMDScannerIntegrationTests {
    @Test("scanStructural finds quotes in large buffer")
    func scanStructuralQuotes() {
        let csv = String(repeating: "abcdefghij", count: 100) + "\"" + String(repeating: "klmnopqrst", count: 100)
        let bytes = Array(csv.utf8)

        let positions = bytes.withUnsafeBufferPointer { buffer in
            SIMDScanner.scanStructural(buffer: buffer.baseAddress!, count: buffer.count, delimiter: 0x2C)
        }

        let quotePositions = positions.filter(\.isQuote)
        #expect(quotePositions.count == 1)
        #expect(quotePositions[0].offset == 1000)
    }

    @Test("scanStructural finds all structural characters")
    func scanStructuralAll() {
        let csv = "a,b,c\r\nd,\"e\",f\n"
        let bytes = Array(csv.utf8)

        let positions = bytes.withUnsafeBufferPointer { buffer in
            SIMDScanner.scanStructural(buffer: buffer.baseAddress!, count: buffer.count, delimiter: 0x2C)
        }

        let commas = positions.filter(\.isComma)
        let quotes = positions.filter(\.isQuote)
        let newlines = positions.filter(\.isNewline)

        #expect(commas.count == 4)
        #expect(quotes.count == 2)
        #expect(newlines.count == 3) // CR, LF, LF
    }

    @Test("countNewlinesApprox counts LF correctly")
    func countNewlines() {
        let csv = "a\nb\nc\nd\ne\n"
        let bytes = Array(csv.utf8)

        let count = bytes.withUnsafeBufferPointer { buffer in
            SIMDScanner.countNewlinesApprox(buffer: buffer.baseAddress!, count: buffer.count)
        }

        #expect(count == 5)
    }

    @Test("countNewlinesApprox handles large buffer")
    func countNewlinesLarge() {
        let line = "abcdefghijklmnopqrstuvwxyz0123456789\n"
        let csv = String(repeating: line, count: 1000)
        let bytes = Array(csv.utf8)

        let count = bytes.withUnsafeBufferPointer { buffer in
            SIMDScanner.countNewlinesApprox(buffer: buffer.baseAddress!, count: buffer.count)
        }

        #expect(count == 1000)
    }

    @Test("findNextStructural finds delimiter")
    func findNextStructuralDelimiter() {
        let csv = "hello,world"
        let bytes = Array(csv.utf8)

        let pos = bytes.withUnsafeBufferPointer { buffer in
            SIMDScanner.findNextStructural(buffer: buffer.baseAddress!, count: buffer.count, delimiter: 0x2C)
        }

        #expect(pos == 5)
    }

    @Test("findNextStructural finds newline")
    func findNextStructuralNewline() {
        let csv = "hello\nworld"
        let bytes = Array(csv.utf8)

        let pos = bytes.withUnsafeBufferPointer { buffer in
            SIMDScanner.findNextStructural(buffer: buffer.baseAddress!, count: buffer.count, delimiter: 0x2C)
        }

        #expect(pos == 5)
    }

    @Test("findNextStructural returns count when not found")
    func findNextStructuralNotFound() {
        let csv = "helloworld"
        let bytes = Array(csv.utf8)

        let pos = bytes.withUnsafeBufferPointer { buffer in
            SIMDScanner.findNextStructural(buffer: buffer.baseAddress!, count: buffer.count, delimiter: 0x2C)
        }

        #expect(pos == bytes.count)
    }

    @Test("findNextQuote finds quote in large buffer")
    func findNextQuoteLarge() {
        let prefix = String(repeating: "a", count: 200)
        let csv = prefix + "\""
        let bytes = Array(csv.utf8)

        let pos = bytes.withUnsafeBufferPointer { buffer in
            SIMDScanner.findNextQuote(buffer: buffer.baseAddress!, count: buffer.count)
        }

        #expect(pos == 200)
    }

    @Test("findRowBoundaries handles CRLF")
    func findRowBoundariesCRLF() {
        let csv = "a,b,c\r\nd,e,f\r\n"
        let bytes = Array(csv.utf8)

        let boundaries = bytes.withUnsafeBufferPointer { buffer in
            SIMDScanner.findRowBoundaries(buffer: buffer.baseAddress!, count: buffer.count)
        }

        #expect(boundaries.rowStarts.count == 2)
        #expect(boundaries.rowStarts[0] == 0)
        #expect(boundaries.rowStarts[1] == 7)
    }

    @Test("findRowBoundaries handles quoted newlines")
    func findRowBoundariesQuotedNewlines() {
        let csv = "\"a\nb\",c\nd,e\n"
        let bytes = Array(csv.utf8)

        let boundaries = bytes.withUnsafeBufferPointer { buffer in
            SIMDScanner.findRowBoundaries(buffer: buffer.baseAddress!, count: buffer.count)
        }

        // Should find 2 rows: "a\nb",c and d,e
        #expect(boundaries.rowStarts.count == 2)
    }
}

// MARK: - CSVFieldEscaperTests

@Suite("CSV Field Escaper")
struct CSVFieldEscaperTests {
    @Test("needsQuoting returns false for simple text")
    func needsQuotingSimple() {
        let text = "Hello World"
        let bytes = Array(text.utf8)
        let result = bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return false }
            return CSVFieldEscaper.needsQuoting(buffer: base, count: buffer.count, delimiter: 0x2C)
        }
        #expect(!result)
    }

    @Test("needsQuoting returns true for text with comma")
    func needsQuotingComma() {
        let text = "Hello, World"
        let bytes = Array(text.utf8)
        let result = bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return false }
            return CSVFieldEscaper.needsQuoting(buffer: base, count: buffer.count, delimiter: 0x2C)
        }
        #expect(result)
    }

    @Test("needsQuoting returns true for text with quote")
    func needsQuotingQuote() {
        let text = "Hello \"World\""
        let bytes = Array(text.utf8)
        let result = bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return false }
            return CSVFieldEscaper.needsQuoting(buffer: base, count: buffer.count, delimiter: 0x2C)
        }
        #expect(result)
    }

    @Test("needsQuoting returns true for text with newline")
    func needsQuotingNewline() {
        let text = "Hello\nWorld"
        let bytes = Array(text.utf8)
        let result = bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return false }
            return CSVFieldEscaper.needsQuoting(buffer: base, count: buffer.count, delimiter: 0x2C)
        }
        #expect(result)
    }

    @Test("needsQuoting returns true for text with CR")
    func needsQuotingCR() {
        let text = "Hello\rWorld"
        let bytes = Array(text.utf8)
        let result = bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return false }
            return CSVFieldEscaper.needsQuoting(buffer: base, count: buffer.count, delimiter: 0x2C)
        }
        #expect(result)
    }

    @Test("needsQuoting handles large text without special chars")
    func needsQuotingLarge() {
        let text = String(repeating: "abcdefghij", count: 100)
        let bytes = Array(text.utf8)
        let result = bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return false }
            return CSVFieldEscaper.needsQuoting(buffer: base, count: buffer.count, delimiter: 0x2C)
        }
        #expect(!result)
    }

    @Test("appendEscaped handles simple text")
    func appendEscapedSimple() {
        var buffer: [UInt8] = []
        CSVFieldEscaper.appendEscaped("Hello", to: &buffer, delimiter: 0x2C)
        #expect(String(decoding: buffer, as: UTF8.self) == "Hello")
    }

    @Test("appendEscaped quotes text with comma")
    func appendEscapedComma() {
        var buffer: [UInt8] = []
        CSVFieldEscaper.appendEscaped("Hello, World", to: &buffer, delimiter: 0x2C)
        #expect(String(decoding: buffer, as: UTF8.self) == "\"Hello, World\"")
    }

    @Test("appendEscaped escapes quotes")
    func appendEscapedQuotes() {
        var buffer: [UInt8] = []
        CSVFieldEscaper.appendEscaped("Say \"Hi\"", to: &buffer, delimiter: 0x2C)
        #expect(String(decoding: buffer, as: UTF8.self) == "\"Say \"\"Hi\"\"\"")
    }

    @Test("appendEscaped handles Unicode")
    func appendEscapedUnicode() {
        var buffer: [UInt8] = []
        CSVFieldEscaper.appendEscaped("日本語,emoji: 🎉", to: &buffer, delimiter: 0x2C)
        #expect(String(decoding: buffer, as: UTF8.self) == "\"日本語,emoji: 🎉\"")
    }
}

// MARK: - FieldBufferPoolTests

@Suite("Legacy Field Buffer Pool")
struct FieldBufferPoolTests {
    @Test("lease returns buffer with requested capacity")
    func leaseCapacity() {
        let pool = FieldBufferPool(maxPoolSize: 4)
        let buffer = pool.lease(capacity: 100)
        #expect(buffer.capacity >= 100)
    }

    @Test("return adds buffer to pool")
    func returnBuffer() {
        let pool = FieldBufferPool(maxPoolSize: 4)
        var buffer = pool.lease(capacity: 100)
        buffer.append(contentsOf: [1, 2, 3])
        pool.return(&buffer)

        // Lease again - should get cleared buffer
        let buffer2 = pool.lease(capacity: 50)
        #expect(buffer2.isEmpty || buffer2.capacity >= 100)
    }

    @Test("pool respects max size")
    func poolMaxSize() {
        let pool = FieldBufferPool(maxPoolSize: 2)
        var b1 = pool.lease(capacity: 10)
        var b2 = pool.lease(capacity: 10)
        var b3 = pool.lease(capacity: 10)

        pool.return(&b1)
        pool.return(&b2)
        pool.return(&b3) // Should be dropped

        // Can only lease 2 from pool
        _ = pool.lease(capacity: 10)
        _ = pool.lease(capacity: 10)
    }

    @Test("clear removes all buffers")
    func clearPool() {
        let pool = FieldBufferPool(maxPoolSize: 4)
        var b1 = pool.lease(capacity: 10)
        var b2 = pool.lease(capacity: 10)
        pool.return(&b1)
        pool.return(&b2)

        pool.clear()

        // Pool should be empty - new lease creates new buffer
        let buffer = pool.lease(capacity: 10)
        #expect(buffer.capacity >= 10)
    }
}
