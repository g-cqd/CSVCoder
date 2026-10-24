//
//  FieldScanTests.swift
//  CSVCoder
//
//  FieldScan must agree with a byte-by-byte search at every length and every position of the match,
//  across the boundary where it hands over from the inline scan to the vector kernel.
//

import Testing

@testable import CSVCoder

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
        // One expectation for the whole sweep: thousands of #expect calls in an unoptimized build would keep
        // a core busy long enough to disturb the wall-clock tests that run beside this one.
        var failures: [String] = []
        for length in 0...70 {
            for position in 0..<length {
                for needle in others {
                    var bytes = [UInt8](repeating: 0x61, count: length)
                    bytes[position] = needle
                    let found = Self.nextStructural(bytes, delimiter: delimiter)
                    if found != position { failures.append("length \(length), \(needle) at \(position): \(found)") }
                }
            }
            let clean = [UInt8](repeating: 0x61, count: length)
            if Self.nextStructural(clean, delimiter: delimiter) != length { failures.append("clean length \(length)") }
        }
        #expect(failures.isEmpty, "\(failures.prefix(5))")
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
        var failures: [String] = []
        for length in 1...70 {
            for position in 0..<length {
                var bytes = [UInt8](repeating: 0x61, count: length)
                bytes[position] = 0x22
                if Self.nextQuote(bytes) != position { failures.append("length \(length), quote at \(position)") }
            }
            if Self.nextQuote([UInt8](repeating: 0x2C, count: length)) != length { failures.append("clean length \(length)") }
        }
        #expect(failures.isEmpty, "\(failures.prefix(5))")
    }
}

extension FieldScanTests {
    @Test("needsQuoting agrees with a byte-by-byte test at every length and position")
    func containsStructuralAtEveryPosition() {
        func contains(_ bytes: [UInt8]) -> Bool {
            bytes.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return false }
                return FieldScan.containsStructural(base, count: buffer.count, delimiter: 0x2C)
            }
        }
        var failures: [String] = []
        for length in 0...140 {
            if contains([UInt8](repeating: 0x61, count: length)) { failures.append("clean length \(length)") }
            // 0x2B is one below the delimiter.
            if contains([UInt8](repeating: 0x2B, count: length)) { failures.append("lookalike length \(length)") }
            for position in 0..<length {
                for needle: UInt8 in [0x2C, 0x0D, 0x0A, 0x22] {
                    var bytes = [UInt8](repeating: 0x61, count: length)
                    bytes[position] = needle
                    if !contains(bytes) { failures.append("length \(length), \(needle) at \(position)") }
                }
            }
        }
        #expect(failures.isEmpty, "\(failures.prefix(5))")
    }
}
