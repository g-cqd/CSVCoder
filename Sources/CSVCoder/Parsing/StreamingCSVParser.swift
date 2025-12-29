//
//  StreamingCSVParser.swift
//  CSVCoder
//
//  AsyncSequence-based CSV parser for streaming large files.
//  Parses UTF-8 bytes directly for performance.
//

import Foundation

/// Streaming CSV parser that yields rows one at a time.
/// Conforms to `AsyncSequence` for `for await` iteration.
/// Uses UTF-8 byte-level parsing for optimal performance.
struct StreamingCSVParser: AsyncSequence, Sendable {
    // MARK: Lifecycle

    /// Initialize with a memory-mapped reader.
    init(reader: MemoryMappedReader, configuration: CSVDecoder.Configuration) {
        self.reader = reader
        self.configuration = configuration
    }

    /// Initialize with a file URL.
    init(url: URL, configuration: CSVDecoder.Configuration) throws {
        reader = try MemoryMappedReader(url: url)
        self.configuration = configuration
    }

    /// Initialize with Data.
    init(data: Data, configuration: CSVDecoder.Configuration) {
        reader = MemoryMappedReader(data: data)
        self.configuration = configuration
    }

    // MARK: Internal

    typealias Element = [String]

    struct AsyncIterator: AsyncIteratorProtocol {
        // MARK: Lifecycle

        init(reader: MemoryMappedReader, configuration: CSVDecoder.Configuration) {
            self.reader = reader
            self.configuration = configuration
            delimiterByte = configuration.delimiter.asciiValue ?? StreamingCSVParser.comma
        }

        // MARK: Internal

        mutating func next() async throws -> [String]? {
            // Skip BOM on first read
            if !bomSkipped {
                bomSkipped = true
                skipBOM()
            }

            guard offset < reader.count else { return nil }

            return try reader.withUnsafeBytes { buffer in
                guard let baseAddress = buffer.baseAddress else { return nil }
                let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
                return try parseNextRow(bytes: bytes, count: reader.count)
            }
        }

        // MARK: Private

        private let reader: MemoryMappedReader
        private let configuration: CSVDecoder.Configuration
        private let delimiterByte: UInt8
        private var offset: Int = 0
        private var lineNumber: Int = 1
        private var columnNumber: Int = 1
        private var bomSkipped: Bool = false

        private mutating func skipBOM() {
            guard reader.count >= 3 else { return }
            reader.withUnsafeBytes { buffer in
                guard let baseAddress = buffer.baseAddress else { return }
                let bytes = UnsafeBufferPointer(
                    start: baseAddress.assumingMemoryBound(to: UInt8.self),
                    count: reader.count,
                )
                offset = CSVUtilities.bomOffset(in: bytes)
            }
        }

        private mutating func parseNextRow(bytes: UnsafePointer<UInt8>, count: Int) throws -> [String]? {
            guard offset < count else { return nil }

            let rowStartLine = lineNumber
            var fields: [String] = []
            var fieldBytes: [UInt8] = []
            fieldBytes.reserveCapacity(256)
            var inQuotes = false
            var fieldStartLine = lineNumber
            var fieldStartColumn = columnNumber
            let isStrict = configuration.parsingMode == .strict

            while offset < count {
                let byte = bytes[offset]

                if inQuotes {
                    if byte == StreamingCSVParser.quote {
                        // Check for escaped quote ""
                        if offset + 1 < count, bytes[offset + 1] == StreamingCSVParser.quote {
                            fieldBytes.append(StreamingCSVParser.quote)
                            offset += 2
                            columnNumber += 2
                            continue
                        } else {
                            // End of quoted field
                            inQuotes = false
                            offset += 1
                            columnNumber += 1
                            continue
                        }
                    } else {
                        // Character inside quoted field (including newlines)
                        if byte == StreamingCSVParser.lf {
                            lineNumber += 1
                            columnNumber = 0
                        } else if byte == StreamingCSVParser.cr {
                            // CR inside quoted field - track line if not followed by LF
                            if offset + 1 >= count || bytes[offset + 1] != StreamingCSVParser.lf {
                                lineNumber += 1
                                columnNumber = 0
                            }
                        }
                        fieldBytes.append(byte)
                        offset += 1
                        columnNumber += 1
                        continue
                    }
                }

                // Not in quotes
                if byte == StreamingCSVParser.quote {
                    if fieldBytes.isEmpty {
                        // Start of quoted field
                        inQuotes = true
                        fieldStartLine = lineNumber
                        fieldStartColumn = columnNumber
                        offset += 1
                        columnNumber += 1
                        continue
                    } else {
                        // Quote in middle of unquoted field - RFC 4180 violation
                        if isStrict {
                            throw CSVDecodingError.parsingError(
                                "Quote character in unquoted field (RFC 4180 violation)",
                                line: lineNumber,
                                column: columnNumber,
                            )
                        }
                        // Lenient mode: treat as literal
                        fieldBytes.append(byte)
                        offset += 1
                        columnNumber += 1
                        continue
                    }
                }

                if byte == delimiterByte {
                    fields.append(processField(fieldBytes))
                    fieldBytes.removeAll(keepingCapacity: true)
                    offset += 1
                    columnNumber += 1
                    continue
                }

                // Handle line endings
                if byte == StreamingCSVParser.cr {
                    // Check for CRLF
                    if offset + 1 < count, bytes[offset + 1] == StreamingCSVParser.lf {
                        // CRLF
                        fields.append(processField(fieldBytes))
                        offset += 2
                        lineNumber += 1
                        columnNumber = 1
                        try validateRowIfStrict(fields, rowLine: rowStartLine)
                        return fields.isEmpty ? nil : fields
                    } else {
                        // Lone CR (old Mac style)
                        fields.append(processField(fieldBytes))
                        offset += 1
                        lineNumber += 1
                        columnNumber = 1
                        try validateRowIfStrict(fields, rowLine: rowStartLine)
                        return fields.isEmpty ? nil : fields
                    }
                }

                if byte == StreamingCSVParser.lf {
                    // LF line ending
                    fields.append(processField(fieldBytes))
                    offset += 1
                    lineNumber += 1
                    columnNumber = 1
                    try validateRowIfStrict(fields, rowLine: rowStartLine)
                    return fields.isEmpty ? nil : fields
                }

                // Regular byte
                fieldBytes.append(byte)
                offset += 1
                columnNumber += 1
            }

            // Check for unterminated quoted field
            if inQuotes {
                throw CSVDecodingError.parsingError(
                    "Unterminated quoted field",
                    line: fieldStartLine,
                    column: fieldStartColumn,
                )
            }

            // Handle last field (no trailing newline)
            if !fieldBytes.isEmpty || !fields.isEmpty {
                fields.append(processField(fieldBytes))
                try validateRowIfStrict(fields, rowLine: rowStartLine)
                return fields.isEmpty ? nil : fields
            }

            return nil
        }

        private func validateRowIfStrict(_ fields: [String], rowLine: Int) throws {
            guard configuration.parsingMode == .strict else { return }
            if let expected = configuration.expectedFieldCount, fields.count != expected {
                throw CSVDecodingError.parsingError(
                    "Expected \(expected) fields but found \(fields.count)",
                    line: rowLine,
                    column: nil,
                )
            }
        }

        private func processField(_ bytes: [UInt8]) -> String {
            let string = String(decoding: bytes, as: UTF8.self)
            if configuration.trimWhitespace {
                return string.trimmingCharacters(in: .whitespaces)
            }
            return string
        }
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(reader: reader, configuration: configuration)
    }

    // MARK: Private

    // UTF-8 byte constants (ASCII subset) - shared with CSVParser
    private static let quote: UInt8 = 0x22 // "
    private static let comma: UInt8 = 0x2C // ,
    private static let cr: UInt8 = 0x0D // \r
    private static let lf: UInt8 = 0x0A // \n

    private let reader: MemoryMappedReader
    private let configuration: CSVDecoder.Configuration
}
