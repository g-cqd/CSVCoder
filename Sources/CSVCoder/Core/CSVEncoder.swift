//
//  CSVEncoder.swift
//  CSVCoder
//
//  A CSV encoder that uses the Codable protocol, similar to JSONEncoder.
//

import Foundation

// MARK: - CSVEncoder

/// A type-safe encoder that converts `Encodable` values to CSV format.
///
/// `CSVEncoder` provides a familiar API similar to `JSONEncoder`, supporting
/// configurable encoding strategies for dates, numbers, booleans, and nil values.
///
/// ## Basic Usage
///
/// ```swift
/// struct Person: Codable {
///     let name: String
///     let age: Int
/// }
///
/// let people = [Person(name: "Alice", age: 30), Person(name: "Bob", age: 25)]
/// let encoder = CSVEncoder()
/// let csv = try encoder.encodeToString(people)
/// // name,age
/// // Alice,30
/// // Bob,25
/// ```
///
/// ## Configuration
///
/// Customize encoding via ``Configuration``:
///
/// ```swift
/// var config = CSVEncoder.Configuration()
/// config.delimiter = ";"
/// config.dateEncodingStrategy = .iso8601
/// config.boolEncodingStrategy = .trueFalse
///
/// let encoder = CSVEncoder(configuration: config)
/// ```
///
/// ## Thread Safety
///
/// `CSVEncoder` is `Sendable` and safe to share across actor boundaries.
/// The encoder is stateless; all configuration is immutable after initialization.
/// Multiple concurrent encodes can safely share the same encoder instance.
///
/// ## Performance
///
/// - SIMD-accelerated field escaping for fields ≥64 bytes
/// - Buffered file output for large datasets
/// - For streaming large sequences, use ``encode(_:to:bufferSize:)-8c2n1``
///
/// ## See Also
///
/// - ``CSVDecoder`` for decoding CSV to types
/// - ``Configuration`` for available options
/// - ``NestedTypeEncodingStrategy`` for handling nested objects
public nonisolated final class CSVEncoder: Sendable {

    /// Configuration options for CSV encoding.
    ///
    /// All properties have sensible defaults. Customize only what you need:
    ///
    /// ```swift
    /// var config = CSVEncoder.Configuration()
    /// config.delimiter = "\t"  // Tab-separated
    /// config.hasHeaders = false // Skip header row
    /// ```
    public struct Configuration: Sendable {
        /// The delimiter character used to separate fields. Default is comma (,).
        public var delimiter: Character

        /// Whether to include a header row. Default is true.
        /// Renamed from `includeHeaders` for symmetry with `CSVDecoder.Configuration.hasHeaders`.
        public var hasHeaders: Bool

        /// The encoding to use when writing data. Default is UTF-8.
        public var encoding: String.Encoding

        /// The date encoding strategy.
        public var dateEncodingStrategy: DateEncodingStrategy

        /// How to encode nil values. Default is empty string.
        public var nilEncodingStrategy: NilEncodingStrategy

        /// The key encoding strategy for transforming property names to header names.
        public var keyEncodingStrategy: KeyEncodingStrategy

        /// The boolean encoding strategy.
        public var boolEncodingStrategy: BoolEncodingStrategy

        /// The number encoding strategy.
        public var numberEncodingStrategy: NumberEncodingStrategy

        /// The line ending to use. Default is LF (\n).
        public var lineEnding: LineEnding

        /// Strategy for encoding nested Codable types.
        public var nestedTypeEncodingStrategy: NestedTypeEncodingStrategy

        /// Creates a new configuration with default values.
        public init(
            delimiter: Character = ",",
            hasHeaders: Bool = true,
            encoding: String.Encoding = .utf8,
            dateEncodingStrategy: DateEncodingStrategy = .iso8601,
            nilEncodingStrategy: NilEncodingStrategy = .emptyString,
            keyEncodingStrategy: KeyEncodingStrategy = .useDefaultKeys,
            boolEncodingStrategy: BoolEncodingStrategy = .numeric,
            numberEncodingStrategy: NumberEncodingStrategy = .standard,
            lineEnding: LineEnding = .lf,
            nestedTypeEncodingStrategy: NestedTypeEncodingStrategy = .error
        ) {
            self.delimiter = delimiter
            self.hasHeaders = hasHeaders
            self.encoding = encoding
            self.dateEncodingStrategy = dateEncodingStrategy
            self.nilEncodingStrategy = nilEncodingStrategy
            self.keyEncodingStrategy = keyEncodingStrategy
            self.boolEncodingStrategy = boolEncodingStrategy
            self.numberEncodingStrategy = numberEncodingStrategy
            self.lineEnding = lineEnding
            self.nestedTypeEncodingStrategy = nestedTypeEncodingStrategy
        }
    }

    /// Strategies for encoding nested Codable types.
    public enum NestedTypeEncodingStrategy: Sendable {
        /// Throw an error when encountering nested types (default).
        case error
        /// Flatten nested types using a separator (e.g., "address_street").
        case flatten(separator: String)
        /// Encode nested types as JSON strings.
        case json
        /// Encode nested types to Data using standard Encodable.
        case codable
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

    /// Strategies for encoding property names to CSV header names.
    public enum KeyEncodingStrategy: Sendable {
        /// Use property names as-is without transformation.
        case useDefaultKeys
        /// Convert camelCase properties to snake_case headers.
        /// Example: "firstName" → "first_name"
        case convertToSnakeCase
        /// Convert camelCase properties to kebab-case headers.
        /// Example: "firstName" → "first-name"
        case convertToKebabCase
        /// Convert camelCase properties to SCREAMING_SNAKE_CASE headers.
        /// Example: "firstName" → "FIRST_NAME"
        case convertToScreamingSnakeCase
        /// Apply a custom transformation function.
        @preconcurrency case custom(@Sendable (String) -> String)
    }

    /// Strategies for encoding boolean values.
    public enum BoolEncodingStrategy: Sendable {
        /// Encode as "true"/"false" (default).
        case trueFalse
        /// Encode as "1"/"0".
        case numeric
        /// Encode as "yes"/"no".
        case yesNo
        /// Encode using custom strings.
        case custom(trueValue: String, falseValue: String)
    }

    /// Strategies for encoding numeric values (Double, Float, Decimal).
    public enum NumberEncodingStrategy: Sendable {
        /// Use Swift's standard number formatting.
        case standard
        /// Use a specific locale for number formatting.
        case locale(Locale)
        /// Use a custom closure for formatting.
        @preconcurrency case custom(@Sendable (any Numeric) throws -> String)
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
                let resolvedHeaders = storage.allKeys().map { transformKey($0) }
                headers = resolvedHeaders
                if configuration.hasHeaders {
                    for (i, key) in resolvedHeaders.enumerated() {
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
                let resolvedHeaders = storage.allKeys().map { transformKey($0) }
                headers = resolvedHeaders
                if configuration.hasHeaders {
                    for (i, key) in resolvedHeaders.enumerated() {
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
    /// Uses SIMD acceleration for fields >= 64 bytes.
    private func appendEscaped(_ value: String, to buffer: inout [UInt8], delimiter: UInt8) {
        CSVFieldEscaper.appendEscaped(value, to: &buffer, delimiter: delimiter)
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
    /// - Parameters:
    ///   - type: The type to get headers for.
    ///   - sample: A sample instance to encode for extracting property names.
    /// - Returns: An array of header names.
    public func headers<T: Encodable>(for type: T.Type, sample: T) throws -> [String] {
        let storage = CSVEncodingStorage()
        let encoder = CSVRowEncoder(configuration: configuration, storage: storage)
        try sample.encode(to: encoder)
        return storage.allKeys()
    }

    // MARK: - Key Transformation

    /// Transforms a property name using the configured strategy.
    func transformKey(_ key: String) -> String {
        switch configuration.keyEncodingStrategy {
        case .useDefaultKeys:
            return key
        case .convertToSnakeCase:
            return convertToSnakeCase(key)
        case .convertToKebabCase:
            return convertToKebabCase(key)
        case .convertToScreamingSnakeCase:
            return convertToScreamingSnakeCase(key)
        case .custom(let transform):
            return transform(key)
        }
    }

    /// Converts camelCase to snake_case.
    private func convertToSnakeCase(_ key: String) -> String {
        var result = ""
        for (index, char) in key.enumerated() {
            if char.isUppercase {
                if index > 0 {
                    result += "_"
                }
                result += char.lowercased()
            } else {
                result += String(char)
            }
        }
        return result
    }

    /// Converts camelCase to kebab-case.
    private func convertToKebabCase(_ key: String) -> String {
        var result = ""
        for (index, char) in key.enumerated() {
            if char.isUppercase {
                if index > 0 {
                    result += "-"
                }
                result += char.lowercased()
            } else {
                result += String(char)
            }
        }
        return result
    }

    /// Converts camelCase to SCREAMING_SNAKE_CASE.
    private func convertToScreamingSnakeCase(_ key: String) -> String {
        var result = ""
        for (index, char) in key.enumerated() {
            if char.isUppercase {
                if index > 0 {
                    result += "_"
                }
                result += String(char)
            } else {
                result += char.uppercased()
            }
        }
        return result
    }

    // MARK: - Field Escaping

    /// Escapes a field value for CSV output per RFC 4180.
    /// Quotes fields containing delimiters, quotes, or newlines.
    func escapeField(_ value: String) -> String {
        CSVFieldEscaper.escapeField(value, delimiter: configuration.delimiter)
    }
}
