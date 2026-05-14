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
/// - Warning: `CSVRowView` borrows a buffer owned elsewhere (typically via ``CSVParser``).
///   The view is only valid while the underlying buffer remains alive. **Never** store a
///   `CSVRowView` beyond the scope of the parsing closure or iteration context that
///   produced it — doing so results in undefined behavior.
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

    /// Creates a row view from packed `Field` records.
    ///
    /// The packed representation collapses the four parallel `[Int]`/`[Bool]`
    /// arrays into a single contiguous `[Field]` (9 bytes per field including
    /// alignment padding), trading the four array allocations per row for a
    /// single buffer.
    public init(
        buffer: UnsafeBufferPointer<UInt8>,
        fields: [Field],
        hasUnterminatedQuote: Bool,
        hasQuoteInUnquotedField: Bool,
    ) {
        self.buffer = buffer
        self.fields = fields
        self.hasUnterminatedQuote = hasUnterminatedQuote
        self.hasQuoteInUnquotedField = hasQuoteInUnquotedField
    }

    /// Legacy initializer that accepts the historical four-array layout.
    ///
    /// Kept for source compatibility with external callers of the
    /// `CSVRowView` initializer.  The arrays are packed into `Field` records
    /// before being stored.
    public init(
        buffer: UnsafeBufferPointer<UInt8>,
        fieldStarts: [Int],
        fieldLengths: [Int],
        fieldQuoted: [Bool],
        fieldHasEscapedQuote: [Bool],
        hasUnterminatedQuote: Bool,
        hasQuoteInUnquotedField: Bool,
    ) {
        let count = fieldStarts.count
        var packed: [Field] = []
        packed.reserveCapacity(count)
        for i in 0 ..< count {
            packed.append(
                Field(
                    start: Int32(fieldStarts[i]),
                    length: Int32(fieldLengths[i]),
                    flags: (fieldQuoted[i] ? Field.quotedBit : 0)
                        | (fieldHasEscapedQuote[i] ? Field.hasEscapedQuoteBit : 0),
                )
            )
        }
        self.init(
            buffer: buffer,
            fields: packed,
            hasUnterminatedQuote: hasUnterminatedQuote,
            hasQuoteInUnquotedField: hasQuoteInUnquotedField,
        )
    }

    // MARK: Public

    /// Compact per-field metadata, replacing four parallel arrays with one.
    public struct Field: Sendable {
        public let start: Int32
        public let length: Int32
        public let flags: UInt8

        /// Bit 0 — field was originally quoted in source.
        @usableFromInline static let quotedBit: UInt8 = 1 << 0
        /// Bit 1 — field contains `""` escape sequences that require unescaping.
        @usableFromInline static let hasEscapedQuoteBit: UInt8 = 1 << 1

        public init(start: Int32, length: Int32, flags: UInt8) {
            self.start = start
            self.length = length
            self.flags = flags
        }

        public var quoted: Bool { (flags & Self.quotedBit) != 0 }
        public var hasEscapedQuote: Bool { (flags & Self.hasEscapedQuoteBit) != 0 }
    }

    /// Reference to the full buffer (owned elsewhere).
    public let buffer: UnsafeBufferPointer<UInt8>

    /// Packed metadata for each field in this row.
    public let fields: [Field]

    /// Offsets of field starts within the buffer (source-compatibility view).
    public var fieldStarts: [Int] { fields.map { Int($0.start) } }

    /// Lengths of each field (source-compatibility view).
    public var fieldLengths: [Int] { fields.map { Int($0.length) } }

    /// Whether each field was quoted (source-compatibility view).
    public var fieldQuoted: [Bool] { fields.map(\.quoted) }

    /// Whether each field contains escaped quotes (source-compatibility view).
    public var fieldHasEscapedQuote: [Bool] { fields.map(\.hasEscapedQuote) }

    /// Whether any field has an unterminated quote.
    public let hasUnterminatedQuote: Bool

    /// Whether any unquoted field contains a quote character (RFC 4180 violation).
    public let hasQuoteInUnquotedField: Bool

    /// The number of fields in this row.
    public var count: Int { fields.count }

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
        guard index < fields.count else { return UnsafeBufferPointer(start: nil, count: 0) }
        let field = fields[index]
        let start = Int(field.start)
        let length = Int(field.length)
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
        string(at: index, encoding: encoding, trim: false)
    }

    /// Decodes the string value for the field at `index`, optionally trimming
    /// ASCII whitespace at the byte level before string materialization.
    ///
    /// Passing `trim: true` is equivalent to applying
    /// `.trimmingCharacters(in: .whitespaces)` afterwards but avoids the
    /// second String allocation — the trim is performed by adjusting the
    /// byte range used to build the String.
    ///
    /// Internally the trim runs over a `Span<UInt8>` view (Swift 6.2,
    /// iOS 12.2+) for compile-time bounds and lifetime safety; the hot
    /// loop uses `subscript(unchecked:)` so the safety has no runtime
    /// cost.
    ///
    /// - Parameters:
    ///   - index: The zero-based field index.
    ///   - encoding: The string encoding to use for conversion.
    ///   - trim: When `true`, strip leading and trailing ASCII whitespace
    ///     bytes (`0x09`, `0x0A`, `0x0B`, `0x0C`, `0x0D`, `0x20`) before
    ///     materializing the String.
    /// - Returns: The decoded string value, or `nil` if the index is out of
    ///   bounds or encoding conversion fails.
    public func string(at index: Int, encoding: String.Encoding, trim: Bool) -> String? {
        guard index < fields.count else { return nil }

        let field = fields[index]
        let start = Int(field.start)
        let length = Int(field.length)
        let isQuoted = field.quoted
        let hasEscapedQuote = field.hasEscapedQuote

        guard let base = buffer.baseAddress else { return nil }

        let ptr = base.advanced(by: start)
        let fieldBuffer = UnsafeBufferPointer(start: ptr, count: length)

        // Compute the trimmed byte range using a Span view, then re-derive
        // an UnsafeBufferPointer of the matching sub-range. This keeps the
        // existing CSVUnescaper / String constructor call sites unchanged.
        let (trimOffset, trimCount): (Int, Int)
        if trim {
            (trimOffset, trimCount) = Self.trimASCIIRange(fieldBuffer.span)
        } else {
            (trimOffset, trimCount) = (0, length)
        }
        let trimmedBuffer = UnsafeBufferPointer(
            start: ptr.advanced(by: trimOffset),
            count: trimCount,
        )

        // Fast path for UTF-8 (most common case)
        if encoding == .utf8 {
            guard isQuoted, hasEscapedQuote else {
                return String(decoding: trimmedBuffer, as: UTF8.self)
            }
            return CSVUnescaper.unescape(buffer: trimmedBuffer)
        }

        // Non-UTF-8 encoding path (ASCII-compatible encodings like ISO-8859-1, Windows-1252)
        if isQuoted, hasEscapedQuote {
            return CSVUnescaper.unescape(buffer: trimmedBuffer, encoding: encoding)
        }

        guard let trimmedBase = trimmedBuffer.baseAddress else { return "" }
        let data = Data(bytes: trimmedBase, count: trimmedBuffer.count)
        return String(data: data, encoding: encoding)
    }

    /// Returns the `(offset, count)` of the sub-range of `span` with leading
    /// and trailing ASCII whitespace removed. `Span` provides compile-time
    /// bounds checking for the loop; `subscript(unchecked:)` keeps the hot
    /// path free of redundant bounds-check codegen. Whitespace is the
    /// ASCII set: `0x09` (TAB), `0x0A` (LF), `0x0B` (VT), `0x0C` (FF),
    /// `0x0D` (CR), `0x20` (SP).
    @inlinable
    static func trimASCIIRange(_ span: Span<UInt8>) -> (offset: Int, count: Int) {
        guard !span.isEmpty else { return (0, 0) }
        var start = 0
        var end = span.count
        while start < end, Self.isASCIIWhitespace(span[unchecked: start]) {
            start &+= 1
        }
        while end > start, Self.isASCIIWhitespace(span[unchecked: end &- 1]) {
            end &-= 1
        }
        return (start, end - start)
    }

    @inlinable
    static func isASCIIWhitespace(_ byte: UInt8) -> Bool {
        // 0x09..=0x0D and 0x20 — same set as Foundation's CharacterSet.whitespaces
        // restricted to ASCII (which CSV fields are at this layer).
        byte == 0x20 || (byte >= 0x09 && byte <= 0x0D)
    }
}
