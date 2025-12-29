//
//  CSVParser.swift
//  CSVCoder
//
//  Zero-copy CSV parser operating directly on UTF-8 bytes.
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
            if isQuoted, hasEscapedQuote {
                // Use zero-allocation unescaper
                return CSVUnescaper.unescape(buffer: fieldBuffer)
            } else {
                // No unescaping needed - direct decode
                return String(decoding: fieldBuffer, as: UTF8.self)
            }
        }

        // Non-UTF-8 encoding path (ASCII-compatible encodings like ISO-8859-1, Windows-1252)
        if isQuoted, hasEscapedQuote {
            return CSVUnescaper.unescape(buffer: fieldBuffer, encoding: encoding)
        }

        let data = Data(bytes: ptr, count: length)
        return String(data: data, encoding: encoding)
    }
}

// MARK: - CSVParser

/// A high-performance, zero-copy CSV parser operating directly on UTF-8 bytes.
///
/// `CSVParser` implements RFC 4180 compliant parsing with SIMD acceleration
/// for large fields. It produces ``CSVRowView`` instances that reference the
/// original buffer without copying data.
///
/// ## Safe Usage Pattern
///
/// Always use the static ``parse(data:delimiter:body:)`` method to ensure
/// buffer lifetime safety:
///
/// ```swift
/// let results = CSVParser.parse(data: csvData) { parser in
///     parser.map { row in
///         row.string(at: 0) ?? ""
///     }
/// }
/// ```
///
/// ## Direct Initialization
///
/// For advanced use cases where you manage buffer lifetime manually:
///
/// ```swift
/// data.withUnsafeBytes { buffer in
///     let parser = CSVParser(
///         buffer: buffer.bindMemory(to: UInt8.self),
///         delimiter: 0x2C  // comma
///     )
///     for row in parser {
///         // Process row
///     }
/// }
/// ```
///
/// ## RFC 4180 Compliance
///
/// The parser handles:
/// - Quoted fields with embedded delimiters, newlines, and quotes
/// - Escaped quotes (`""` → `"`)
/// - Both LF and CRLF line endings
/// - UTF-8 encoded content
///
/// ## Performance
///
/// - Uses SIMD acceleration for fields ≥64 bytes
/// - Uses SWAR acceleration for fields 8-63 bytes
/// - O(n) parsing where n is the total byte count
///
/// ## Thread Safety
///
/// `CSVParser` and its iterator are not `Sendable`. The parser borrows
/// the underlying buffer and must be used within the same isolation context.
public struct CSVParser: Sequence {
    // MARK: Lifecycle

    /// Creates a parser for the given buffer with the specified delimiter.
    ///
    /// - Parameters:
    ///   - buffer: A pointer to UTF-8 encoded CSV data. The buffer must remain
    ///     valid for the lifetime of the parser and any ``CSVRowView`` instances it produces.
    ///   - delimiter: The ASCII byte value of the field delimiter (e.g., `0x2C` for comma).
    ///
    /// - Warning: Prefer using ``parse(data:delimiter:body:)`` unless you need
    ///   manual buffer lifetime management.
    public init(
        buffer: UnsafeBufferPointer<UInt8>,
        delimiter: UInt8,
    ) {
        self.buffer = buffer
        self.delimiter = delimiter
    }

    // MARK: Public

    /// An iterator that produces ``CSVRowView`` instances for each row in the CSV data.
    public struct Iterator: IteratorProtocol {
        // MARK: Lifecycle

        init(parser: CSVParser) {
            self.parser = parser
        }

        // MARK: Public

        /// Advances to and returns the next row, or `nil` if no more rows exist.
        public mutating func next() -> CSVRowView? {
            guard offset < parser.buffer.count else {
                return nil
            }

            var fieldStarts: [Int] = []
            var fieldLengths: [Int] = []
            var fieldQuoted: [Bool] = []
            var fieldHasEscapedQuote: [Bool] = []
            var hasUnterminatedQuote = false
            var hasQuoteInUnquotedField = false

            var rowEnded = false

            while !rowEnded && offset < parser.buffer.count {
                // Parse Field
                let result = parser.parseField(from: offset)
                fieldStarts.append(result.start)
                fieldLengths.append(result.length)
                fieldQuoted.append(result.quoted)
                fieldHasEscapedQuote.append(result.hasEscapedQuote)

                if result.unterminated {
                    hasUnterminatedQuote = true
                }
                if result.hasQuoteInUnquoted {
                    hasQuoteInUnquotedField = true
                }
                offset = result.nextOffset
                rowEnded = result.isRowEnd
            }

            // Handle trailing empty line (EOF after newline)
            if fieldStarts
                .isEmpty || (fieldStarts.count == 1 && fieldLengths[0] == 0 && offset >= parser.buffer.count) {
                if offset >= parser.buffer.count, fieldStarts.isEmpty {
                    return nil
                }
                // If it's a single empty field at EOF, usually we skip it if it was just a newline
                if fieldStarts.count == 1, fieldLengths[0] == 0 {
                    return nil
                }
            }

            return CSVRowView(
                buffer: parser.buffer,
                fieldStarts: fieldStarts,
                fieldLengths: fieldLengths,
                fieldQuoted: fieldQuoted,
                fieldHasEscapedQuote: fieldHasEscapedQuote,
                hasUnterminatedQuote: hasUnterminatedQuote,
                hasQuoteInUnquotedField: hasQuoteInUnquotedField,
            )
        }

        // MARK: Internal

        let parser: CSVParser
        var offset: Int = 0
    }

    /// The underlying UTF-8 byte buffer being parsed.
    public let buffer: UnsafeBufferPointer<UInt8>

    /// The ASCII byte value of the field delimiter (default: comma `0x2C`).
    public let delimiter: UInt8

    /// Safely parses CSV data within a closure scope, ensuring buffer validity.
    /// This ensures the parser's underlying buffer remains valid during iteration.
    ///
    /// - Parameters:
    ///   - data: The CSV data to parse.
    ///   - delimiter: The field delimiter (default comma).
    ///   - body: A closure that receives the parser.
    /// - Returns: The result of the body closure.
    public static func parse<R>(
        data: Data,
        delimiter: UInt8 = 0x2C,
        body: (CSVParser) throws -> R,
    ) rethrows -> R {
        try data.withUnsafeBytes { buffer in
            let parser = CSVParser(
                buffer: buffer.bindMemory(to: UInt8.self),
                delimiter: delimiter,
            )
            return try body(parser)
        }
    }

    /// Creates an iterator for traversing CSV rows.
    public func makeIterator() -> Iterator {
        Iterator(parser: self)
    }

    /// Parses the entire buffer and returns all rows as an array.
    ///
    /// This is a convenience method that collects all ``CSVRowView`` instances
    /// into an array. For large files, consider iterating directly to avoid
    /// holding all row metadata in memory simultaneously.
    ///
    /// - Returns: An array of ``CSVRowView`` instances, one per CSV row.
    /// - Complexity: O(n) where n is the total byte count.
    public func parse() -> [CSVRowView] {
        var rows: [CSVRowView] = []
        for row in self {
            rows.append(row)
        }
        return rows
    }

    // MARK: Internal

    /// Internal result type for single-field parsing.
    struct FieldResult {
        let start: Int
        let length: Int
        let quoted: Bool
        let nextOffset: Int
        let isRowEnd: Bool
        let unterminated: Bool
        let hasQuoteInUnquoted: Bool
        let hasEscapedQuote: Bool
    }

    // MARK: Fileprivate

    // ASCII constants
    fileprivate static let quote: UInt8 = 0x22 // "
    fileprivate static let cr: UInt8 = 0x0D // \r
    fileprivate static let lf: UInt8 = 0x0A // \n

    // Returns: (contentStart, contentLength, isQuoted, nextOffset, isRowEnd, isUnterminatedQuote, hasQuoteInUnquoted)
    @inline(__always)
    fileprivate func parseField(from startOffset: Int) -> FieldResult {
        var cursor = startOffset
        let count = buffer.count
        guard cursor < count else {
            return FieldResult(
                start: cursor,
                length: 0,
                quoted: false,
                nextOffset: cursor,
                isRowEnd: true,
                unterminated: false,
                hasQuoteInUnquoted: false,
                hasEscapedQuote: false,
            )
        }

        let c = buffer[cursor]

        if c == CSVParser.quote {
            // Quoted Field
            let contentStart = cursor + 1
            cursor += 1 // Skip opening quote
            var hasEscapedQuote = false

            while cursor < count {
                // Use SIMD to find the next quote
                // If the field is long, this skips checking every byte

                if let baseAddress = buffer.baseAddress {
                    // findNextQuote searches from 0, we need to offset buffer pointer
                    let relativeQuote = SIMDScanner.findNextQuote(
                        buffer: baseAddress.advanced(by: cursor),
                        count: count - cursor,
                    )
                    cursor += relativeQuote
                } else {
                    // Fallback if buffer base is nil (should not happen)
                    while cursor < count, buffer[cursor] != CSVParser.quote {
                        cursor += 1
                    }
                }

                if cursor >= count {
                    // EOF inside quote
                    return FieldResult(
                        start: contentStart,
                        length: cursor - contentStart,
                        quoted: true,
                        nextOffset: cursor,
                        isRowEnd: true,
                        unterminated: true,
                        hasQuoteInUnquoted: false,
                        hasEscapedQuote: hasEscapedQuote,
                    )
                }

                // Found a quote at `cursor`
                // Check if it is escaped ""
                if cursor + 1 < count, buffer[cursor + 1] == CSVParser.quote {
                    cursor += 2 // Skip ""
                    hasEscapedQuote = true
                } else {
                    // End of quoted field
                    let contentEnd = cursor
                    cursor += 1 // Skip closing quote

                    // Expect delimiter or newline or EOF
                    if cursor < count {
                        let next = buffer[cursor]
                        if next == delimiter {
                            return FieldResult(
                                start: contentStart,
                                length: contentEnd - contentStart,
                                quoted: true,
                                nextOffset: cursor + 1,
                                isRowEnd: false,
                                unterminated: false,
                                hasQuoteInUnquoted: false,
                                hasEscapedQuote: hasEscapedQuote,
                            )
                        } else if next == CSVParser.lf {
                            return FieldResult(
                                start: contentStart,
                                length: contentEnd - contentStart,
                                quoted: true,
                                nextOffset: cursor + 1,
                                isRowEnd: true,
                                unterminated: false,
                                hasQuoteInUnquoted: false,
                                hasEscapedQuote: hasEscapedQuote,
                            )
                        } else if next == CSVParser.cr {
                            if cursor + 1 < count, buffer[cursor + 1] == CSVParser.lf {
                                return FieldResult(
                                    start: contentStart,
                                    length: contentEnd - contentStart,
                                    quoted: true,
                                    nextOffset: cursor + 2,
                                    isRowEnd: true,
                                    unterminated: false,
                                    hasQuoteInUnquoted: false,
                                    hasEscapedQuote: hasEscapedQuote,
                                )
                            } else {
                                return FieldResult(
                                    start: contentStart,
                                    length: contentEnd - contentStart,
                                    quoted: true,
                                    nextOffset: cursor + 1,
                                    isRowEnd: true,
                                    unterminated: false,
                                    hasQuoteInUnquoted: false,
                                    hasEscapedQuote: hasEscapedQuote,
                                )
                            }
                        } else {
                            // Lenient: treat garbage after quote as end of field
                            return FieldResult(
                                start: contentStart,
                                length: contentEnd - contentStart,
                                quoted: true,
                                nextOffset: cursor,
                                isRowEnd: false,
                                unterminated: false,
                                hasQuoteInUnquoted: false,
                                hasEscapedQuote: hasEscapedQuote,
                            )
                        }
                    } else {
                        // EOF
                        return FieldResult(
                            start: contentStart,
                            length: contentEnd - contentStart,
                            quoted: true,
                            nextOffset: cursor,
                            isRowEnd: true,
                            unterminated: false,
                            hasQuoteInUnquoted: false,
                            hasEscapedQuote: hasEscapedQuote,
                        )
                    }
                }
            }

            // Unterminated quote - return what we have and flag it
            return FieldResult(
                start: contentStart,
                length: cursor - contentStart,
                quoted: true,
                nextOffset: cursor,
                isRowEnd: true,
                unterminated: true,
                hasQuoteInUnquoted: false,
                hasEscapedQuote: hasEscapedQuote,
            )
        } else {
            // Unquoted Field - use SIMD for long fields
            let contentStart = cursor
            let remaining = count - cursor
            var hasQuoteInField = false

            // Use SIMD for fields >= 64 bytes
            if remaining >= 64, let basePtr = buffer.baseAddress {
                let simdOffset = SIMDScanner.findNextStructural(
                    buffer: basePtr.advanced(by: cursor),
                    count: remaining,
                    delimiter: delimiter,
                )
                cursor += simdOffset

                if cursor >= count {
                    // EOF - check for quotes in the field we just scanned
                    for i in contentStart ..< cursor {
                        if buffer[i] == CSVParser.quote {
                            hasQuoteInField = true
                            break
                        }
                    }
                    return FieldResult(
                        start: contentStart,
                        length: cursor - contentStart,
                        quoted: false,
                        nextOffset: cursor,
                        isRowEnd: true,
                        unterminated: false,
                        hasQuoteInUnquoted: hasQuoteInField,
                        hasEscapedQuote: false,
                    )
                }
            }

            // Scalar handling for short fields or post-SIMD
            while cursor < count {
                let byte = buffer[cursor]

                if byte == CSVParser.quote {
                    hasQuoteInField = true
                }

                if byte == delimiter {
                    return FieldResult(
                        start: contentStart,
                        length: cursor - contentStart,
                        quoted: false,
                        nextOffset: cursor + 1,
                        isRowEnd: false,
                        unterminated: false,
                        hasQuoteInUnquoted: hasQuoteInField,
                        hasEscapedQuote: false,
                    )
                } else if byte == CSVParser.lf {
                    return FieldResult(
                        start: contentStart,
                        length: cursor - contentStart,
                        quoted: false,
                        nextOffset: cursor + 1,
                        isRowEnd: true,
                        unterminated: false,
                        hasQuoteInUnquoted: hasQuoteInField,
                        hasEscapedQuote: false,
                    )
                } else if byte == CSVParser.cr {
                    if cursor + 1 < count, buffer[cursor + 1] == CSVParser.lf {
                        return FieldResult(
                            start: contentStart,
                            length: cursor - contentStart,
                            quoted: false,
                            nextOffset: cursor + 2,
                            isRowEnd: true,
                            unterminated: false,
                            hasQuoteInUnquoted: hasQuoteInField,
                            hasEscapedQuote: false,
                        )
                    } else {
                        return FieldResult(
                            start: contentStart,
                            length: cursor - contentStart,
                            quoted: false,
                            nextOffset: cursor + 1,
                            isRowEnd: true,
                            unterminated: false,
                            hasQuoteInUnquoted: hasQuoteInField,
                            hasEscapedQuote: false,
                        )
                    }
                }
                cursor += 1
            }

            // EOF
            return FieldResult(
                start: contentStart,
                length: cursor - contentStart,
                quoted: false,
                nextOffset: cursor,
                isRowEnd: true,
                unterminated: false,
                hasQuoteInUnquoted: hasQuoteInField,
                hasEscapedQuote: false,
            )
        }
    }
}
