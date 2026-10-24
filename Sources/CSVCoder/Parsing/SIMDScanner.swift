//
//  SIMDScanner.swift
//  CSVCoder
//
//  SIMD-accelerated byte scanning for CSV parsing.
//  Uses 64-byte vectors for ~8x speedup over scalar scanning.
//  Includes SWAR (SIMD Within A Register) for 8-byte operations on smaller fields.
//

import Foundation

// MARK: - SWARUtils

/// SWAR (SIMD Within A Register) utilities for 8-byte parallel operations.
///
/// Processes 8 bytes at a time using UInt64 bit manipulation.
/// Used as fallback for fields smaller than 64 bytes.
enum SWARUtils: Sendable {
    /// Broadcasts a single byte to all 8 positions of a UInt64.
    @inline(__always)
    static func broadcast(_ byte: UInt8) -> UInt64 {
        UInt64(byte) &* 0x0101_0101_0101_0101
    }

    /// Returns a mask whose lowest set byte is the first byte equal to the target.
    ///
    /// Uses the classic "SWAR zero-byte detection" algorithm. It is exact for "is there a match"
    /// and for the lowest match, and nothing else: the borrow out of a zero byte also flags the byte
    /// above it when that byte is 0x01, so do not count its set bits. Use ``exactMatchMask(_:target:)``
    /// to count.
    @inline(__always)
    static func findByte(_ word: UInt64, target: UInt8) -> UInt64 {
        let broadcast = broadcast(target)
        let xored = word ^ broadcast
        // Zero bytes in xored become 0x80 in result
        return (xored &- 0x0101_0101_0101_0101) & ~xored & 0x8080_8080_8080_8080
    }

    /// Returns a mask with the high bit set in exactly the bytes equal to the target.
    ///
    /// The low seven bits are added without a carry out of any byte and the high bit is OR-ed back
    /// in, so no byte influences its neighbour. One operation dearer than ``findByte(_:target:)``.
    @inline(__always)
    static func exactMatchMask(_ word: UInt64, target: UInt8) -> UInt64 {
        let xored = word ^ broadcast(target)
        let low7: UInt64 = 0x7F7F_7F7F_7F7F_7F7F
        return ~(((xored & low7) &+ low7) | xored) & 0x8080_8080_8080_8080
    }

    /// Checks if any byte in the word matches any of the four targets.
    @inline(__always)
    static func hasAnyByte(_ word: UInt64, _ t1: UInt8, _ t2: UInt8, _ t3: UInt8, _ t4: UInt8) -> Bool {
        findByte(word, target: t1) != 0 || findByte(word, target: t2) != 0 || findByte(word, target: t3) != 0
            || findByte(word, target: t4) != 0
    }

    /// Finds the byte index (0-7) of the first match, or nil if none.
    @inline(__always)
    static func firstMatchIndex(_ mask: UInt64) -> Int? {
        guard mask != 0 else { return nil }
        // Each match sets the high bit of its byte (0x80 pattern)
        // Divide by 8 to convert bit position to byte position
        return mask.trailingZeroBitCount / 8
    }

    /// Loads 8 bytes from buffer as a UInt64 (little-endian).
    ///
    /// Uses unaligned load to avoid alignment requirements.
    @inline(__always)
    static func load(_ buffer: UnsafePointer<UInt8>) -> UInt64 {
        UnsafeRawPointer(buffer).loadUnaligned(as: UInt64.self)
    }
}

// MARK: - SIMD Loading

/// Loads 64 bytes from a buffer into a SIMD64 vector.
///
/// Package-internal for use by SIMDScanner and its extensions.
@inline(__always)
func loadSIMD64(from buffer: UnsafePointer<UInt8>) -> SIMD64<UInt8> {
    UnsafeRawPointer(buffer).loadUnaligned(as: SIMD64<UInt8>.self)
}

// MARK: - SIMDScanner

/// SIMD-accelerated scanner for finding CSV structural characters.
///
/// Uses 64-byte SIMD vectors to scan for quotes, delimiters, and newlines.
/// Falls back to SWAR (8-byte) for smaller data, then scalar for remainder.
struct SIMDScanner: Sendable {
    // MARK: Internal

    /// Represents a structural index entry.
    struct StructuralPosition: Sendable {
        let offset: Int
        let byte: UInt8

        var isQuote: Bool { byte == SIMDScanner.quote }
        var isComma: Bool { byte == SIMDScanner.comma }
        var isNewline: Bool { byte == SIMDScanner.cr || byte == SIMDScanner.lf }
    }

    /// Result of scanning a buffer for row boundaries.
    struct RowBoundaries: Sendable {
        /// Start offsets of each row in the buffer.
        let rowStarts: [Int]
        /// Whether the buffer ends mid-quote (incomplete row).
        let endsInQuote: Bool
        /// Offset where the last complete row ends.
        let lastCompleteRowEnd: Int
    }

    /// Scans a buffer for structural CSV characters using SIMD.
    ///
    /// Returns positions of all quotes, delimiters, and newlines.
    ///
    /// - Parameters:
    ///   - buffer: Pointer to UTF-8 bytes.
    ///   - count: Number of bytes to scan.
    ///   - delimiter: The field delimiter byte (default comma).
    /// - Returns: Array of structural positions sorted by offset.
    @inline(__always)
    static func scanStructural(
        buffer: UnsafePointer<UInt8>,
        count: Int,
        delimiter: UInt8 = comma,
    ) -> [StructuralPosition] {
        var positions: [StructuralPosition] = []
        // Empirically ~1 structural per 32 bytes for typical CSV with average
        // field widths.  The array will grow if needed; cache locality matters
        // more than avoiding one realloc on text-heavy data.
        positions.reserveCapacity(count / 32)

        var offset = 0

        // Process 64 bytes at a time using SIMD
        while offset + 64 <= count {
            let chunk = loadSIMD64(from: buffer.advanced(by: offset))

            // Create comparison masks
            let quoteVec = SIMD64<UInt8>(repeating: quote)
            let delimVec = SIMD64<UInt8>(repeating: delimiter)
            let crVec = SIMD64<UInt8>(repeating: cr)
            let lfVec = SIMD64<UInt8>(repeating: lf)

            // Compare and get masks
            let quoteMask = chunk .== quoteVec
            let delimMask = chunk .== delimVec
            let crMask = chunk .== crVec
            let lfMask = chunk .== lfVec

            // Combine all structural masks
            let structuralMask = quoteMask .| delimMask .| crMask .| lfMask

            // SIMDMask's underlying storage is not directly exposed as a
            // bit-packed `UInt64`, and the alternatives (per-lane bit
            // construction via `unsafeBitCast` over `SIMD64<Int8>` + a series
            // of ANDs) measured no faster than the simple loop on Apple
            // silicon.  Keep the loop for portability; revisit when stdlib
            // gains a stable `bitPattern` accessor.
            for i in 0..<64 where structuralMask[i] {
                positions.append(StructuralPosition(offset: offset + i, byte: buffer[offset + i]))
            }

            offset += 64
        }

        // SWAR fallback for 8-63 remaining bytes
        while offset + 8 <= count {
            let word = SWARUtils.load(buffer.advanced(by: offset))
            if SWARUtils.hasAnyByte(word, quote, delimiter, cr, lf) {
                // Found structural byte, scan individually
                for i in 0..<8 {
                    let byte = buffer[offset + i]
                    if byte == quote || byte == delimiter || byte == cr || byte == lf {
                        positions.append(StructuralPosition(offset: offset + i, byte: byte))
                    }
                }
            }
            offset += 8
        }

        // Scalar fallback for remaining 0-7 bytes
        while offset < count {
            let byte = buffer[offset]
            if byte == quote || byte == delimiter || byte == cr || byte == lf {
                positions.append(StructuralPosition(offset: offset, byte: byte))
            }
            offset += 1
        }

        return positions
    }

    /// Finds row boundaries in a buffer, accounting for quoted fields.
    ///
    /// Uses SIMD scanning followed by state machine for quote tracking.
    ///
    /// - Parameters:
    ///   - buffer: Pointer to UTF-8 bytes.
    ///   - count: Number of bytes to scan.
    ///   - delimiter: The field delimiter byte.
    ///   - startOffset: Global offset (for reporting absolute positions).
    /// - Returns: Row boundary information.
    static func findRowBoundaries(
        buffer: UnsafePointer<UInt8>,
        count: Int,
        delimiter: UInt8 = comma,
        startOffset: Int = 0,
    ) -> RowBoundaries {
        // Fast path: scan for structural characters
        let structural = scanStructural(buffer: buffer, count: count, delimiter: delimiter)

        var rowStarts: [Int] = [startOffset]
        var inQuotes = false
        var lastNewlineEnd = 0

        for pos in structural {
            if pos.isQuote {
                inQuotes.toggle()
            } else if !inQuotes, pos.isNewline {
                // Found row boundary
                var endOffset = pos.offset

                // Handle CRLF as single newline
                if pos.byte == cr, pos.offset + 1 < count, buffer[pos.offset + 1] == lf {
                    endOffset = pos.offset + 1
                }

                // Skip if this is the LF of a CRLF we already processed
                if pos.byte == lf, pos.offset > 0, buffer[pos.offset - 1] == cr {
                    continue
                }

                lastNewlineEnd = endOffset + 1
                if lastNewlineEnd < count {
                    rowStarts.append(startOffset + lastNewlineEnd)
                }
            }
        }

        return RowBoundaries(
            rowStarts: rowStarts,
            endsInQuote: inQuotes,
            lastCompleteRowEnd: startOffset + lastNewlineEnd,
        )
    }

    /// Counts approximate row count in buffer using SIMD newline detection.
    ///
    /// Note: This is an approximation that doesn't account for quoted newlines.
    /// Use for chunk sizing estimates, not exact counting.
    ///
    /// - Parameters:
    ///   - buffer: Pointer to UTF-8 bytes.
    ///   - count: Number of bytes to scan.
    /// - Returns: Approximate number of newlines (LF characters).
    @inline(__always)
    static func countNewlinesApprox(
        buffer: UnsafePointer<UInt8>,
        count: Int,
    ) -> Int {
        var total = 0
        var offset = 0

        // Process 64 bytes at a time using SIMD
        while offset + 64 <= count {
            let chunk = loadSIMD64(from: buffer.advanced(by: offset))
            let lfVec = SIMD64<UInt8>(repeating: lf)
            let mask = chunk .== lfVec

            // Direct count - avoids bitmask conversion overhead
            for i in 0..<64 where mask[i] {
                total += 1
            }
            offset += 64
        }

        // SWAR fallback for 8-63 remaining bytes
        while offset + 8 <= count {
            let word = SWARUtils.load(buffer.advanced(by: offset))
            let lfMask = SWARUtils.exactMatchMask(word, target: lf)
            // Count high bits set (each match has 0x80 pattern)
            total += (lfMask / 0x80).nonzeroBitCount
            offset += 8
        }

        // Scalar fallback for remaining 0-7 bytes
        while offset < count {
            if buffer[offset] == lf {
                total += 1
            }
            offset += 1
        }

        return total
    }

    // MARK: Private

    // CSV structural bytes (ASCII)
    private static let quote: UInt8 = 0x22  // "
    private static let comma: UInt8 = 0x2C  // ,
    private static let cr: UInt8 = 0x0D  // \r
    private static let lf: UInt8 = 0x0A  // \n
}
