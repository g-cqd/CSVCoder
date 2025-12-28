//
//  CSVUtilities.swift
//  CSVCoder
//
//  Shared utilities for CSV parsing and encoding.
//  Consolidates BOM handling, field escaping, and row building.
//

import Foundation

// MARK: - BOM Handling & Encoding Utilities

/// Shared utilities for CSV operations.
enum CSVUtilities {
    /// UTF-8 BOM bytes (EF BB BF).
    static let utf8BOM: (UInt8, UInt8, UInt8) = (0xEF, 0xBB, 0xBF)

    /// UTF-16 LE BOM bytes (FF FE).
    static let utf16LEBOM: (UInt8, UInt8) = (0xFF, 0xFE)

    /// UTF-16 BE BOM bytes (FE FF).
    static let utf16BEBOM: (UInt8, UInt8) = (0xFE, 0xFF)

    /// UTF-32 LE BOM bytes (FF FE 00 00).
    static let utf32LEBOM: (UInt8, UInt8, UInt8, UInt8) = (0xFF, 0xFE, 0x00, 0x00)

    /// UTF-32 BE BOM bytes (00 00 FE FF).
    static let utf32BEBOM: (UInt8, UInt8, UInt8, UInt8) = (0x00, 0x00, 0xFE, 0xFF)

    /// Returns the byte offset to skip UTF-8 BOM if present.
    /// - Parameter bytes: The buffer to check.
    /// - Returns: 3 if BOM is present, 0 otherwise.
    @inline(__always)
    static func bomOffset(in bytes: UnsafeBufferPointer<UInt8>) -> Int {
        guard bytes.count >= 3,
              bytes[0] == utf8BOM.0,
              bytes[1] == utf8BOM.1,
              bytes[2] == utf8BOM.2 else {
            return 0
        }
        return 3
    }

    /// Returns the byte offset to skip UTF-8 BOM if present.
    /// - Parameters:
    ///   - baseAddress: Pointer to the start of the buffer.
    ///   - count: Number of bytes in the buffer.
    /// - Returns: 3 if BOM is present, 0 otherwise.
    @inline(__always)
    static func bomOffset(baseAddress: UnsafePointer<UInt8>, count: Int) -> Int {
        guard count >= 3,
              baseAddress[0] == utf8BOM.0,
              baseAddress[1] == utf8BOM.1,
              baseAddress[2] == utf8BOM.2 else {
            return 0
        }
        return 3
    }

    /// Detects encoding from BOM and returns the encoding and byte offset to skip.
    /// - Parameter data: The data to check for BOM.
    /// - Returns: A tuple of detected encoding (or nil if no BOM) and the byte offset to skip.
    static func detectBOM(in data: Data) -> (encoding: String.Encoding?, offset: Int) {
        guard data.count >= 2 else { return (nil, 0) }

        // Check UTF-32 first (4-byte BOM, but first 2 bytes overlap with UTF-16 LE)
        if data.count >= 4 {
            if data[0] == utf32LEBOM.0 && data[1] == utf32LEBOM.1 &&
               data[2] == utf32LEBOM.2 && data[3] == utf32LEBOM.3 {
                return (.utf32LittleEndian, 4)
            }
            if data[0] == utf32BEBOM.0 && data[1] == utf32BEBOM.1 &&
               data[2] == utf32BEBOM.2 && data[3] == utf32BEBOM.3 {
                return (.utf32BigEndian, 4)
            }
        }

        // Check UTF-8 (3-byte BOM)
        if data.count >= 3 {
            if data[0] == utf8BOM.0 && data[1] == utf8BOM.1 && data[2] == utf8BOM.2 {
                return (.utf8, 3)
            }
        }

        // Check UTF-16 (2-byte BOM)
        if data[0] == utf16LEBOM.0 && data[1] == utf16LEBOM.1 {
            return (.utf16LittleEndian, 2)
        }
        if data[0] == utf16BEBOM.0 && data[1] == utf16BEBOM.1 {
            return (.utf16BigEndian, 2)
        }

        return (nil, 0)
    }

    /// Checks if an encoding uses ASCII-compatible byte values for structural characters.
    ///
    /// ASCII-compatible encodings use the same byte values (0x00-0x7F) for ASCII characters,
    /// which means CSV structural characters (comma, quote, CR, LF) have identical byte representations.
    /// This allows the parser to operate on raw bytes and only use encoding for string conversion.
    ///
    /// - Parameter encoding: The encoding to check.
    /// - Returns: `true` if the encoding is ASCII-compatible.
    @inline(__always)
    static func isASCIICompatible(_ encoding: String.Encoding) -> Bool {
        switch encoding {
        case .utf8, .ascii, .isoLatin1, .isoLatin2,
             .windowsCP1250, .windowsCP1251, .windowsCP1252,
             .windowsCP1253, .windowsCP1254,
             .macOSRoman, .nextstep:
            return true
        case .utf16, .utf16BigEndian, .utf16LittleEndian,
             .utf32, .utf32BigEndian, .utf32LittleEndian,
             .unicode:
            return false
        default:
            // For unknown encodings, assume not ASCII-compatible for safety
            return false
        }
    }

    /// Transcodes data from a non-ASCII-compatible encoding to UTF-8.
    ///
    /// For encodings like UTF-16 and UTF-32, the byte structure differs from ASCII,
    /// so we must convert to String first, then to UTF-8 bytes for parsing.
    ///
    /// - Parameters:
    ///   - data: The source data.
    ///   - encoding: The source encoding.
    /// - Returns: UTF-8 encoded data, or nil if conversion fails.
    static func transcodeToUTF8(_ data: Data, from encoding: String.Encoding) -> Data? {
        // Try to detect and skip BOM
        let (detectedEncoding, bomOffset) = detectBOM(in: data)
        let effectiveEncoding = detectedEncoding ?? encoding
        let dataWithoutBOM = bomOffset > 0 ? data.dropFirst(bomOffset) : data

        guard let string = String(data: Data(dataWithoutBOM), encoding: effectiveEncoding) else {
            return nil
        }
        return string.data(using: .utf8)
    }
}

// MARK: - Field Unescaping

/// Zero-allocation field unescaper for quoted CSV fields.
/// Converts `""` sequences to single `"` without intermediate string allocations.
enum CSVUnescaper: Sendable {
    private static let quote: UInt8 = 0x22  // "

    /// Checks if a buffer contains escaped quotes (`""`).
    /// Uses SWAR for medium-sized buffers, SIMD for large ones.
    ///
    /// - Parameters:
    ///   - buffer: Pointer to UTF-8 bytes.
    ///   - count: Number of bytes to scan.
    /// - Returns: `true` if the buffer contains `""` sequences.
    @inline(__always)
    static func hasEscapedQuotes(buffer: UnsafePointer<UInt8>, count: Int) -> Bool {
        guard count >= 2 else { return false }

        var offset = 0

        // SWAR check for 8+ bytes: look for consecutive quotes
        while offset + 9 <= count {
            let word = SWARUtils.load(buffer.advanced(by: offset))
            let nextWord = SWARUtils.load(buffer.advanced(by: offset + 1))

            // Find quotes in both positions
            let quoteMask1 = SWARUtils.findByte(word, target: quote)
            let quoteMask2 = SWARUtils.findByte(nextWord, target: quote)

            // Consecutive quotes exist if we have a quote followed by a quote
            if quoteMask1 != 0 && quoteMask2 != 0 {
                // Check byte-by-byte in this region
                for i in 0..<8 {
                    if buffer[offset + i] == quote && buffer[offset + i + 1] == quote {
                        return true
                    }
                }
            }
            offset += 8
        }

        // Scalar fallback for remainder
        while offset < count - 1 {
            if buffer[offset] == quote && buffer[offset + 1] == quote {
                return true
            }
            offset += 1
        }

        return false
    }

    /// Unescapes a quoted CSV field, converting `""` to `"`.
    /// Returns the string directly if no escaping is needed (fast path).
    ///
    /// - Parameter buffer: Buffer containing the field content (without outer quotes).
    /// - Returns: The unescaped string.
    static func unescape(buffer: UnsafeBufferPointer<UInt8>) -> String {
        guard let baseAddress = buffer.baseAddress else {
            return ""
        }

        let count = buffer.count

        // Fast path: no escaped quotes
        if !hasEscapedQuotes(buffer: baseAddress, count: count) {
            return String(decoding: buffer, as: UTF8.self)
        }

        // Slow path: build unescaped result
        var result = [UInt8]()
        result.reserveCapacity(count)

        var i = 0
        while i < count {
            let byte = baseAddress[i]
            if byte == quote && i + 1 < count && baseAddress[i + 1] == quote {
                // Escaped quote: append single quote, skip both
                result.append(quote)
                i += 2
            } else {
                result.append(byte)
                i += 1
            }
        }

        return String(decoding: result, as: UTF8.self)
    }

    /// Unescapes a quoted CSV field with a specific encoding.
    ///
    /// - Parameters:
    ///   - buffer: Buffer containing the field content (without outer quotes).
    ///   - encoding: The string encoding to use.
    /// - Returns: The unescaped string, or nil if encoding fails.
    static func unescape(buffer: UnsafeBufferPointer<UInt8>, encoding: String.Encoding) -> String? {
        guard let baseAddress = buffer.baseAddress else {
            return ""
        }

        let count = buffer.count

        // For UTF-8, use optimized path
        if encoding == .utf8 {
            return unescape(buffer: buffer)
        }

        // For other encodings, convert first then unescape
        let data = Data(bytes: baseAddress, count: count)
        guard let str = String(data: data, encoding: encoding) else {
            return nil
        }

        // Check if unescaping is needed
        if !hasEscapedQuotes(buffer: baseAddress, count: count) {
            return str
        }

        return str.replacingOccurrences(of: "\"\"", with: "\"")
    }
}

// MARK: - Field Escaping

/// RFC 4180 compliant field escaper.
/// Handles quoting of fields containing delimiters, quotes, or newlines.
enum CSVFieldEscaper: Sendable {
    // ASCII constants
    private static let quote: UInt8 = 0x22      // "
    private static let lf: UInt8 = 0x0A         // \n
    private static let cr: UInt8 = 0x0D         // \r

    /// Checks if a field needs quoting per RFC 4180 using raw pointer.
    /// Uses SWAR for medium-sized fields, SIMD for large ones.
    ///
    /// - Parameters:
    ///   - buffer: Pointer to UTF-8 bytes.
    ///   - count: Number of bytes.
    ///   - delimiter: The field delimiter byte.
    /// - Returns: `true` if the field contains characters requiring quoting.
    @inline(__always)
    static func needsQuoting(buffer: UnsafePointer<UInt8>, count: Int, delimiter: UInt8) -> Bool {
        // Use SIMD for large fields
        if count >= 64 {
            return SIMDScanner.needsQuoting(buffer: buffer, count: count, delimiter: delimiter)
        }

        // SWAR for medium fields (8-63 bytes)
        var offset = 0
        while offset + 8 <= count {
            let word = SWARUtils.load(buffer.advanced(by: offset))
            if SWARUtils.hasAnyByte(word, quote, delimiter, lf, cr) {
                return true
            }
            offset += 8
        }

        // Scalar fallback for remainder
        while offset < count {
            let byte = buffer[offset]
            if byte == delimiter || byte == quote || byte == lf || byte == cr {
                return true
            }
            offset += 1
        }

        return false
    }

    /// Checks if a field needs quoting per RFC 4180.
    /// - Parameters:
    ///   - bytes: UTF-8 bytes of the field value.
    ///   - delimiter: The field delimiter byte.
    /// - Returns: `true` if the field contains characters requiring quoting.
    @inline(__always)
    static func needsQuoting(_ bytes: [UInt8], delimiter: UInt8) -> Bool {
        bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return false }
            return needsQuoting(buffer: base, count: buffer.count, delimiter: delimiter)
        }
    }

    /// SIMD-accelerated quoting check for larger fields.
    /// Falls back to scalar check for small fields.
    /// - Parameters:
    ///   - bytes: UTF-8 bytes of the field value.
    ///   - delimiter: The field delimiter byte.
    /// - Returns: `true` if the field contains characters requiring quoting.
    static func needsQuotingSIMD(_ bytes: [UInt8], delimiter: UInt8) -> Bool {
        needsQuoting(bytes, delimiter: delimiter)
    }

    /// Appends an escaped field to a byte buffer.
    /// Quotes the field if it contains delimiters, quotes, or newlines.
    /// Uses contiguous UTF-8 storage for efficient access.
    ///
    /// - Parameters:
    ///   - value: The string value to escape.
    ///   - buffer: The output buffer to append to.
    ///   - delimiter: The field delimiter byte.
    static func appendEscaped(_ value: String, to buffer: inout [UInt8], delimiter: UInt8) {
        // Use withContiguousStorageIfAvailable for zero-copy when possible
        var mutableValue = value
        let handled = mutableValue.withUTF8 { utf8 -> Bool in
            guard let baseAddress = utf8.baseAddress else {
                return true  // Empty string - handled
            }

            let count = utf8.count
            let needsQuotes = needsQuoting(buffer: baseAddress, count: count, delimiter: delimiter)

            if needsQuotes {
                buffer.append(quote)
                for i in 0..<count {
                    let byte = baseAddress[i]
                    if byte == quote {
                        buffer.append(quote) // Escape quote by doubling
                    }
                    buffer.append(byte)
                }
                buffer.append(quote)
            } else {
                buffer.append(contentsOf: UnsafeBufferPointer(start: baseAddress, count: count))
            }
            return true
        }

        // Fallback should never happen after withUTF8, but just in case
        if !handled {
            let utf8Bytes = Array(value.utf8)
            let needsQuotes = needsQuoting(utf8Bytes, delimiter: delimiter)
            if needsQuotes {
                buffer.append(quote)
                for byte in utf8Bytes {
                    if byte == quote {
                        buffer.append(quote)
                    }
                    buffer.append(byte)
                }
                buffer.append(quote)
            } else {
                buffer.append(contentsOf: utf8Bytes)
            }
        }
    }

    /// Escapes a field value for CSV output per RFC 4180.
    /// Returns a quoted string if the value contains special characters.
    /// - Parameters:
    ///   - value: The string value to escape.
    ///   - delimiter: The delimiter character.
    /// - Returns: The escaped field string.
    static func escapeField(_ value: String, delimiter: Character) -> String {
        let delimString = String(delimiter)

        let needsQuoting = value.contains(delimString) ||
                          value.contains("\"") ||
                          value.contains("\n") ||
                          value.contains("\r")

        if needsQuoting {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }

        return value
    }
}

// MARK: - Row Builder

/// A builder for constructing CSV rows directly into byte buffers.
/// Avoids intermediate String allocations for better performance.
struct CSVRowBuilder: Sendable {
    let delimiter: UInt8
    let lineEnding: [UInt8]

    /// Creates a row builder with the specified delimiter and line ending.
    /// - Parameters:
    ///   - delimiter: The field delimiter character.
    ///   - lineEnding: The line ending style.
    init(delimiter: Character, lineEnding: CSVEncoder.LineEnding) {
        self.delimiter = delimiter.asciiValue ?? 0x2C
        self.lineEnding = Array(lineEnding.rawValue.utf8)
    }

    /// Builds a row from field values into the output buffer.
    /// - Parameters:
    ///   - fields: The field values for this row.
    ///   - buffer: The output buffer to append to.
    func buildRow(_ fields: [String], into buffer: inout [UInt8]) {
        for (index, field) in fields.enumerated() {
            if index > 0 {
                buffer.append(delimiter)
            }
            CSVFieldEscaper.appendEscaped(field, to: &buffer, delimiter: delimiter)
        }
        buffer.append(contentsOf: lineEnding)
    }

    /// Builds a header row from field names.
    /// - Parameters:
    ///   - headers: The header names.
    ///   - buffer: The output buffer to append to.
    func buildHeader(_ headers: [String], into buffer: inout [UInt8]) {
        buildRow(headers, into: &buffer)
    }

    /// Builds a row and returns it as a new byte array.
    /// - Parameter fields: The field values for this row.
    /// - Returns: The row as a byte array.
    func buildRow(_ fields: [String]) -> [UInt8] {
        var buffer: [UInt8] = []
        buffer.reserveCapacity(fields.count * 32)
        buildRow(fields, into: &buffer)
        return buffer
    }

    /// Builds a header row and returns it as a new byte array.
    /// - Parameter headers: The header names.
    /// - Returns: The header row as a byte array.
    func buildHeader(_ headers: [String]) -> [UInt8] {
        buildRow(headers)
    }
}
