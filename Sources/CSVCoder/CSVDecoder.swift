//
//  CSVDecoder.swift
//  CSVCoder
//
//  A CSV decoder that uses the Codable protocol, similar to JSONDecoder.
//

import Foundation

/// A decoder that decodes CSV data into Decodable types.
public final class CSVDecoder: Sendable {

    /// Configuration for CSV parsing.
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

        /// The key decoding strategy for mapping CSV headers to property names.
        public var keyDecodingStrategy: KeyDecodingStrategy

        /// Custom column mapping from CSV header names to property names.
        /// Takes precedence over keyDecodingStrategy for specified columns.
        public var columnMapping: [String: String]

        /// Maps column indices to property names for headerless or index-based decoding.
        /// When set, columns are accessed by index instead of header name.
        /// Example: `[0: "name", 1: "age", 2: "score"]`
        public var indexMapping: [Int: String]

        /// Creates a new configuration with default values.
        public init(
            delimiter: Character = ",",
            hasHeaders: Bool = true,
            encoding: String.Encoding = .utf8,
            trimWhitespace: Bool = true,
            dateDecodingStrategy: DateDecodingStrategy = .deferredToDate,
            numberDecodingStrategy: NumberDecodingStrategy = .standard,
            boolDecodingStrategy: BoolDecodingStrategy = .standard,
            keyDecodingStrategy: KeyDecodingStrategy = .useDefaultKeys,
            columnMapping: [String: String] = [:],
            indexMapping: [Int: String] = [:]
        ) {
            self.delimiter = delimiter
            self.hasHeaders = hasHeaders
            self.encoding = encoding
            self.trimWhitespace = trimWhitespace
            self.dateDecodingStrategy = dateDecodingStrategy
            self.numberDecodingStrategy = numberDecodingStrategy
            self.boolDecodingStrategy = boolDecodingStrategy
            self.keyDecodingStrategy = keyDecodingStrategy
            self.columnMapping = columnMapping
            self.indexMapping = indexMapping
        }
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
    }

    /// Strategies for decoding numeric values (Double, Float, Decimal).
    public enum NumberDecodingStrategy: Sendable {
        /// Use Swift's standard number parsing. Fails on European formats or currency symbols.
        case standard
        /// Auto-detect US (1,234.56) and EU (1.234,56) formats; strip currency symbols.
        case flexible
        /// Use a specific locale for number formatting.
        case locale(Locale)
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
        let columnOrder = (T.self as? _CSVIndexedDecodableMarker.Type)?._csvColumnOrder
        
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
        let columnOrder = (T.self as? _CSVIndexedDecodableMarker.Type)?._csvColumnOrder
        return try decodeRows(type, from: string, columnOrder: columnOrder)
    }

    /// Internal method that handles both regular Decodable and CSVIndexedDecodable.
    private func decodeRows<T: Decodable>(
        _ type: [T].Type,
        from string: String,
        columnOrder: [String]?
    ) throws -> [T] {
        let parser = CSVParser(string: string, configuration: configuration)
        let rows = try parser.parse()

        guard !rows.isEmpty else { return [] }

        let rawHeaders: [String]
        let dataRows: [[String]]

        if configuration.hasHeaders {
            rawHeaders = rows[0]
            dataRows = Array(rows.dropFirst())
        } else {
            rawHeaders = (0..<(rows.first?.count ?? 0)).map { "column\($0)" }
            dataRows = rows
        }

        // Determine headers based on: indexMapping > columnOrder > rawHeaders
        let headers: [String]
        if !configuration.indexMapping.isEmpty {
            // Explicit index mapping takes precedence
            let maxIndex = configuration.indexMapping.keys.max() ?? 0
            headers = (0...maxIndex).map { configuration.indexMapping[$0] ?? "column\($0)" }
        } else if let columnOrder = columnOrder, !configuration.hasHeaders {
            // Use CSVIndexedDecodable column order for headerless CSV
            headers = columnOrder
        } else {
            // Apply key transformation and column mapping
            headers = rawHeaders.map { transformKey($0) }
        }

        return try dataRows.enumerated().compactMap { rowIndex, row in
            var dictionary: [String: String] = [:]
            for (index, header) in headers.enumerated() {
                if index < row.count {
                    dictionary[header] = row[index]
                }
            }
            let decoder = CSVRowDecoder(
                row: dictionary,
                configuration: configuration,
                codingPath: [],
                rowIndex: rowIndex + (configuration.hasHeaders ? 2 : 1) // 1-based, account for header
            )
            return try T(from: decoder)
        }
    }

    /// Optimized zero-copy decoding from Data.
    private func decodeRowsFromBytes<T: Decodable>(
        _ type: [T].Type,
        from data: Data,
        columnOrder: [String]?
    ) throws -> [T] {
        return try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return [] }
            let bytes = UnsafeBufferPointer(start: baseAddress.assumingMemoryBound(to: UInt8.self), count: buffer.count)
            let delimiter = configuration.delimiter.asciiValue ?? 0x2C
            
            let parser = ByteCSVParser(buffer: bytes, delimiter: delimiter)
            let rows = parser.parse()
            
            guard !rows.isEmpty else { return [] }
            
            var startIndex = 0
            let rawHeaders: [String]
            
            if configuration.hasHeaders {
                let headerRow = rows[0]
                // Parse headers immediately
                var extracted: [String] = []
                extracted.reserveCapacity(headerRow.count)
                for i in 0..<headerRow.count {
                    if let s = headerRow.string(at: i) {
                        extracted.append(s)
                    } else {
                        extracted.append("column\(i)")
                    }
                }
                rawHeaders = extracted
                startIndex = 1
            } else {
                rawHeaders = (0..<rows[0].count).map { "column\($0)" }
                startIndex = 0
            }
            
            // Determine headers based on: indexMapping > columnOrder > rawHeaders
            let headers: [String]
            if !configuration.indexMapping.isEmpty {
                let maxIndex = configuration.indexMapping.keys.max() ?? 0
                headers = (0...maxIndex).map { configuration.indexMapping[$0] ?? "column\($0)" }
            } else if let columnOrder = columnOrder, !configuration.hasHeaders {
                headers = columnOrder
            } else {
                headers = rawHeaders.map { transformKey($0) }
            }
            
            // Build header map (Header -> Column Index)
            var headerMap: [String: Int] = [:]
            for (index, header) in headers.enumerated() {
                headerMap[header] = index
            }
            
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
