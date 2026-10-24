//
//  FieldScan.swift
//  CSVCoder
//
//  Finds the end of a CSV field: a short inline scan, then Aemi's vector kernels.
//

import AemiKernels

/// Byte searches for the field scanner.
///
/// A CSV field is usually a few bytes, so a call into a vector kernel (about 4 ns of setup) costs more
/// than scanning the field. The first ``inlineBytes`` bytes are scanned in place; only a longer field
/// reaches the kernel, where it is faster at every length measured from 20 bytes up (11x at 400).
enum FieldScan {
    /// Bytes scanned in place before the vector kernel takes over.
    ///
    /// 16 was never slower than the previous scanner at any length from 2 to 4,000 bytes; 8 was 1.15x slower
    /// at 10 bytes, 24 gave back the gain at 40 and 100.
    static let inlineBytes = 16

    /// Bytes tested in a register before the kernel takes over in ``containsStructural(_:count:delimiter:)``.
    static let swarBytes = 64

    private static let quote: UInt8 = 0x22
    private static let cr: UInt8 = 0x0D
    private static let lf: UInt8 = 0x0A

    /// The offset of the first delimiter, CR, LF or quote in `base[0..<count]`.
    ///
    /// - Parameters:
    ///   - base: The first byte to examine.
    ///   - count: The number of readable bytes at `base`.
    ///   - delimiter: The field delimiter.
    /// - Returns: The offset of the match, or `count` if there is none.
    /// - Complexity: O(*n*) in the distance to the match.
    @inline(__always)
    static func nextStructural(_ base: UnsafePointer<UInt8>, count: Int, delimiter: UInt8) -> Int {
        let head = min(count, inlineBytes)
        var index = 0
        while index < head {
            let byte = base[index]
            if byte == delimiter || byte == cr || byte == lf || byte == quote { return index }
            index += 1
        }
        guard count > head else { return count }
        return head
            + AemiKernels.firstIndexOfAny(
                base: base + head, count: count - head, delimiter, cr, lf, quote, quote)
    }

    /// Whether `base[0..<count]` holds a delimiter, CR, LF or quote: whether a field needs quoting.
    ///
    /// The first ``swarBytes`` bytes are tested eight at a time in a register, which beat a byte loop
    /// and the 16-byte kernel head at every length from 1 to 63 (a 24-byte field: 7.4 ns against 21.6);
    /// a longer field hands the rest to the vector kernel.
    ///
    /// - Complexity: O(*n*).
    @inline(__always)
    static func containsStructural(_ base: UnsafePointer<UInt8>, count: Int, delimiter: UInt8) -> Bool {
        let head = min(count, swarBytes)
        var offset = 0
        while offset + 8 <= head {
            if SWARUtils.hasAnyByte(SWARUtils.load(base + offset), quote, delimiter, cr, lf) { return true }
            offset += 8
        }
        while offset < head {
            let byte = base[offset]
            if byte == delimiter || byte == cr || byte == lf || byte == quote { return true }
            offset += 1
        }
        guard count > head else { return false }
        return AemiKernels.firstIndexOfAny(base: base + head, count: count - head, delimiter, cr, lf, quote, quote)
            < count - head
    }

    /// The offset of the first quote in `base[0..<count]`, or `count` if there is none.
    ///
    /// - Complexity: O(*n*) in the distance to the quote.
    @inline(__always)
    static func nextQuote(_ base: UnsafePointer<UInt8>, count: Int) -> Int {
        let head = min(count, inlineBytes)
        var index = 0
        while index < head {
            if base[index] == quote { return index }
            index += 1
        }
        guard count > head else { return count }
        return head + AemiKernels.firstIndexOfByte(base: base + head, count: count - head, needle: quote)
    }
}
