//
//  CSVEncoder.swift
//  CSVCoder
//
//  A CSV encoder that uses the Codable protocol, similar to JSONEncoder.
//

import Foundation

/// An encoder that encodes Encodable types to CSV data.
/// nonisolated utility class with immutable configuration
public nonisolated final class CSVEncoder: Sendable {

    /// Configuration for CSV encoding.
    public struct Configuration: Sendable {
        /// The delimiter character used to separate fields. Default is comma (,).
        public var delimiter: Character

        /// Whether to include a header row. Default is true.
        public var includeHeaders: Bool

        /// The encoding to use when writing data. Default is UTF-8.
        public var encoding: String.Encoding

        /// The date encoding strategy.
        public var dateEncodingStrategy: DateEncodingStrategy

        /// How to encode nil values. Default is empty string.
        public var nilEncodingStrategy: NilEncodingStrategy

        /// The line ending to use. Default is LF (\n).
        public var lineEnding: LineEnding

        /// Creates a new configuration with default values.
        public init(
            delimiter: Character = ",",
            includeHeaders: Bool = true,
            encoding: String.Encoding = .utf8,
            dateEncodingStrategy: DateEncodingStrategy = .iso8601,
            nilEncodingStrategy: NilEncodingStrategy = .emptyString,
            lineEnding: LineEnding = .lf
        ) {
            self.delimiter = delimiter
            self.includeHeaders = includeHeaders
            self.encoding = encoding
            self.dateEncodingStrategy = dateEncodingStrategy
            self.nilEncodingStrategy = nilEncodingStrategy
            self.lineEnding = lineEnding
        }
    }

    /// Strategies for encoding dates.
    public enum DateEncodingStrategy: Sendable {
        /// Defer to Date's Encodable implementation.
        case deferredToDate
        /// Encode as a Unix timestamp (seconds since 1970).
        case secondsSince1970
        /// Encode as a Unix timestamp (milliseconds since 1970).
        case millisecondsSince1970
        /// Encode using ISO 8601 format.
        case iso8601
        /// Encode using a custom date format string.
        case formatted(String)
        /// Encode using a custom closure.
        @preconcurrency case custom(@Sendable (Date) throws -> String)
    }

    /// Strategies for encoding nil values.
    public enum NilEncodingStrategy: Sendable {
        /// Encode nil as an empty string.
        case emptyString
        /// Encode nil as the literal string "null".
        case nullLiteral
        /// Encode nil using a custom string.
        case custom(String)
    }

    /// Line ending options.
    public enum LineEnding: String, Sendable {
        /// Unix-style line feed (\n)
        case lf = "\n"
        /// Windows-style carriage return + line feed (\r\n)
        case crlf = "\r\n"
    }

    /// The configuration used for encoding.
    public let configuration: Configuration

    /// Creates a new CSV encoder with the given configuration.
    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Encodes an array of values to CSV data.
    /// - Parameter values: The values to encode.
    /// - Returns: The encoded CSV data.
    public func encode<T: Encodable>(_ values: [T]) throws -> Data {
        var buffer: [UInt8] = []
        try encodeToBuffer(values, into: &buffer)
        return Data(buffer)
    }

    /// Encodes an array of values to a CSV string.
    /// - Parameter values: The values to encode.
    /// - Returns: The encoded CSV string.
    public func encodeToString<T: Encodable>(_ values: [T]) throws -> String {
        var buffer: [UInt8] = []
        try encodeToBuffer(values, into: &buffer)
        return String(decoding: buffer, as: UTF8.self)
    }
    
    /// Encodes an array of values directly to a file URL.
    /// Uses buffered writing to support large datasets with constant memory usage.
    /// - Parameters:
    ///   - values: The values to encode.
    ///   - url: The destination file URL.
    public func encode<T: Encodable>(_ values: [T], to url: URL) throws {
        // Create file
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        var writer = BufferedCSVWriter(handle: handle)
        
        try encodeToWriter(values, writer: &writer)
        try writer.close()
    }

    // MARK: - Internal Streaming Helpers
    
    private func encodeToBuffer<T: Encodable>(_ values: [T], into buffer: inout [UInt8]) throws {
        guard !values.isEmpty else { return }
        
        var headers: [String]?
        let delimiterByte = configuration.delimiter.asciiValue ?? 0x2C
        let lineEndingBytes = Array(configuration.lineEnding.rawValue.utf8)
        
        for (index, value) in values.enumerated() {
            let storage = CSVEncodingStorage()
            let encoder = CSVRowEncoder(configuration: configuration, storage: storage)
            try value.encode(to: encoder)
            
            // Handle Header on first row
            if headers == nil {
                headers = storage.allKeys()
                if configuration.includeHeaders {
                    let headerKeys = headers!
                    for (i, key) in headerKeys.enumerated() {
                        if i > 0 { buffer.append(delimiterByte) }
                        appendEscaped(key, to: &buffer, delimiter: delimiterByte)
                    }
                    buffer.append(contentsOf: lineEndingBytes)
                }
            }
            
            guard let keys = headers else { continue }
            let rowData = storage.allValues()
            
            // Write Row
            for (i, key) in keys.enumerated() {
                if i > 0 { buffer.append(delimiterByte) }
                let val = rowData[key] ?? ""
                appendEscaped(val, to: &buffer, delimiter: delimiterByte)
            }
            
            // Add newline for all rows except the last one (to match previous behavior if needed, 
            // but standard CSV usually has trailing newline. The previous implementation using joined(separator:) 
            // meant NO trailing newline. I will stick to that for compatibility).
            if index < values.count - 1 {
                buffer.append(contentsOf: lineEndingBytes)
            }
        }
    }
    
    private func encodeToWriter<T: Encodable>(_ values: [T], writer: inout BufferedCSVWriter) throws {
        guard !values.isEmpty else { return }
        
        var headers: [String]?
        let delimiter = String(configuration.delimiter)
        let lineEnding = configuration.lineEnding.rawValue
        
        for (index, value) in values.enumerated() {
            let storage = CSVEncodingStorage()
            let encoder = CSVRowEncoder(configuration: configuration, storage: storage)
            try value.encode(to: encoder)
            
            if headers == nil {
                headers = storage.allKeys()
                if configuration.includeHeaders {
                    let headerKeys = headers!
                    for (i, key) in headerKeys.enumerated() {
                        if i > 0 { try writer.write(delimiter) }
                        try writer.write(escapeField(key))
                    }
                    try writer.write(lineEnding)
                }
            }
            
            guard let keys = headers else { continue }
            let rowData = storage.allValues()
            
            for (i, key) in keys.enumerated() {
                if i > 0 { try writer.write(delimiter) }
                let val = rowData[key] ?? ""
                try writer.write(escapeField(val))
            }
            
            if index < values.count - 1 {
                try writer.write(lineEnding)
            }
        }
    }

    /// Appends an escaped field directly to the byte buffer.
    private func appendEscaped(_ value: String, to buffer: inout [UInt8], delimiter: UInt8) {
        // Fast path for simple values
        var needsQuotes = false
        for scalar in value.unicodeScalars {
            let v = scalar.value
            if v == UInt32(delimiter) || v == 0x22 || v == 0x0A || v == 0x0D {
                needsQuotes = true
                break
            }
        }
        
        if needsQuotes {
            buffer.append(0x22) // "
            for scalar in value.unicodeScalars {
                if scalar.value == 0x22 {
                    buffer.append(0x22) // "
                    buffer.append(0x22) // "
                } else {
                    buffer.append(contentsOf: String(scalar).utf8)
                }
            }
            buffer.append(0x22) // "
        } else {
            buffer.append(contentsOf: value.utf8)
        }
    }

    /// Encodes a single value to a CSV row string (without headers).
    /// - Parameter value: The value to encode.
    /// - Returns: A single CSV row string.
    public func encodeRow<T: Encodable>(_ value: T) throws -> String {
        let storage = CSVEncodingStorage()
        let encoder = CSVRowEncoder(configuration: configuration, storage: storage)
        try value.encode(to: encoder)

        let keys = storage.allKeys()
        let row = storage.allValues()
        let delimiter = String(configuration.delimiter)

        let values = keys.map { key -> String in
            let value = row[key] ?? ""
            return escapeField(value)
        }

        return values.joined(separator: delimiter)
    }

    /// Encodes a single value to a dictionary representation.
    /// - Parameter value: The value to encode.
    /// - Returns: A dictionary of field names to string values.
    public func encodeToDictionary<T: Encodable>(_ value: T) throws -> [String: String] {
        let storage = CSVEncodingStorage()
        let encoder = CSVRowEncoder(configuration: configuration, storage: storage)
        try value.encode(to: encoder)
        return storage.allValues()
    }

    /// Returns the header row for a given type.
    /// - Parameter type: The type to get headers for.
    /// - Returns: An array of header names.
    public func headers<T: Encodable>(for type: T.Type, sample: T) throws -> [String] {
        let storage = CSVEncodingStorage()
        let encoder = CSVRowEncoder(configuration: configuration, storage: storage)
        try sample.encode(to: encoder)
        return storage.allKeys()
    }

    // MARK: - Field Escaping

    /// Escapes a field value for CSV output per RFC 4180.
    /// Quotes fields containing delimiters, quotes, or newlines.
    func escapeField(_ value: String) -> String {
        let delimiter = String(configuration.delimiter)

        // Check if escaping is needed
        let needsQuoting = value.contains(delimiter) ||
                          value.contains("\"") ||
                          value.contains("\n") ||
                          value.contains("\r")

        if needsQuoting {
            // Escape quotes by doubling them and wrap in quotes
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }

        return value
    }
}
