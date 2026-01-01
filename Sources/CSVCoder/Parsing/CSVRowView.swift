//
//  CSVRowView.swift
//  CSVCoder
//
//  A zero-copy view into a single CSV row within a raw UTF-8 buffer.
//

import Foundation

// MARK: - CSVRowView

/// A zero-copy view into a single CSV row within a raw UTF-8 buffer.
///
/// `CSVRowView` provides efficient access to field data without allocating copies.
/// It stores byte offsets and lengths rather than string values, enabling
/// high-performance parsing of large CSV files.
///
/// ## Thread Safety
///
/// `CSVRowView` is **not** `Sendable` because it references a borrowed buffer
/// that must remain valid for the view's lifetime. Always use within the closure
/// scope of ``CSVParser/parse(data:delimiter:body:)``.
///
/// ## Usage
///
/// ```swift
/// CSVParser.parse(data: csvData) { parser in
///     for row in parser {
///         for i in 0..<row.count {
///             if let value = row.string(at: i) {
///                 print(value)
///             }
///         }
///     }
/// }
/// ```
///
/// ## Performance Notes
///
/// - Field access via ``string(at:)`` is O(1) for unquoted fields
/// - Quoted fields with escaped quotes (`""`) require O(n) unescaping
/// - Use ``getBytes(at:)`` for maximum performance when UTF-8 bytes suffice
public struct CSVRowView {
    // MARK: Lifecycle

    /// Creates a row view with the given buffer and field metadata.
    public init(
        buffer: UnsafeBufferPointer<UInt8>,
        fieldStarts: [Int],
        fieldLengths: [Int],
        fieldQuoted: [Bool],
        fieldHasEscapedQuote: [Bool],
        hasUnterminatedQuote: Bool,
        hasQuoteInUnquotedField: Bool,
    ) {
        self.buffer = buffer
        self.fieldStarts = fieldStarts
        self.fieldLengths = fieldLengths
        self.fieldQuoted = fieldQuoted
        self.fieldHasEscapedQuote = fieldHasEscapedQuote
        self.hasUnterminatedQuote = hasUnterminatedQuote
        self.hasQuoteInUnquotedField = hasQuoteInUnquotedField
    }

    // MARK: Public

    /// Reference to the full buffer (owned elsewhere).
    public let buffer: UnsafeBufferPointer<UInt8>

    /// Offsets of field starts within the buffer.
    public let fieldStarts: [Int]

    /// Lengths of each field.
    public let fieldLengths: [Int]

    /// Whether each field was quoted (needs unescaping).
    public let fieldQuoted: [Bool]

    /// Whether each field contains escaped quotes ("" that need unescaping.
    public let fieldHasEscapedQuote: [Bool]

    /// Whether any field has an unterminated quote.
    public let hasUnterminatedQuote: Bool

    /// Whether any unquoted field contains a quote character (RFC 4180 violation).
    public let hasQuoteInUnquotedField: Bool

    /// The number of fields in this row.
    public var count: Int { fieldStarts.count }

    /// Returns the raw UTF-8 bytes for the field at the given index.
    ///
    /// This method provides zero-copy access to field data, useful when
    /// you need to perform custom parsing or validation without allocating strings.
    ///
    /// - Parameter index: The zero-based field index.
    /// - Returns: A buffer pointer to the field's UTF-8 bytes, or an empty buffer if out of bounds.
    /// - Complexity: O(1)
    ///
    /// - Warning: The returned buffer is only valid while the parent `CSVParser`'s
    ///   data remains in scope. Do not store the buffer beyond the parsing closure.
    public func getBytes(at index: Int) -> UnsafeBufferPointer<UInt8> {
        let start = fieldStarts[index]
        let length = fieldLengths[index]
        guard start + length <= buffer.count else { return UnsafeBufferPointer(start: nil, count: 0) }
        return UnsafeBufferPointer(start: buffer.baseAddress?.advanced(by: start), count: length)
    }

    /// Decodes and returns the string value for the field at the given index.
    ///
    /// Handles RFC 4180 quote unescaping automatically:
    /// - Quoted fields have outer quotes stripped
    /// - Escaped quotes (`""`) are converted to single quotes (`"`)
    ///
    /// - Parameter index: The zero-based field index.
    /// - Returns: The decoded string value, or `nil` if the index is out of bounds.
    /// - Complexity: O(1) for unquoted fields; O(n) for quoted fields with escaped quotes.
    public func string(at index: Int) -> String? {
        string(at: index, encoding: .utf8)
    }

    /// Decodes and returns the string value for the field at the given index using the specified encoding.
    ///
    /// Handles RFC 4180 quote unescaping automatically:
    /// - Quoted fields have outer quotes stripped
    /// - Escaped quotes (`""`) are converted to single quotes (`"`)
    ///
    /// - Parameters:
    ///   - index: The zero-based field index.
    ///   - encoding: The string encoding to use for conversion. For best performance, use `.utf8`.
    /// - Returns: The decoded string value, or `nil` if the index is out of bounds or conversion fails.
    /// - Complexity: O(1) for unquoted UTF-8 fields; O(n) for quoted fields with escaped quotes or non-UTF-8 encodings.
    public func string(at index: Int, encoding: String.Encoding) -> String? {
        guard index < fieldStarts.count else { return nil }

        let start = fieldStarts[index]
        let length = fieldLengths[index]
        let isQuoted = fieldQuoted[index]
        let hasEscapedQuote = fieldHasEscapedQuote[index]

        guard let base = buffer.baseAddress else { return nil }

        let ptr = base.advanced(by: start)
        let fieldBuffer = UnsafeBufferPointer(start: ptr, count: length)

        // Fast path for UTF-8 (most common case)
        if encoding == .utf8 {
            guard isQuoted, hasEscapedQuote else {
                // No unescaping needed - direct decode
                return String(decoding: fieldBuffer, as: UTF8.self)
            }
            // Use zero-allocation unescaper
            return CSVUnescaper.unescape(buffer: fieldBuffer)
        }

        // Non-UTF-8 encoding path (ASCII-compatible encodings like ISO-8859-1, Windows-1252)
        if isQuoted, hasEscapedQuote {
            return CSVUnescaper.unescape(buffer: fieldBuffer, encoding: encoding)
        }

        let data = Data(bytes: ptr, count: length)
        return String(data: data, encoding: encoding)
    }
}
