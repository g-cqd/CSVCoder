//
//  CSVParser.swift
//  CSVCoder
//
//  Zero-copy CSV parser operating directly on UTF-8 bytes.
//

import Foundation

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

    /// Parses a single field starting at the given offset.
    @inline(__always)
    fileprivate func parseField(from startOffset: Int) -> FieldResult {
        let count = buffer.count
        guard startOffset < count else {
            return makeEmptyFieldResult(at: startOffset)
        }

        if buffer[startOffset] == CSVParser.quote {
            return parseQuotedField(from: startOffset, count: count)
        } else {
            return parseUnquotedField(from: startOffset, count: count)
        }
    }

    // MARK: Private

    /// Creates an empty field result for EOF conditions.
    @inline(__always)
    private func makeEmptyFieldResult(at offset: Int) -> FieldResult {
        FieldResult(
            start: offset,
            length: 0,
            quoted: false,
            nextOffset: offset,
            isRowEnd: true,
            unterminated: false,
            hasQuoteInUnquoted: false,
            hasEscapedQuote: false,
        )
    }

    /// Determines the next offset and row-end status based on the terminator byte.
    @inline(__always)
    private func resolveTerminator(
        at cursor: Int,
        count: Int,
    ) -> (nextOffset: Int, isRowEnd: Bool) {
        let byte = buffer[cursor]
        if byte == delimiter {
            return (cursor + 1, false)
        } else if byte == CSVParser.lf {
            return (cursor + 1, true)
        } else if byte == CSVParser.cr {
            let isCRLF = cursor + 1 < count && buffer[cursor + 1] == CSVParser.lf
            return (isCRLF ? cursor + 2 : cursor + 1, true)
        }
        // Garbage after quote - treat as field boundary without advancing
        return (cursor, false)
    }

    /// Parses a quoted field starting at the given offset.
    private func parseQuotedField(from startOffset: Int, count: Int) -> FieldResult {
        let contentStart = startOffset + 1
        var cursor = contentStart
        var hasEscapedQuote = false

        while cursor < count {
            cursor = advanceToNextQuote(from: cursor, count: count)

            if cursor >= count {
                return makeQuotedFieldResult(
                    contentStart: contentStart,
                    contentEnd: cursor,
                    nextOffset: cursor,
                    isRowEnd: true,
                    unterminated: true,
                    hasEscapedQuote: hasEscapedQuote,
                )
            }

            // Check for escaped quote ""
            if cursor + 1 < count, buffer[cursor + 1] == CSVParser.quote {
                cursor += 2
                hasEscapedQuote = true
                continue
            }

            // End of quoted field - closing quote found
            let contentEnd = cursor
            cursor += 1

            if cursor < count {
                let (nextOffset, isRowEnd) = resolveTerminator(at: cursor, count: count)
                return makeQuotedFieldResult(
                    contentStart: contentStart,
                    contentEnd: contentEnd,
                    nextOffset: nextOffset,
                    isRowEnd: isRowEnd,
                    unterminated: false,
                    hasEscapedQuote: hasEscapedQuote,
                )
            } else {
                return makeQuotedFieldResult(
                    contentStart: contentStart,
                    contentEnd: contentEnd,
                    nextOffset: cursor,
                    isRowEnd: true,
                    unterminated: false,
                    hasEscapedQuote: hasEscapedQuote,
                )
            }
        }

        // Unterminated quote
        return makeQuotedFieldResult(
            contentStart: contentStart,
            contentEnd: cursor,
            nextOffset: cursor,
            isRowEnd: true,
            unterminated: true,
            hasEscapedQuote: hasEscapedQuote,
        )
    }

    /// Advances cursor to the next quote character using SIMD when available.
    @inline(__always)
    private func advanceToNextQuote(from cursor: Int, count: Int) -> Int {
        if let baseAddress = buffer.baseAddress {
            let relativeQuote = SIMDScanner.findNextQuote(
                buffer: baseAddress.advanced(by: cursor),
                count: count - cursor,
            )
            return cursor + relativeQuote
        } else {
            var pos = cursor
            while pos < count, buffer[pos] != CSVParser.quote {
                pos += 1
            }
            return pos
        }
    }

    /// Creates a FieldResult for a quoted field.
    @inline(__always)
    private func makeQuotedFieldResult(
        contentStart: Int,
        contentEnd: Int,
        nextOffset: Int,
        isRowEnd: Bool,
        unterminated: Bool,
        hasEscapedQuote: Bool,
    ) -> FieldResult {
        FieldResult(
            start: contentStart,
            length: contentEnd - contentStart,
            quoted: true,
            nextOffset: nextOffset,
            isRowEnd: isRowEnd,
            unterminated: unterminated,
            hasQuoteInUnquoted: false,
            hasEscapedQuote: hasEscapedQuote,
        )
    }

    /// Parses an unquoted field starting at the given offset.
    private func parseUnquotedField(from startOffset: Int, count: Int) -> FieldResult {
        var cursor = startOffset
        var hasQuoteInField = false

        // Use SIMD for fields >= 64 bytes
        cursor = trySIMDAdvance(from: cursor, count: count)

        if cursor >= count {
            // EOF reached via SIMD - check for quotes in scanned region
            hasQuoteInField = checkForQuotes(from: startOffset, to: cursor)
            return makeUnquotedFieldResult(
                contentStart: startOffset,
                contentEnd: cursor,
                nextOffset: cursor,
                isRowEnd: true,
                hasQuoteInUnquoted: hasQuoteInField,
            )
        }

        // Scalar handling for short fields or post-SIMD
        while cursor < count {
            let byte = buffer[cursor]

            if byte == CSVParser.quote {
                hasQuoteInField = true
            }

            if byte == delimiter || byte == CSVParser.lf || byte == CSVParser.cr {
                let (nextOffset, isRowEnd) = resolveTerminator(at: cursor, count: count)
                return makeUnquotedFieldResult(
                    contentStart: startOffset,
                    contentEnd: cursor,
                    nextOffset: nextOffset,
                    isRowEnd: isRowEnd,
                    hasQuoteInUnquoted: hasQuoteInField,
                )
            }
            cursor += 1
        }

        // EOF
        return makeUnquotedFieldResult(
            contentStart: startOffset,
            contentEnd: cursor,
            nextOffset: cursor,
            isRowEnd: true,
            hasQuoteInUnquoted: hasQuoteInField,
        )
    }

    /// Attempts SIMD-accelerated advance for unquoted fields.
    /// Returns the new cursor position after SIMD scanning.
    @inline(__always)
    private func trySIMDAdvance(from startOffset: Int, count: Int) -> Int {
        let remaining = count - startOffset
        guard remaining >= 64, let basePtr = buffer.baseAddress else {
            return startOffset
        }

        let simdOffset = SIMDScanner.findNextStructural(
            buffer: basePtr.advanced(by: startOffset),
            count: remaining,
            delimiter: delimiter,
        )
        return startOffset + simdOffset
    }

    /// Checks if there are any quote characters in the specified range.
    @inline(__always)
    private func checkForQuotes(from start: Int, to end: Int) -> Bool {
        for i in start ..< end where buffer[i] == CSVParser.quote {
            return true
        }
        return false
    }

    /// Creates a FieldResult for an unquoted field.
    @inline(__always)
    private func makeUnquotedFieldResult(
        contentStart: Int,
        contentEnd: Int,
        nextOffset: Int,
        isRowEnd: Bool,
        hasQuoteInUnquoted: Bool,
    ) -> FieldResult {
        FieldResult(
            start: contentStart,
            length: contentEnd - contentStart,
            quoted: false,
            nextOffset: nextOffset,
            isRowEnd: isRowEnd,
            unterminated: false,
            hasQuoteInUnquoted: hasQuoteInUnquoted,
            hasEscapedQuote: false,
        )
    }
}
