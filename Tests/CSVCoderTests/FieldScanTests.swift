//
//  FieldScanTests.swift
//  CSVCoder
//
//  FieldScan must agree with a byte-by-byte search at every length and every position of the match,
//  across the boundary where it hands over from the inline scan to the vector kernel.
//

@testable import CSVCoder
import Testing

@Suite("FieldScan")
struct FieldScanTests {
    private static func nextStructural(_ bytes: [UInt8], delimiter: UInt8) -> Int {
        bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return 0 }
            return FieldScan.nextStructural(base, count: buffer.count, delimiter: delimiter)
        }
    }

    private static func nextQuote(_ bytes: [UInt8]) -> Int {
        bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return 0 }
            return FieldScan.nextQuote(base, count: buffer.count)
        }
    }

    @Test("The first structural byte is found at every length and position", arguments: [0x2C, 0x3B, 0x09] as [UInt8])
    func structuralAtEveryPosition(delimiter: UInt8) {
        let others: [UInt8] = [delimiter, 0x0D, 0x0A, 0x22]
        for length in 0...70 {
            for position in 0..<max(length, 1) {
                for needle in others {
                    var bytes = [UInt8](repeating: 0x61, count: length)
                    guard position < length else { continue }
                    bytes[position] = needle
                    #expect(Self.nextStructural(bytes, delimiter: delimiter) == position)
                }
            }
            let clean = [UInt8](repeating: 0x61, count: length)
            #expect(Self.nextStructural(clean, delimiter: delimiter) == length)
        }
    }

    @Test("The earliest of several structural bytes wins")
    func earliestWins() {
        var bytes = [UInt8](repeating: 0x61, count: 100)
        bytes[90] = 0x0A
        bytes[40] = 0x22
        bytes[70] = 0x2C
        #expect(Self.nextStructural(bytes, delimiter: 0x2C) == 40)
    }

    @Test("Bytes that merely resemble a structural byte are skipped")
    func lookalikesAreSkipped() {
        // 0x2B, 0x2D, 0x0B, 0x0C, 0x21 and 0x23 are one off the delimiter, LF, CR and quote.
        let bytes: [UInt8] = Array(repeating: [0x2B, 0x2D, 0x0B, 0x0C, 0x21, 0x23, 0xA2, 0xAC, 0x8A], count: 12).flatMap
        { $0 }
        #expect(Self.nextStructural(bytes, delimiter: 0x2C) == bytes.count)
    }

    @Test("The first quote is found at every length and position")
    func quoteAtEveryPosition() {
        for length in 1...70 {
            for position in 0..<length {
                var bytes = [UInt8](repeating: 0x61, count: length)
                bytes[position] = 0x22
                #expect(Self.nextQuote(bytes) == position)
            }
            #expect(Self.nextQuote([UInt8](repeating: 0x2C, count: length)) == length)
        }
    }
}
