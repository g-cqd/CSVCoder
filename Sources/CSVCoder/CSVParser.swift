//
//  CSVParser.swift
//  CSVCoder
//
//  Zero-copy CSV parser operating directly on UTF-8 bytes.
//

import Foundation

/// A view into a single CSV row within the raw buffer.
/// Does not hold copies of data, only offsets.
public struct CSVRowView {
    /// Reference to the full buffer (owned elsewhere).
    public let buffer: UnsafeBufferPointer<UInt8>

    /// Offsets of field starts.
    public let fieldStarts: [Int]

    /// Lengths of fields.
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
    
    /// Access raw bytes for a field.
    public func getBytes(at index: Int) -> UnsafeBufferPointer<UInt8> {
        let start = fieldStarts[index]
        let length = fieldLengths[index]
        guard start + length <= buffer.count else { return UnsafeBufferPointer(start: nil, count: 0) }
        return UnsafeBufferPointer(start: buffer.baseAddress?.advanced(by: start), count: length)
    }
    
    /// decode a string from a field.
    public func string(at index: Int) -> String? {
        guard index < fieldStarts.count else { return nil }
        
        let start = fieldStarts[index]
        let length = fieldLengths[index]
        let isQuoted = fieldQuoted[index]
        let hasEscapedQuote = fieldHasEscapedQuote[index]
        
        guard let base = buffer.baseAddress else { return nil }
        
        if isQuoted {
            // Must unescape: replace "" with "
            
            // Optimization: if no internal escaped quotes, just strip outer quotes
            // Note: The parser logic returns contentStart and contentLength (excluding outer quotes)
            // So we can just create the string directly if no internal escapes!
            if !hasEscapedQuote {
                let ptr = base.advanced(by: start)
                return String(decoding: UnsafeBufferPointer(start: ptr, count: length), as: UTF8.self)
            }
            
            // Slow path: contains escaped quotes "" -> "
            let fieldBytes = UnsafeBufferPointer(start: base.advanced(by: start), count: length)
            let s = String(decoding: fieldBytes, as: UTF8.self)
            return s.replacingOccurrences(of: "\"\"", with: "\"")
        } else {
            // Zero-copy string creation if possible (Swift 5.x strings are fast to create from UTF8)
            let ptr = base.advanced(by: start)
            return String(decoding: UnsafeBufferPointer(start: ptr, count: length), as: UTF8.self)
        }
    }
}

/// A zero-copy parser that iterates over rows.
public struct CSVParser: Sequence {

    public let buffer: UnsafeBufferPointer<UInt8>

    public let delimiter: UInt8

    // ASCII constants
    fileprivate static let quote: UInt8 = 0x22      // "
    fileprivate static let cr: UInt8 = 0x0D         // \r
    fileprivate static let lf: UInt8 = 0x0A         // \n

    /// Safely parses CSV data within a closure scope.
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
        body: (CSVParser) throws -> R
    ) rethrows -> R {
        try data.withUnsafeBytes { buffer in
            let parser = CSVParser(
                buffer: buffer.bindMemory(to: UInt8.self),
                delimiter: delimiter
            )
            return try body(parser)
        }
    }

    public init(buffer: UnsafeBufferPointer<UInt8>, delimiter: UInt8) {
        self.buffer = buffer
        self.delimiter = delimiter
    }

    public func makeIterator() -> Iterator {
        Iterator(parser: self)
    }

    public struct Iterator: IteratorProtocol {
        let parser: CSVParser
        var offset: Int = 0

        public mutating func next() -> CSVRowView? {
            guard offset < parser.buffer.count else { return nil }

            var fieldStarts: [Int] = []
            var fieldLengths: [Int] = []
            var fieldQuoted: [Bool] = []
            var fieldHasEscapedQuote: [Bool] = []
            var hasUnterminatedQuote = false
            var hasQuoteInUnquotedField = false
            fieldStarts.reserveCapacity(16)
            fieldLengths.reserveCapacity(16)
            fieldQuoted.reserveCapacity(16)
            fieldHasEscapedQuote.reserveCapacity(16)

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
            if fieldStarts.isEmpty || (fieldStarts.count == 1 && fieldLengths[0] == 0 && offset >= parser.buffer.count) {
                 if offset >= parser.buffer.count && fieldStarts.isEmpty { return nil }
                 // If it's a single empty field at EOF, usually we skip it if it was just a newline
                 if fieldStarts.count == 1 && fieldLengths[0] == 0 { return nil }
            }

            return CSVRowView(
                buffer: parser.buffer,
                fieldStarts: fieldStarts,
                fieldLengths: fieldLengths,
                fieldQuoted: fieldQuoted,
                fieldHasEscapedQuote: fieldHasEscapedQuote,
                hasUnterminatedQuote: hasUnterminatedQuote,
                hasQuoteInUnquotedField: hasQuoteInUnquotedField
            )
        }
    }

    /// Parses the buffer and returns an array of row views.
    public func parse() -> [CSVRowView] {
        var rows: [CSVRowView] = []
        for row in self {
            rows.append(row)
        }
        return rows
    }

    /// Result of parsing a single field.
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

    // Returns: (contentStart, contentLength, isQuoted, nextOffset, isRowEnd, isUnterminatedQuote, hasQuoteInUnquoted)
    @inline(__always)
    fileprivate func parseField(from startOffset: Int) -> FieldResult {
        var cursor = startOffset
        let count = buffer.count
        guard cursor < count else {
            return FieldResult(start: cursor, length: 0, quoted: false, nextOffset: cursor, isRowEnd: true, unterminated: false, hasQuoteInUnquoted: false, hasEscapedQuote: false)
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
                       count: count - cursor
                   )
                   cursor += relativeQuote
                } else {
                   // Fallback if buffer base is nil (should not happen)
                   while cursor < count && buffer[cursor] != CSVParser.quote {
                       cursor += 1
                   }
                }

                if cursor >= count {
                     // EOF inside quote
                     return FieldResult(start: contentStart, length: cursor - contentStart, quoted: true, nextOffset: cursor, isRowEnd: true, unterminated: true, hasQuoteInUnquoted: false, hasEscapedQuote: hasEscapedQuote)
                }

                // Found a quote at `cursor`
                // Check if it is escaped ""
                if cursor + 1 < count && buffer[cursor + 1] == CSVParser.quote {
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
                            return FieldResult(start: contentStart, length: contentEnd - contentStart, quoted: true, nextOffset: cursor + 1, isRowEnd: false, unterminated: false, hasQuoteInUnquoted: false, hasEscapedQuote: hasEscapedQuote)
                        } else if next == CSVParser.lf {
                            return FieldResult(start: contentStart, length: contentEnd - contentStart, quoted: true, nextOffset: cursor + 1, isRowEnd: true, unterminated: false, hasQuoteInUnquoted: false, hasEscapedQuote: hasEscapedQuote)
                        } else if next == CSVParser.cr {
                            if cursor + 1 < count && buffer[cursor + 1] == CSVParser.lf {
                                return FieldResult(start: contentStart, length: contentEnd - contentStart, quoted: true, nextOffset: cursor + 2, isRowEnd: true, unterminated: false, hasQuoteInUnquoted: false, hasEscapedQuote: hasEscapedQuote)
                            } else {
                                return FieldResult(start: contentStart, length: contentEnd - contentStart, quoted: true, nextOffset: cursor + 1, isRowEnd: true, unterminated: false, hasQuoteInUnquoted: false, hasEscapedQuote: hasEscapedQuote)
                            }
                        } else {
                            // Lenient: treat garbage after quote as end of field
                            return FieldResult(start: contentStart, length: contentEnd - contentStart, quoted: true, nextOffset: cursor, isRowEnd: false, unterminated: false, hasQuoteInUnquoted: false, hasEscapedQuote: hasEscapedQuote)
                        }
                    } else {
                        // EOF
                        return FieldResult(start: contentStart, length: contentEnd - contentStart, quoted: true, nextOffset: cursor, isRowEnd: true, unterminated: false, hasQuoteInUnquoted: false, hasEscapedQuote: hasEscapedQuote)
                    }
                }
            }

            // Unterminated quote - return what we have and flag it
            return FieldResult(start: contentStart, length: cursor - contentStart, quoted: true, nextOffset: cursor, isRowEnd: true, unterminated: true, hasQuoteInUnquoted: false, hasEscapedQuote: hasEscapedQuote)

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
                    delimiter: delimiter
                )
                cursor += simdOffset

                if cursor >= count {
                    // EOF - check for quotes in the field we just scanned
                    for i in contentStart..<cursor {
                        if buffer[i] == CSVParser.quote {
                            hasQuoteInField = true
                            break
                        }
                    }
                    return FieldResult(start: contentStart, length: cursor - contentStart, quoted: false, nextOffset: cursor, isRowEnd: true, unterminated: false, hasQuoteInUnquoted: hasQuoteInField, hasEscapedQuote: false)
                }
            }

            // Scalar handling for short fields or post-SIMD
            while cursor < count {
                let byte = buffer[cursor]

                if byte == CSVParser.quote {
                    hasQuoteInField = true
                }

                if byte == delimiter {
                    return FieldResult(start: contentStart, length: cursor - contentStart, quoted: false, nextOffset: cursor + 1, isRowEnd: false, unterminated: false, hasQuoteInUnquoted: hasQuoteInField, hasEscapedQuote: false)
                } else if byte == CSVParser.lf {
                    return FieldResult(start: contentStart, length: cursor - contentStart, quoted: false, nextOffset: cursor + 1, isRowEnd: true, unterminated: false, hasQuoteInUnquoted: hasQuoteInField, hasEscapedQuote: false)
                } else if byte == CSVParser.cr {
                    if cursor + 1 < count && buffer[cursor + 1] == CSVParser.lf {
                        return FieldResult(start: contentStart, length: cursor - contentStart, quoted: false, nextOffset: cursor + 2, isRowEnd: true, unterminated: false, hasQuoteInUnquoted: hasQuoteInField, hasEscapedQuote: false)
                    } else {
                        return FieldResult(start: contentStart, length: cursor - contentStart, quoted: false, nextOffset: cursor + 1, isRowEnd: true, unterminated: false, hasQuoteInUnquoted: hasQuoteInField, hasEscapedQuote: false)
                    }
                }
                cursor += 1
            }

            // EOF
            return FieldResult(start: contentStart, length: cursor - contentStart, quoted: false, nextOffset: cursor, isRowEnd: true, unterminated: false, hasQuoteInUnquoted: hasQuoteInField, hasEscapedQuote: false)
        }
    }
}