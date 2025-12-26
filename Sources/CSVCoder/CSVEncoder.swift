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
        let string = try encodeToString(values)
        guard let data = string.data(using: configuration.encoding) else {
            throw CSVEncodingError.invalidOutput("Could not convert string to data using \(configuration.encoding)")
        }
        return data
    }

    /// Encodes an array of values to a CSV string.
    /// - Parameter values: The values to encode.
    /// - Returns: The encoded CSV string.
    public func encodeToString<T: Encodable>(_ values: [T]) throws -> String {
        guard !values.isEmpty else { return "" }

        var rows: [[String: String]] = []
        var allKeys: [String] = []

        // Encode each value
        for value in values {
            let storage = CSVEncodingStorage()
            let encoder = CSVRowEncoder(configuration: configuration, storage: storage)
            try value.encode(to: encoder)

            let encodedRow = storage.allValues()
            rows.append(encodedRow)

            // Track key order from first row
            if allKeys.isEmpty {
                allKeys = storage.allKeys()
            }
        }

        // Build CSV output
        var lines: [String] = []
        let delimiter = String(configuration.delimiter)
        let lineEnding = configuration.lineEnding.rawValue

        // Add header row
        if configuration.includeHeaders {
            let headerRow = allKeys.map { escapeField($0) }.joined(separator: delimiter)
            lines.append(headerRow)
        }

        // Add data rows
        for row in rows {
            let values = allKeys.map { key -> String in
                let value = row[key] ?? ""
                return escapeField(value)
            }
            lines.append(values.joined(separator: delimiter))
        }

        return lines.joined(separator: lineEnding)
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

    // MARK: - Private Helpers

    private func escapeField(_ value: String) -> String {
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
