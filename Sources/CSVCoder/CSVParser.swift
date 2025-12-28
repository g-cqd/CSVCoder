//
//  CSVParser.swift
//  CSVCoder
//
//  Zero-copy CSV parser operating directly on UTF-8 bytes.
//

import Foundation

/// A view into a single CSV row within the raw buffer.
/// Does not hold copies of data, only offsets.
struct CSVRowView {
    /// Reference to the full buffer (owned elsewhere).
    let buffer: UnsafeBufferPointer<UInt8>

    /// Offsets of field starts.
    let fieldStarts: [Int]

    /// Lengths of fields.
    let fieldLengths: [Int]

    /// Whether each field was quoted (needs unescaping).
    let fieldQuoted: [Bool]

    /// Whether any field has an unterminated quote.
    let hasUnterminatedQuote: Bool

    /// Whether any unquoted field contains a quote character (RFC 4180 violation).
    let hasQuoteInUnquotedField: Bool

    /// The number of fields in this row.
    var count: Int { fieldStarts.count }
    
    /// Access raw bytes for a field.
    func getBytes(at index: Int) -> UnsafeBufferPointer<UInt8> {
        let start = fieldStarts[index]
        let length = fieldLengths[index]
        guard start + length <= buffer.count else { return UnsafeBufferPointer(start: nil, count: 0) }
        return UnsafeBufferPointer(start: buffer.baseAddress?.advanced(by: start), count: length)
    }
    
    /// decode a string from a field.
    func string(at index: Int) -> String? {
        guard index < fieldStarts.count else { return nil }
        
        let start = fieldStarts[index]
        let length = fieldLengths[index]
        let isQuoted = fieldQuoted[index]
        
        guard let base = buffer.baseAddress else { return nil }
        
        if isQuoted {
            // Must unescape: replace "" with "
            // We need to copy to a new buffer to unescape
            // Or parse directly. Since "" -> " reduces length, we could decode and replace.
            
            // Fast path: check if it actually contains escaped quotes
            // If it's just wrapped in quotes but no internal quotes, we can just slice (excluding outer quotes)
            
            // The parser strips outer quotes for us?
            // Let's assume the parser gives us the CONTENT offsets (excluding outer quotes).
            // But we still need to handle internal "" -> ".
            
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

struct CSVParser: Sequence {



    let buffer: UnsafeBufferPointer<UInt8>

    let delimiter: UInt8

    

    // ASCII constants

    fileprivate static let quote: UInt8 = 0x22      // "

    fileprivate static let cr: UInt8 = 0x0D         // \r

    fileprivate static let lf: UInt8 = 0x0A         // \n

    

    init(buffer: UnsafeBufferPointer<UInt8>, delimiter: UInt8) {

        self.buffer = buffer

        self.delimiter = delimiter

    }

    

    func makeIterator() -> Iterator {

        Iterator(parser: self)

    }

    

    struct Iterator: IteratorProtocol {

        let parser: CSVParser

        var offset: Int = 0



        mutating func next() -> CSVRowView? {

            guard offset < parser.buffer.count else { return nil }



            var fieldStarts: [Int] = []
            var fieldLengths: [Int] = []
            var fieldQuoted: [Bool] = []
            var hasUnterminatedQuote = false
            var hasQuoteInUnquotedField = false
            fieldStarts.reserveCapacity(16)
            fieldLengths.reserveCapacity(16)
            fieldQuoted.reserveCapacity(16)



            var rowEnded = false



            while !rowEnded && offset < parser.buffer.count {

                // Parse Field
                let result = parser.parseField(from: offset)
                fieldStarts.append(result.start)
                fieldLengths.append(result.length)
                fieldQuoted.append(result.quoted)
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
                hasUnterminatedQuote: hasUnterminatedQuote,
                hasQuoteInUnquotedField: hasQuoteInUnquotedField
            )

        }

    }

    

    /// Parses the buffer and returns an array of row views.

    func parse() -> [CSVRowView] {

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
    }

    // Returns: (contentStart, contentLength, isQuoted, nextOffset, isRowEnd, isUnterminatedQuote, hasQuoteInUnquoted)
    @inline(__always)
    fileprivate func parseField(from startOffset: Int) -> FieldResult {

        var cursor = startOffset
        let count = buffer.count
        guard cursor < count else {
            return FieldResult(start: cursor, length: 0, quoted: false, nextOffset: cursor, isRowEnd: true, unterminated: false, hasQuoteInUnquoted: false)
        }
        
        let c = buffer[cursor]
        
        if c == CSVParser.quote {
            // Quoted Field
            let contentStart = cursor + 1
            cursor += 1 // Skip opening quote

            while cursor < count {
                if buffer[cursor] == CSVParser.quote {
                    // Check for escaped quote ""
                    if cursor + 1 < count && buffer[cursor + 1] == CSVParser.quote {
                        cursor += 2
                    } else {
                        // End of quote
                        let contentEnd = cursor
                        cursor += 1 // Skip closing quote

                        // Expect delimiter or newline or EOF
                        if cursor < count {
                            let next = buffer[cursor]
                            if next == delimiter {
                                return FieldResult(start: contentStart, length: contentEnd - contentStart, quoted: true, nextOffset: cursor + 1, isRowEnd: false, unterminated: false, hasQuoteInUnquoted: false)
                            } else if next == CSVParser.lf {
                                return FieldResult(start: contentStart, length: contentEnd - contentStart, quoted: true, nextOffset: cursor + 1, isRowEnd: true, unterminated: false, hasQuoteInUnquoted: false)
                            } else if next == CSVParser.cr {
                                if cursor + 1 < count && buffer[cursor + 1] == CSVParser.lf {
                                    return FieldResult(start: contentStart, length: contentEnd - contentStart, quoted: true, nextOffset: cursor + 2, isRowEnd: true, unterminated: false, hasQuoteInUnquoted: false)
                                } else {
                                    return FieldResult(start: contentStart, length: contentEnd - contentStart, quoted: true, nextOffset: cursor + 1, isRowEnd: true, unterminated: false, hasQuoteInUnquoted: false)
                                }
                            } else {
                                // Lenient: treat garbage after quote as end of field
                                return FieldResult(start: contentStart, length: contentEnd - contentStart, quoted: true, nextOffset: cursor, isRowEnd: false, unterminated: false, hasQuoteInUnquoted: false)
                            }
                        } else {
                            // EOF
                            return FieldResult(start: contentStart, length: contentEnd - contentStart, quoted: true, nextOffset: cursor, isRowEnd: true, unterminated: false, hasQuoteInUnquoted: false)
                        }
                    }
                } else {
                    cursor += 1
                }
            }

            // Unterminated quote - return what we have and flag it
            return FieldResult(start: contentStart, length: cursor - contentStart, quoted: true, nextOffset: cursor, isRowEnd: true, unterminated: true, hasQuoteInUnquoted: false)

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
                    return FieldResult(start: contentStart, length: cursor - contentStart, quoted: false, nextOffset: cursor, isRowEnd: true, unterminated: false, hasQuoteInUnquoted: hasQuoteInField)
                }
            }

            // Scalar handling for short fields or post-SIMD
            while cursor < count {
                let byte = buffer[cursor]

                if byte == CSVParser.quote {
                    hasQuoteInField = true
                }

                if byte == delimiter {
                    return FieldResult(start: contentStart, length: cursor - contentStart, quoted: false, nextOffset: cursor + 1, isRowEnd: false, unterminated: false, hasQuoteInUnquoted: hasQuoteInField)
                } else if byte == CSVParser.lf {
                    return FieldResult(start: contentStart, length: cursor - contentStart, quoted: false, nextOffset: cursor + 1, isRowEnd: true, unterminated: false, hasQuoteInUnquoted: hasQuoteInField)
                } else if byte == CSVParser.cr {
                    if cursor + 1 < count && buffer[cursor + 1] == CSVParser.lf {
                        return FieldResult(start: contentStart, length: cursor - contentStart, quoted: false, nextOffset: cursor + 2, isRowEnd: true, unterminated: false, hasQuoteInUnquoted: hasQuoteInField)
                    } else {
                        return FieldResult(start: contentStart, length: cursor - contentStart, quoted: false, nextOffset: cursor + 1, isRowEnd: true, unterminated: false, hasQuoteInUnquoted: hasQuoteInField)
                    }
                }
                cursor += 1
            }

            // EOF
            return FieldResult(start: contentStart, length: cursor - contentStart, quoted: false, nextOffset: cursor, isRowEnd: true, unterminated: false, hasQuoteInUnquoted: hasQuoteInField)
        }
    }
}
