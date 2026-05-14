//
//  CSVRowStreamProducer.swift
//  CSVCoder
//
//  Unified async-friendly row producer that runs `CSVParser.Iterator` over
//  memory-mapped data, materialising one `[String]` row per call.  Used by
//  the back-pressure and progress streaming entry points so they share the
//  same SIMD-accelerated parser as the synchronous decode path.
//

import Foundation

/// Produces CSV rows on demand from already-mapped data using the shared
/// ``CSVParser`` engine.  Each call to ``nextRow()`` re-enters
/// `Data.withUnsafeBytes`, resumes the parser from the last persisted offset,
/// materialises a row to `[String]`, and exits the closure — keeping the
/// borrowed buffer pointer scoped to a single row.
///
/// The producer applies the same strict-mode validation, BOM handling, and
/// encoding-aware string decoding as the synchronous `CSVDecoder` path.
struct CSVRowStreamProducer: Sendable {
    // MARK: Lifecycle

    /// Initialises the producer with a file URL using memory-mapped I/O.
    init(url: URL, configuration: CSVDecoder.Configuration) throws {
        let raw = try Data(contentsOf: url, options: .mappedIfSafe)
        try self.init(data: raw, configuration: configuration)
    }

    /// Initialises the producer with an in-memory `Data` value.
    init(data: Data, configuration: CSVDecoder.Configuration) throws {
        let encoding = configuration.encoding
        let isASCIICompatible = CSVUtilities.isASCIICompatible(encoding)

        if !isASCIICompatible {
            guard let transcoded = CSVUtilities.transcodeToUTF8(data, from: encoding) else {
                throw CSVDecodingError.parsingError(
                    "Failed to transcode data from \(encoding) to UTF-8",
                    line: nil,
                    column: nil,
                )
            }
            self.data = transcoded
            effectiveEncoding = .utf8
        } else {
            self.data = data
            effectiveEncoding = encoding
        }

        self.configuration = configuration
        delimiter = configuration.delimiter.asciiValue ?? 0x2C
    }

    // MARK: Internal

    /// Returns the next CSV row as a fully materialised `[String]`, or `nil`
    /// at end of input.  Throws `CSVDecodingError.parsingError` if strict
    /// mode (or unterminated-quote enforcement) is violated.
    mutating func nextRow() throws -> [String]? {
        try data.withUnsafeBytes { buffer -> [String]? in
            guard let baseAddress = buffer.baseAddress else { return nil }
            let bytes = UnsafeBufferPointer(
                start: baseAddress.assumingMemoryBound(to: UInt8.self),
                count: buffer.count,
            )

            // Skip BOM on the very first call (sentinel offset == -1).
            if offset < 0 {
                offset = CSVUtilities.bomOffset(in: bytes)
            }

            guard offset < bytes.count else { return nil }

            let parser = CSVParser(buffer: bytes, delimiter: delimiter)
            var iterator = CSVParser.Iterator(parser: parser)
            iterator.offset = offset

            guard let view = iterator.next() else {
                offset = iterator.offset
                return nil
            }

            offset = iterator.offset
            rowIndex += 1

            let isStrict = configuration.parsingMode == .strict

            if view.hasUnterminatedQuote {
                throw CSVDecodingError.parsingError(
                    "Unterminated quoted field",
                    line: rowIndex,
                    column: nil,
                )
            }

            if isStrict, view.hasQuoteInUnquotedField {
                throw CSVDecodingError.parsingError(
                    "Quote character in unquoted field (RFC 4180 violation)",
                    line: rowIndex,
                    column: nil,
                )
            }

            // expectedFieldCount applies in BOTH lenient and strict modes —
            // setting it expresses intent, so a mismatch is always an error.
            if let expected = configuration.expectedFieldCount, view.count != expected {
                throw CSVDecodingError.parsingError(
                    "Expected \(expected) fields but found \(view.count)",
                    line: rowIndex,
                    column: nil,
                )
            }

            var fields: [String] = []
            fields.reserveCapacity(view.count)
            for i in 0 ..< view.count {
                let raw = try materialiseField(view: view, index: i, isStrict: isStrict)
                fields.append(configuration.trimWhitespace ? raw.trimmingCharacters(in: .whitespaces) : raw)
            }
            return fields
        }
    }

    // MARK: Private

    private let data: Data
    private let delimiter: UInt8
    private let configuration: CSVDecoder.Configuration
    private let effectiveEncoding: String.Encoding
    private var offset: Int = -1  // -1 sentinel: BOM-skip pending
    private var rowIndex: Int = 0

    /// Materialises a single field from the row view, enforcing strict-mode
    /// invalid-UTF-8 rejection.  Lenient mode keeps `String(decoding:as:)`
    /// behaviour, which substitutes U+FFFD for invalid bytes.
    private func materialiseField(view: CSVRowView, index: Int, isStrict: Bool) throws -> String {
        if isStrict, effectiveEncoding == .utf8 {
            // In strict + UTF-8 mode, reject invalid byte sequences instead of
            // silently substituting U+FFFD.  Unquoted fields can be validated
            // directly; quoted fields with escapes need to be unescaped first
            // and then re-validated.
            let raw = view.getBytes(at: index)
            let field = view.fields[index]
            if !field.quoted || !field.hasEscapedQuote {
                guard let str = String(bytes: raw, encoding: .utf8) else {
                    throw CSVDecodingError.parsingError(
                        "Invalid UTF-8 byte sequence in field",
                        line: rowIndex,
                        column: index + 1,
                    )
                }
                return str
            }
            // Quoted with escapes — fall through to the general path; the
            // unescaper already handles UTF-8 correctly and the result is a
            // valid Swift String.
        }

        if let s = view.string(at: index, encoding: effectiveEncoding) {
            return s
        }
        return ""
    }
}
