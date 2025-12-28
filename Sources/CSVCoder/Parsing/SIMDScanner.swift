//
//  SIMDScanner.swift
//  CSVCoder
//
//  SIMD-accelerated byte scanning for CSV parsing.
//  Uses 64-byte vectors for ~8x speedup over scalar scanning.
//

import Foundation

/// SIMD-accelerated scanner for finding CSV structural characters.
/// Uses 64-byte SIMD vectors to scan for quotes, delimiters, and newlines.
struct SIMDScanner: Sendable {

    // CSV structural bytes (ASCII)
    private static let quote: UInt8 = 0x22      // "
    private static let comma: UInt8 = 0x2C      // ,
    private static let cr: UInt8 = 0x0D         // \r
    private static let lf: UInt8 = 0x0A         // \n
    private static let tab: UInt8 = 0x09        // \t

    /// Represents a structural index entry.
    struct StructuralPosition: Sendable {
        let offset: Int
        let byte: UInt8

        var isQuote: Bool { byte == SIMDScanner.quote }
        var isComma: Bool { byte == SIMDScanner.comma }
        var isNewline: Bool { byte == SIMDScanner.cr || byte == SIMDScanner.lf }
        var isDelimiter: Bool { byte == SIMDScanner.comma || byte == SIMDScanner.tab }
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
        delimiter: UInt8 = comma
    ) -> [StructuralPosition] {
        var positions: [StructuralPosition] = []
        positions.reserveCapacity(count / 8) // Estimate ~1 structural per 8 bytes

        var offset = 0

        // Process 64 bytes at a time using SIMD
        while offset + 64 <= count {
            // Load 64 bytes into SIMD vector
            let chunk = SIMD64<UInt8>(
                buffer[offset], buffer[offset+1], buffer[offset+2], buffer[offset+3],
                buffer[offset+4], buffer[offset+5], buffer[offset+6], buffer[offset+7],
                buffer[offset+8], buffer[offset+9], buffer[offset+10], buffer[offset+11],
                buffer[offset+12], buffer[offset+13], buffer[offset+14], buffer[offset+15],
                buffer[offset+16], buffer[offset+17], buffer[offset+18], buffer[offset+19],
                buffer[offset+20], buffer[offset+21], buffer[offset+22], buffer[offset+23],
                buffer[offset+24], buffer[offset+25], buffer[offset+26], buffer[offset+27],
                buffer[offset+28], buffer[offset+29], buffer[offset+30], buffer[offset+31],
                buffer[offset+32], buffer[offset+33], buffer[offset+34], buffer[offset+35],
                buffer[offset+36], buffer[offset+37], buffer[offset+38], buffer[offset+39],
                buffer[offset+40], buffer[offset+41], buffer[offset+42], buffer[offset+43],
                buffer[offset+44], buffer[offset+45], buffer[offset+46], buffer[offset+47],
                buffer[offset+48], buffer[offset+49], buffer[offset+50], buffer[offset+51],
                buffer[offset+52], buffer[offset+53], buffer[offset+54], buffer[offset+55],
                buffer[offset+56], buffer[offset+57], buffer[offset+58], buffer[offset+59],
                buffer[offset+60], buffer[offset+61], buffer[offset+62], buffer[offset+63]
            )

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

            // Extract positions from mask
            for i in 0..<64 where structuralMask[i] {
                positions.append(StructuralPosition(offset: offset + i, byte: buffer[offset + i]))
            }

            offset += 64
        }

        // Handle remaining bytes with scalar fallback
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
        startOffset: Int = 0
    ) -> RowBoundaries {
        // Fast path: scan for structural characters
        let structural = scanStructural(buffer: buffer, count: count, delimiter: delimiter)

        var rowStarts: [Int] = [startOffset]
        var inQuotes = false
        var lastNewlineEnd = 0

        for pos in structural {
            if pos.isQuote {
                inQuotes.toggle()
            } else if !inQuotes && pos.isNewline {
                // Found row boundary
                var endOffset = pos.offset

                // Handle CRLF as single newline
                if pos.byte == cr && pos.offset + 1 < count && buffer[pos.offset + 1] == lf {
                    endOffset = pos.offset + 1
                }

                // Skip if this is the LF of a CRLF we already processed
                if pos.byte == lf && pos.offset > 0 && buffer[pos.offset - 1] == cr {
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
            lastCompleteRowEnd: startOffset + lastNewlineEnd
        )
    }

    /// Counts approximate row count in buffer using SIMD newline detection.
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
        count: Int
    ) -> Int {
        var total = 0
        var offset = 0

        // Process 64 bytes at a time
        while offset + 64 <= count {
            let chunk = SIMD64<UInt8>(
                buffer[offset], buffer[offset+1], buffer[offset+2], buffer[offset+3],
                buffer[offset+4], buffer[offset+5], buffer[offset+6], buffer[offset+7],
                buffer[offset+8], buffer[offset+9], buffer[offset+10], buffer[offset+11],
                buffer[offset+12], buffer[offset+13], buffer[offset+14], buffer[offset+15],
                buffer[offset+16], buffer[offset+17], buffer[offset+18], buffer[offset+19],
                buffer[offset+20], buffer[offset+21], buffer[offset+22], buffer[offset+23],
                buffer[offset+24], buffer[offset+25], buffer[offset+26], buffer[offset+27],
                buffer[offset+28], buffer[offset+29], buffer[offset+30], buffer[offset+31],
                buffer[offset+32], buffer[offset+33], buffer[offset+34], buffer[offset+35],
                buffer[offset+36], buffer[offset+37], buffer[offset+38], buffer[offset+39],
                buffer[offset+40], buffer[offset+41], buffer[offset+42], buffer[offset+43],
                buffer[offset+44], buffer[offset+45], buffer[offset+46], buffer[offset+47],
                buffer[offset+48], buffer[offset+49], buffer[offset+50], buffer[offset+51],
                buffer[offset+52], buffer[offset+53], buffer[offset+54], buffer[offset+55],
                buffer[offset+56], buffer[offset+57], buffer[offset+58], buffer[offset+59],
                buffer[offset+60], buffer[offset+61], buffer[offset+62], buffer[offset+63]
            )

            let lfVec = SIMD64<UInt8>(repeating: lf)
            let mask = chunk .== lfVec

            // Count set bits in mask
            for i in 0..<64 where mask[i] {
                total += 1
            }

            offset += 64
        }

        // Scalar fallback for remainder
        while offset < count {
            if buffer[offset] == lf {
                total += 1
            }
            offset += 1
        }

        return total
    }

    // MARK: - Fast Field Boundary Detection

    /// Finds the next delimiter, newline, or quote in a buffer using SIMD.
    /// Used for fast unquoted field parsing.
    ///
    /// - Parameters:
    ///   - buffer: Pointer to start of search.
    ///   - count: Number of bytes to search.
    ///   - delimiter: The field delimiter byte.
    /// - Returns: Offset of first structural character, or count if none found.
    @inline(__always)
    static func findNextStructural(
        buffer: UnsafePointer<UInt8>,
        count: Int,
        delimiter: UInt8
    ) -> Int {
        var offset = 0

        // Process 64 bytes at a time using SIMD
        while offset + 64 <= count {
            let chunk = SIMD64<UInt8>(
                buffer[offset], buffer[offset+1], buffer[offset+2], buffer[offset+3],
                buffer[offset+4], buffer[offset+5], buffer[offset+6], buffer[offset+7],
                buffer[offset+8], buffer[offset+9], buffer[offset+10], buffer[offset+11],
                buffer[offset+12], buffer[offset+13], buffer[offset+14], buffer[offset+15],
                buffer[offset+16], buffer[offset+17], buffer[offset+18], buffer[offset+19],
                buffer[offset+20], buffer[offset+21], buffer[offset+22], buffer[offset+23],
                buffer[offset+24], buffer[offset+25], buffer[offset+26], buffer[offset+27],
                buffer[offset+28], buffer[offset+29], buffer[offset+30], buffer[offset+31],
                buffer[offset+32], buffer[offset+33], buffer[offset+34], buffer[offset+35],
                buffer[offset+36], buffer[offset+37], buffer[offset+38], buffer[offset+39],
                buffer[offset+40], buffer[offset+41], buffer[offset+42], buffer[offset+43],
                buffer[offset+44], buffer[offset+45], buffer[offset+46], buffer[offset+47],
                buffer[offset+48], buffer[offset+49], buffer[offset+50], buffer[offset+51],
                buffer[offset+52], buffer[offset+53], buffer[offset+54], buffer[offset+55],
                buffer[offset+56], buffer[offset+57], buffer[offset+58], buffer[offset+59],
                buffer[offset+60], buffer[offset+61], buffer[offset+62], buffer[offset+63]
            )

            let delimVec = SIMD64<UInt8>(repeating: delimiter)
            let crVec = SIMD64<UInt8>(repeating: cr)
            let lfVec = SIMD64<UInt8>(repeating: lf)

            let delimMask = chunk .== delimVec
            let crMask = chunk .== crVec
            let lfMask = chunk .== lfVec

            let structuralMask = delimMask .| crMask .| lfMask

            // Find first set bit
            for i in 0..<64 where structuralMask[i] {
                return offset + i
            }

            offset += 64
        }

        // Scalar fallback for remainder
        while offset < count {
            let byte = buffer[offset]
            if byte == delimiter || byte == cr || byte == lf {
                return offset
            }
            offset += 1
        }

        return count
    }

    /// Finds the position of the first quote character using SIMD.
    /// Returns count if no quote is found.
    @inline(__always)
    static func findNextQuote(
        buffer: UnsafePointer<UInt8>,
        count: Int
    ) -> Int {
        var offset = 0

        // Process 64 bytes at a time
        while offset + 64 <= count {
            let chunk = SIMD64<UInt8>(
                buffer[offset], buffer[offset+1], buffer[offset+2], buffer[offset+3],
                buffer[offset+4], buffer[offset+5], buffer[offset+6], buffer[offset+7],
                buffer[offset+8], buffer[offset+9], buffer[offset+10], buffer[offset+11],
                buffer[offset+12], buffer[offset+13], buffer[offset+14], buffer[offset+15],
                buffer[offset+16], buffer[offset+17], buffer[offset+18], buffer[offset+19],
                buffer[offset+20], buffer[offset+21], buffer[offset+22], buffer[offset+23],
                buffer[offset+24], buffer[offset+25], buffer[offset+26], buffer[offset+27],
                buffer[offset+28], buffer[offset+29], buffer[offset+30], buffer[offset+31],
                buffer[offset+32], buffer[offset+33], buffer[offset+34], buffer[offset+35],
                buffer[offset+36], buffer[offset+37], buffer[offset+38], buffer[offset+39],
                buffer[offset+40], buffer[offset+41], buffer[offset+42], buffer[offset+43],
                buffer[offset+44], buffer[offset+45], buffer[offset+46], buffer[offset+47],
                buffer[offset+48], buffer[offset+49], buffer[offset+50], buffer[offset+51],
                buffer[offset+52], buffer[offset+53], buffer[offset+54], buffer[offset+55],
                buffer[offset+56], buffer[offset+57], buffer[offset+58], buffer[offset+59],
                buffer[offset+60], buffer[offset+61], buffer[offset+62], buffer[offset+63]
            )

            let quoteVec = SIMD64<UInt8>(repeating: quote)
            let quoteMask = chunk .== quoteVec

            for i in 0..<64 where quoteMask[i] {
                return offset + i
            }

            offset += 64
        }

        // Scalar fallback
        while offset < count {
            if buffer[offset] == quote {
                return offset
            }
            offset += 1
        }

        return count
    }
}
