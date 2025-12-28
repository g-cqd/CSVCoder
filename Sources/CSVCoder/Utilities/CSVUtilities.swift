//
//  CSVUtilities.swift
//  CSVCoder
//
//  Shared utilities for CSV parsing and encoding.
//  Consolidates BOM handling, field escaping, and row building.
//

import Foundation

// MARK: - BOM Handling

/// Shared utilities for CSV operations.
enum CSVUtilities {
    /// UTF-8 BOM bytes (EF BB BF).
    static let utf8BOM: (UInt8, UInt8, UInt8) = (0xEF, 0xBB, 0xBF)

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
}

// MARK: - Field Escaping

/// RFC 4180 compliant field escaper.
/// Handles quoting of fields containing delimiters, quotes, or newlines.
enum CSVFieldEscaper {
    // ASCII constants
    private static let quote: UInt8 = 0x22      // "
    private static let lf: UInt8 = 0x0A         // \n
    private static let cr: UInt8 = 0x0D         // \r

    /// Checks if a field needs quoting per RFC 4180.
    /// - Parameters:
    ///   - bytes: UTF-8 bytes of the field value.
    ///   - delimiter: The field delimiter byte.
    /// - Returns: `true` if the field contains characters requiring quoting.
    @inline(__always)
    static func needsQuoting(_ bytes: [UInt8], delimiter: UInt8) -> Bool {
        for byte in bytes {
            if byte == delimiter || byte == quote || byte == lf || byte == cr {
                return true
            }
        }
        return false
    }

    /// SIMD-accelerated quoting check for larger fields.
    /// Falls back to scalar check for small fields.
    /// - Parameters:
    ///   - bytes: UTF-8 bytes of the field value.
    ///   - delimiter: The field delimiter byte.
    /// - Returns: `true` if the field contains characters requiring quoting.
    static func needsQuotingSIMD(_ bytes: [UInt8], delimiter: UInt8) -> Bool {
        guard bytes.count >= 64 else {
            return needsQuoting(bytes, delimiter: delimiter)
        }

        return bytes.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return false }
            return SIMDScanner.needsQuoting(buffer: baseAddress, count: buffer.count, delimiter: delimiter)
        }
    }

    /// Appends an escaped field to a byte buffer.
    /// Quotes the field if it contains delimiters, quotes, or newlines.
    /// - Parameters:
    ///   - value: The string value to escape.
    ///   - buffer: The output buffer to append to.
    ///   - delimiter: The field delimiter byte.
    static func appendEscaped(_ value: String, to buffer: inout [UInt8], delimiter: UInt8) {
        let utf8Bytes = Array(value.utf8)

        // Determine if quoting is needed
        let needsQuotes: Bool
        if utf8Bytes.count >= 64 {
            needsQuotes = needsQuotingSIMD(utf8Bytes, delimiter: delimiter)
        } else {
            needsQuotes = needsQuoting(utf8Bytes, delimiter: delimiter)
        }

        if needsQuotes {
            buffer.append(quote)
            for byte in utf8Bytes {
                if byte == quote {
                    buffer.append(quote) // Escape quote by doubling
                }
                buffer.append(byte)
            }
            buffer.append(quote)
        } else {
            buffer.append(contentsOf: utf8Bytes)
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
