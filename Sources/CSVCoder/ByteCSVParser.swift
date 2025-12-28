//
//  ByteCSVParser.swift
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

struct ByteCSVParser: Sequence {



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

        let parser: ByteCSVParser

        var offset: Int = 0

        

        mutating func next() -> CSVRowView? {

            guard offset < parser.buffer.count else { return nil }

            

            var fieldStarts: [Int] = []

            var fieldLengths: [Int] = []

            var fieldQuoted: [Bool] = []

            fieldStarts.reserveCapacity(16)

            fieldLengths.reserveCapacity(16)

            fieldQuoted.reserveCapacity(16)

            

            var rowEnded = false

            

            while !rowEnded && offset < parser.buffer.count {

                // Parse Field

                let (start, length, quoted, newOffset, isRowEnd) = parser.parseField(from: offset)

                

                fieldStarts.append(start)

                fieldLengths.append(length)

                fieldQuoted.append(quoted)

                

                offset = newOffset

                rowEnded = isRowEnd

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

                fieldQuoted: fieldQuoted

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

    

    // Returns: (contentStart, contentLength, isQuoted, nextOffset, isRowEnd)

    @inline(__always)

    fileprivate func parseField(from startOffset: Int) -> (Int, Int, Bool, Int, Bool) {


        var cursor = startOffset
        let count = buffer.count
        guard cursor < count else { return (cursor, 0, false, cursor, true) }
        
        let c = buffer[cursor]
        
        if c == ByteCSVParser.quote {
            // Quoted Field
            let contentStart = cursor + 1
            cursor += 1 // Skip opening quote
            
            while cursor < count {
                if buffer[cursor] == ByteCSVParser.quote {
                    // Check for escaped quote ""
                    if cursor + 1 < count && buffer[cursor + 1] == ByteCSVParser.quote {
                        cursor += 2
                    } else {
                        // End of quote
                        let contentEnd = cursor
                        cursor += 1 // Skip closing quote
                        
                        // Expect delimiter or newline or EOF
                        if cursor < count {
                            let next = buffer[cursor]
                            if next == delimiter {
                                return (contentStart, contentEnd - contentStart, true, cursor + 1, false)
                            } else if next == ByteCSVParser.lf {
                                return (contentStart, contentEnd - contentStart, true, cursor + 1, true)
                            } else if next == ByteCSVParser.cr {
                                if cursor + 1 < count && buffer[cursor + 1] == ByteCSVParser.lf {
                                    return (contentStart, contentEnd - contentStart, true, cursor + 2, true)
                                } else {
                                    return (contentStart, contentEnd - contentStart, true, cursor + 1, true)
                                }
                            } else {
                                // Lenient: treat garbage after quote as end of field?
                                // Standard says: quote must be followed by delimiter or newline.
                                // We'll just stop here.
                                return (contentStart, contentEnd - contentStart, true, cursor, false)
                            }
                        } else {
                            // EOF
                            return (contentStart, contentEnd - contentStart, true, cursor, true)
                        }
                    }
                } else {
                    cursor += 1
                }
            }
            
            // Unterminated quote - return what we have
            return (contentStart, cursor - contentStart, true, cursor, true)
            
        } else {
            // Unquoted Field
            let contentStart = cursor
            
            while cursor < count {
                let byte = buffer[cursor]
                
                if byte == delimiter {
                    return (contentStart, cursor - contentStart, false, cursor + 1, false)
                } else if byte == ByteCSVParser.lf {
                    return (contentStart, cursor - contentStart, false, cursor + 1, true)
                } else if byte == ByteCSVParser.cr {
                    if cursor + 1 < count && buffer[cursor + 1] == ByteCSVParser.lf {
                        return (contentStart, cursor - contentStart, false, cursor + 2, true)
                    } else {
                        return (contentStart, cursor - contentStart, false, cursor + 1, true)
                    }
                }
                cursor += 1
            }
            
            // EOF
            return (contentStart, cursor - contentStart, false, cursor, true)
        }
    }
}
