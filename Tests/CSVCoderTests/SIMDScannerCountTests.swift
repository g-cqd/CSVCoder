//
//  SIMDScannerCountTests.swift
//  CSVCoder
//
//  countNewlinesApprox must agree with a byte-by-byte count; the SWAR zero-byte test it used
//  reports a false match in the byte above a real one (an LF followed by 0x0B).
//

@testable import CSVCoder
import Foundation
import Testing

@Suite("SIMDScanner newline count")
struct SIMDScannerCountTests {
    private static func count(_ bytes: [UInt8]) -> Int {
        bytes.withUnsafeBufferPointer { SIMDScanner.countNewlinesApprox(buffer: $0.baseAddress!, count: $0.count) }
    }

    @Test("An LF followed by a byte one above it is counted once", arguments: [8, 9, 15, 63])
    func lfThenVerticalTab(length: Int) {
        var bytes = [UInt8](repeating: 0x41, count: length)
        bytes[0] = 0x0A
        bytes[1] = 0x0B  // 0x0A ^ 0x0A = 0, 0x0B ^ 0x0A = 1: the borrow from the first byte flags the second
        #expect(Self.count(bytes) == 1)
    }

    @Test("The count equals a scalar count on random bytes at every length", arguments: 0...130)
    func matchesScalarCount(length: Int) {
        var generator = SystemRandomNumberGenerator()
        // Bias towards 0x09...0x0C so neighbours of LF are common.
        let bytes = (0..<length).map { _ in UInt8.random(in: 0x08...0x0D, using: &generator) }
        #expect(Self.count(bytes) == bytes.filter { $0 == 0x0A }.count)
    }
}
