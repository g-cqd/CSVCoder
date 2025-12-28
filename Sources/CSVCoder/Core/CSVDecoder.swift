//
//  CSVDecoder.swift
//  CSVCoder
//
//  A CSV decoder that uses the Codable protocol, similar to JSONDecoder.
//

import Foundation

// MARK: - CSVDecoder

/// A type-safe decoder that converts CSV data to `Decodable` types.
///
/// `CSVDecoder` provides a familiar API similar to `JSONDecoder`, with rich
/// configuration options for dates, numbers, booleans, key transformations,
/// and locale-aware parsing.
///
/// ## Basic Usage
///
/// ```swift
/// struct Person: Codable {
///     let name: String
///     let age: Int
/// }
///
/// let csv = """
/// name,age
/// Alice,30
/// Bob,25
/// """
///
/// let decoder = CSVDecoder()
/// let people: [Person] = try decoder.decode(from: csv)
/// ```
///
/// ## Configuration
///
/// Customize decoding via ``Configuration``:
///
/// ```swift
/// var config = CSVDecoder.Configuration()
/// config.delimiter = ";"
/// config.dateDecodingStrategy = .flexible
/// config.keyDecodingStrategy = .convertFromSnakeCase
///
/// let decoder = CSVDecoder(configuration: config)
/// ```
///
/// ## Thread Safety
///
/// `CSVDecoder` is `Sendable` and safe to share across actor boundaries.
/// The decoder is stateless; all configuration is immutable after initialization.
/// Multiple concurrent decodes can safely share the same decoder instance.
///
/// ## Performance
///
/// - Zero-copy parsing using ``CSVParser`` for UTF-8 data
/// - SIMD-accelerated field scanning for large files
/// - Streaming and parallel decoding extensions available
///
/// ## RFC 4180 Compliance
///
/// Supports both lenient (default) and strict parsing modes. Lenient mode
/// tolerates minor violations; strict mode enforces full compliance with
/// detailed error locations.
///
/// ## See Also
///
/// - ``CSVEncoder`` for encoding types to CSV
/// - ``Configuration`` for available options
/// - ``CSVParser`` for low-level parsing
public final class CSVDecoder: Sendable {

    /// Configuration options for CSV decoding.
    ///
    /// All properties have sensible defaults. Customize only what you need:
    ///
    /// ```swift
    /// var config = CSVDecoder.Configuration()
    /// config.delimiter = "\t"  // Tab-separated
    /// config.trimWhitespace = false
    /// ```
    ///
    /// ## Configuration Priority
    ///
    /// Header resolution follows this precedence:
    /// 1. ``indexMapping`` - Explicit column index → property name mapping
    /// 2. ``hasHeaders`` with ``keyDecodingStrategy`` - Transform header names
    /// 3. `CSVIndexedDecodable` conformance - Use type's `CodingKeys` order
    /// 4. Generated column names (`column0`, `column1`, ...)
    public struct Configuration: Sendable {
        /// The delimiter character used to separate fields. Default is comma (,).
        public var delimiter: Character

        /// Whether the first row contains headers. Default is true.
        public var hasHeaders: Bool

        /// The encoding to use when reading data. Default is UTF-8.
        public var encoding: String.Encoding

        /// Whether to trim whitespace from field values. Default is true.
        public var trimWhitespace: Bool

        /// The date decoding strategy.
        public var dateDecodingStrategy: DateDecodingStrategy

        /// The number decoding strategy.
        public var numberDecodingStrategy: NumberDecodingStrategy

        /// The boolean decoding strategy.
        public var boolDecodingStrategy: BoolDecodingStrategy

        /// The nil decoding strategy for interpreting empty/special values as nil.
        public var nilDecodingStrategy: NilDecodingStrategy

        /// The key decoding strategy for mapping CSV headers to property names.
        public var keyDecodingStrategy: KeyDecodingStrategy

        /// Custom column mapping from CSV header names to property names.
        /// Takes precedence over keyDecodingStrategy for specified columns.
        public var columnMapping: [String: String]

        /// Maps column indices to property names for headerless or index-based decoding.
        /// When set, columns are accessed by index instead of header name.
        /// Example: `[0: "name", 1: "age", 2: "score"]`
        public var indexMapping: [Int: String]

        /// The parsing mode for RFC 4180 compliance.
        public var parsingMode: ParsingMode

        /// Expected field count per row for strict mode validation.
        /// Set to nil to skip field count validation.
        public var expectedFieldCount: Int?

        /// Strategy for decoding nested Codable types.
        public var nestedTypeDecodingStrategy: NestedTypeDecodingStrategy

        /// Creates a new configuration with default values.
        public init(
            delimiter: Character = ",",
            hasHeaders: Bool = true,
            encoding: String.Encoding = .utf8,
            trimWhitespace: Bool = true,
            dateDecodingStrategy: DateDecodingStrategy = .deferredToDate,
            numberDecodingStrategy: NumberDecodingStrategy = .standard,
            boolDecodingStrategy: BoolDecodingStrategy = .standard,
            nilDecodingStrategy: NilDecodingStrategy = .emptyString,
            keyDecodingStrategy: KeyDecodingStrategy = .useDefaultKeys,
            columnMapping: [String: String] = [:],
            indexMapping: [Int: String] = [:],
            parsingMode: ParsingMode = .lenient,
            expectedFieldCount: Int? = nil,
            nestedTypeDecodingStrategy: NestedTypeDecodingStrategy = .error
        ) {
            self.delimiter = delimiter
            self.hasHeaders = hasHeaders
            self.encoding = encoding
            self.trimWhitespace = trimWhitespace
            self.dateDecodingStrategy = dateDecodingStrategy
            self.numberDecodingStrategy = numberDecodingStrategy
            self.boolDecodingStrategy = boolDecodingStrategy
            self.nilDecodingStrategy = nilDecodingStrategy
            self.keyDecodingStrategy = keyDecodingStrategy
            self.columnMapping = columnMapping
            self.indexMapping = indexMapping
            self.parsingMode = parsingMode
            self.expectedFieldCount = expectedFieldCount
            self.nestedTypeDecodingStrategy = nestedTypeDecodingStrategy
        }
    }

    /// Strategies for decoding nested Codable types.
    public enum NestedTypeDecodingStrategy: Sendable {
        /// Throw an error when encountering nested types (default).
        case error
        /// Flatten nested types using a separator (e.g., "address_street").
        case flatten(separator: String)
        /// Decode the field value as JSON.
        case json
        /// Convert field to Data and decode using the type's Decodable conformance.
        case codable
    }

    /// Strategies for decoding dates.
    public enum DateDecodingStrategy: Sendable {
        /// Defer to Date's Decodable implementation.
        case deferredToDate
        /// Decode as a Unix timestamp (seconds since 1970).
        case secondsSince1970
        /// Decode as a Unix timestamp (milliseconds since 1970).
        case millisecondsSince1970
        /// Decode using ISO 8601 format.
        case iso8601
        /// Decode using a custom date format string.
        case formatted(String)
        /// Decode using a custom closure.
        @preconcurrency case custom(@Sendable (String) throws -> Date)
        /// Automatically detect format from 20+ common patterns (ISO, EU, US, etc.)
        case flexible
        /// Try a preferred format first, then fall back to auto-detection.
        case flexibleWithHint(preferred: String)
        /// Use Foundation's Date.ParseStrategy for locale-aware parsing.
        /// Automatically handles date order preferences (DD/MM vs MM/DD) per region.
        case localeAware(locale: Locale = .autoupdatingCurrent, style: DateStyle = .numeric)

        /// Date styles for localeAware parsing.
        public enum DateStyle: Sendable {
            case numeric    // 12/31/2024 or 31/12/2024 depending on locale
            case abbreviated // Dec 31, 2024 or 31 Dec 2024
            case long       // December 31, 2024
        }
    }

    /// Strategies for decoding numeric values (Double, Float, Decimal).
    public enum NumberDecodingStrategy: Sendable {
        /// Use Swift's standard number parsing. Fails on European formats or currency symbols.
        case standard
        /// Auto-detect US (1,234.56) and EU (1.234,56) formats; strip currency symbols.
        case flexible
        /// Use a specific locale for number formatting.
        case locale(Locale)
        /// Use Foundation's FormatStyle.ParseStrategy for locale-aware parsing.
        /// Handles all 300+ locales automatically including grouping separators and decimal marks.
        case parseStrategy(locale: Locale = .autoupdatingCurrent)
        /// Currency-aware parsing that strips currency symbols/codes before parsing.
        /// Uses system locale data to recognize all known currency symbols.
        /// - Parameters:
        ///   - code: Expected currency code (e.g., "USD"). If nil, accepts any currency.
        ///   - locale: Locale for number format interpretation.
        case currency(code: String? = nil, locale: Locale = .autoupdatingCurrent)
    }

    /// Strategies for decoding boolean values.
    public enum BoolDecodingStrategy: Sendable {
        /// Standard values: true/yes/1, false/no/0
        case standard
        /// Extended i18n values: oui/non, ja/nein, да/нет, 是/否, etc.
        case flexible
        /// Custom true/false value sets.
        case custom(trueValues: Set<String>, falseValues: Set<String>)
    }

    /// Strategies for interpreting values as nil.
    public enum NilDecodingStrategy: Sendable {
        /// Treat empty strings as nil (default).
        case emptyString
        /// Treat the literal string "null" (case-insensitive) as nil.
        case nullLiteral
        /// Treat any of the specified strings as nil.
        case custom(Set<String>)
    }

    /// Parsing modes for RFC 4180 compliance.
    public enum ParsingMode: Sendable {
        /// Lenient mode (default): tolerates minor RFC 4180 violations.
        /// - Allows quotes in unquoted fields
        /// - Allows variable field counts across rows
        case lenient
        /// Strict mode: enforces full RFC 4180 compliance.
        /// - Rejects quotes in unquoted fields
        /// - Validates consistent field counts across rows
        /// - Reports precise error locations
        case strict
    }

    /// Strategies for mapping CSV header names to property names.
    public enum KeyDecodingStrategy: Sendable {
        /// Use keys as-is without transformation.
        case useDefaultKeys
        /// Convert snake_case headers to camelCase properties.
        /// Example: "first_name" → "firstName"
        case convertFromSnakeCase
        /// Convert kebab-case headers to camelCase properties.
        /// Example: "first-name" → "firstName"
        case convertFromKebabCase
        /// Convert SCREAMING_SNAKE_CASE headers to camelCase properties.
        /// Example: "FIRST_NAME" → "firstName"
        case convertFromScreamingSnakeCase
        /// Convert PascalCase headers to camelCase properties.
        /// Example: "FirstName" → "firstName"
        case convertFromPascalCase
        /// Apply a custom transformation function.
        @preconcurrency case custom(@Sendable (String) -> String)
    }

    /// The configuration used for decoding.
    public let configuration: Configuration

    /// Creates a new CSV decoder with the given configuration.
    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Decodes an array of values from the given CSV data.
    ///
    /// For headerless CSV, the decoder automatically detects `CSVIndexedDecodable`
    /// conformance and uses the type's `CodingKeys` order for column mapping.
    ///
    /// - Parameters:
    ///   - type: The type to decode.
    ///   - data: The CSV data to decode.
    /// - Returns: An array of decoded values.
    public func decode<T: Decodable>(_ type: [T].Type, from data: Data) throws -> [T] {
        // Runtime detection of CSVIndexedDecodable conformance
        let columnOrder = (T.self as? _CSVIndexedMarker.Type)?._csvColumnOrder

        // Fast path: Zero-copy decoding for UTF-8 data
        return try decodeRowsFromBytes(type, from: data, columnOrder: columnOrder)
    }

    /// Decodes an array of values from the given CSV string.
    ///
    /// For headerless CSV, the decoder automatically detects `CSVIndexedDecodable`
    /// conformance and uses the type's `CodingKeys` order for column mapping.
    ///
    /// - Parameters:
    ///   - type: The type to decode.
    ///   - string: The CSV string to decode.
    /// - Returns: An array of decoded values.
    public func decode<T: Decodable>(_ type: [T].Type, from string: String) throws -> [T] {
        // Runtime detection of CSVIndexedDecodable conformance
        let columnOrder = (T.self as? _CSVIndexedMarker.Type)?._csvColumnOrder
        return try decodeRows(type, from: string, columnOrder: columnOrder)
    }

    /// Internal method that handles both regular Decodable and CSVIndexedDecodable.
    /// Uses CSVParser for consistent zero-copy performance.
    private func decodeRows<T: Decodable>(
        _ type: [T].Type,
        from string: String,
        columnOrder: [String]?
    ) throws -> [T] {
        // Convert string to UTF-8 bytes and use CSVParser for consistency
        let utf8Data = Data(string.utf8)
        return try decodeRowsFromBytes(type, from: utf8Data, columnOrder: columnOrder)
    }

    /// Optimized zero-copy decoding from Data.
    private func decodeRowsFromBytes<T: Decodable>(
        _ type: [T].Type,
        from data: Data,
        columnOrder: [String]?
    ) throws -> [T] {
        return try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return [] }

            // Handle UTF-8 BOM
            let rawBytes = UnsafeBufferPointer(
                start: baseAddress.assumingMemoryBound(to: UInt8.self),
                count: buffer.count
            )
            let startOffset = CSVUtilities.bomOffset(in: rawBytes)

            let adjustedBase = baseAddress.assumingMemoryBound(to: UInt8.self).advanced(by: startOffset)
            let adjustedCount = buffer.count - startOffset
            let bytes = UnsafeBufferPointer(start: adjustedBase, count: adjustedCount)
            let delimiter = configuration.delimiter.asciiValue ?? 0x2C

            let parser = CSVParser(buffer: bytes, delimiter: delimiter)
            let rows = parser.parse()

            // Check for parsing errors
            let isStrict = configuration.parsingMode == .strict
            let expectedFieldCount = configuration.expectedFieldCount

            for (index, row) in rows.enumerated() {
                // Check for unterminated quotes (always an error)
                if row.hasUnterminatedQuote {
                    throw CSVDecodingError.parsingError("Unterminated quoted field", line: index + 1, column: nil)
                }

                // Strict mode: reject quotes in unquoted fields
                if isStrict && row.hasQuoteInUnquotedField {
                    throw CSVDecodingError.parsingError("Quote character in unquoted field (RFC 4180 violation)", line: index + 1, column: nil)
                }

                // Strict mode: validate field count
                if isStrict, let expected = expectedFieldCount, row.count != expected {
                    throw CSVDecodingError.parsingError("Expected \(expected) fields but found \(row.count)", line: index + 1, column: nil)
                }
            }

            guard !rows.isEmpty else { return [] }

            // Extract raw headers from first row
            let firstRow = rows[0]
            var rawHeaders: [String] = []
            rawHeaders.reserveCapacity(firstRow.count)
            for i in 0..<firstRow.count {
                if let s = firstRow.string(at: i) {
                    rawHeaders.append(s)
                } else {
                    rawHeaders.append("column\(i)")
                }
            }

            // Resolve headers using unified method
            let headers = resolveHeaders(
                rawHeaders: rawHeaders,
                columnOrder: columnOrder,
                columnCount: firstRow.count
            )

            // Build header map (Header -> Column Index)
            var headerMap: [String: Int] = [:]
            for (index, header) in headers.enumerated() {
                headerMap[header] = index
            }

            // Skip header row if present
            let startIndex = configuration.hasHeaders ? 1 : 0
            
            // Decode rows
            var results: [T] = []
            results.reserveCapacity(rows.count - startIndex)
            
            for i in startIndex..<rows.count {
                let rowView = rows[i]
                let decoder = CSVRowDecoder(
                    view: rowView,
                    headerMap: headerMap,
                    configuration: configuration,
                    codingPath: [],
                    rowIndex: i + 1
                )
                results.append(try T(from: decoder))
            }
            
            return results
        }
    }

    /// Transforms a CSV header key using the configured strategy.
    func transformKey(_ key: String) -> String {
        // Custom column mapping takes precedence
        if let mapped = configuration.columnMapping[key] {
            return mapped
        }

        switch configuration.keyDecodingStrategy {
        case .useDefaultKeys:
            return key

        case .convertFromSnakeCase:
            return convertFromSnakeCase(key)

        case .convertFromKebabCase:
            return convertFromKebabCase(key)

        case .convertFromScreamingSnakeCase:
            return convertFromScreamingSnakeCase(key)

        case .convertFromPascalCase:
            return convertFromPascalCase(key)

        case .custom(let transform):
            return transform(key)
        }
    }

    /// Converts snake_case to camelCase.
    private func convertFromSnakeCase(_ key: String) -> String {
        let parts = key.split(separator: "_")
        guard let first = parts.first else { return key }
        let rest = parts.dropFirst().map { $0.capitalized }
        return String(first).lowercased() + rest.joined()
    }

    /// Converts kebab-case to camelCase.
    private func convertFromKebabCase(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard let first = parts.first else { return key }
        let rest = parts.dropFirst().map { $0.capitalized }
        return String(first).lowercased() + rest.joined()
    }

    /// Converts SCREAMING_SNAKE_CASE to camelCase.
    private func convertFromScreamingSnakeCase(_ key: String) -> String {
        let parts = key.lowercased().split(separator: "_")
        guard let first = parts.first else { return key }
        let rest = parts.dropFirst().map { $0.capitalized }
        return String(first) + rest.joined()
    }

    /// Converts PascalCase to camelCase.
    private func convertFromPascalCase(_ key: String) -> String {
        guard let first = key.first else { return key }
        return first.lowercased() + String(key.dropFirst())
    }

    // MARK: - Header Resolution

    /// Resolves headers based on configuration priority.
    /// Priority: indexMapping > hasHeaders (with key transform) > columnOrder > generated
    ///
    /// - Parameters:
    ///   - rawHeaders: The raw header strings from the first row (or generated column names).
    ///   - columnOrder: Optional column order from CSVIndexedDecodable conformance.
    ///   - columnCount: Number of columns in the data (used for generation if needed).
    /// - Returns: The resolved header names.
    func resolveHeaders(
        rawHeaders: [String],
        columnOrder: [String]?,
        columnCount: Int? = nil
    ) -> [String] {
        // 1. Explicit index mapping takes highest precedence
        if !configuration.indexMapping.isEmpty {
            let maxIndex = configuration.indexMapping.keys.max() ?? 0
            return (0...maxIndex).map { configuration.indexMapping[$0] ?? "column\($0)" }
        }

        // 2. If hasHeaders, use first row with key transformation
        if configuration.hasHeaders {
            return rawHeaders.map { transformKey($0) }
        }

        // 3. If CSVIndexedDecodable provides column order, use it
        if let columnOrder = columnOrder {
            return columnOrder
        }

        // 4. Generate column names based on count
        let count = columnCount ?? rawHeaders.count
        return (0..<count).map { "column\($0)" }
    }

    /// Decodes a single row from a dictionary representation.
    /// - Parameters:
    ///   - type: The type to decode.
    ///   - row: The dictionary representing a single CSV row.
    /// - Returns: The decoded value.
    public func decode<T: Decodable>(_ type: T.Type, from row: [String: String]) throws -> T {
        let decoder = CSVRowDecoder(
            row: row,
            configuration: configuration,
            codingPath: []
        )
        return try T(from: decoder)
    }

    // MARK: - Type-Inferred Decode Methods

    /// Decodes an array of values from CSV data with type inference.
    ///
    /// Example:
    /// ```swift
    /// let people: [Person] = try decoder.decode(from: data)
    /// ```
    ///
    /// - Parameter data: The CSV data to decode.
    /// - Returns: An array of decoded values.
    public func decode<T: Decodable>(from data: Data) throws -> [T] {
        try decode([T].self, from: data)
    }

    /// Decodes an array of values from a CSV string with type inference.
    ///
    /// Example:
    /// ```swift
    /// let people: [Person] = try decoder.decode(from: csvString)
    /// ```
    ///
    /// - Parameter string: The CSV string to decode.
    /// - Returns: An array of decoded values.
    public func decode<T: Decodable>(from string: String) throws -> [T] {
        try decode([T].self, from: string)
    }

    /// Decodes a single row from a dictionary with type inference.
    ///
    /// Example:
    /// ```swift
    /// let person: Person = try decoder.decode(from: rowDict)
    /// ```
    ///
    /// - Parameter row: The dictionary representing a single CSV row.
    /// - Returns: The decoded value.
    public func decode<T: Decodable>(from row: [String: String]) throws -> T {
        try decode(T.self, from: row)
    }
}
