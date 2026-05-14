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
nonisolated public final class CSVEncoder: Sendable {
    // MARK: Lifecycle

    /// Creates a new CSV encoder with the given configuration.
    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    // MARK: Public

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
        // MARK: Lifecycle

        /// Creates a new configuration with default values.
        public init(
            delimiter: Character = ",",
            hasHeaders: Bool = true,
            dateEncodingStrategy: DateEncodingStrategy = .iso8601,
            nilEncodingStrategy: NilEncodingStrategy = .emptyString,
            keyEncodingStrategy: KeyEncodingStrategy = .useDefaultKeys,
            boolEncodingStrategy: BoolEncodingStrategy = .numeric,
            numberEncodingStrategy: NumberEncodingStrategy = .standard,
            lineEnding: LineEnding = .lf,
            nestedTypeEncodingStrategy: NestedTypeEncodingStrategy = .error,
            includesTrailingNewline: Bool = false,
        ) {
            precondition(delimiter.asciiValue != nil, "CSV delimiter must be an ASCII character, got '\(delimiter)'")
            self.delimiter = delimiter
            self.hasHeaders = hasHeaders
            self.dateEncodingStrategy = dateEncodingStrategy
            self.nilEncodingStrategy = nilEncodingStrategy
            self.keyEncodingStrategy = keyEncodingStrategy
            self.boolEncodingStrategy = boolEncodingStrategy
            self.numberEncodingStrategy = numberEncodingStrategy
            self.lineEnding = lineEnding
            self.nestedTypeEncodingStrategy = nestedTypeEncodingStrategy
            self.includesTrailingNewline = includesTrailingNewline
        }

        // MARK: Public

        /// The delimiter character used to separate fields. Default is comma (,).
        public var delimiter: Character

        /// Whether to include a header row. Default is true.
        /// Renamed from `includeHeaders` for symmetry with `CSVDecoder.Configuration.hasHeaders`.
        public var hasHeaders: Bool

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

        /// Whether to append a newline after the last row. Default is false.
        public var includesTrailingNewline: Bool
    }

    /// Strategies for encoding nested Codable types.
    public enum NestedTypeEncodingStrategy: Sendable {
        /// Throw an error when encountering nested types (default).
        case error
        /// Flatten nested types using a separator (e.g., "address_street").
        case flatten(separator: String)
        /// Encode nested types as JSON strings, rejecting outputs larger than ``maxBytes``.
        /// The default 1 MiB cap bounds the cost of `JSONEncoder` per cell.
        case json(maxBytes: Int = 1 << 20)
        /// Deprecated alias for ``json``.  Functionally identical; kept for
        /// source compatibility and will be removed in a future release.
        @available(*, deprecated, renamed: "json")
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

    /// Encodes an array of values to CSV data.
    /// - Parameter values: The values to encode.
    /// - Returns: The encoded CSV data.
    public func encode<T: Encodable>(_ values: [T]) throws -> Data {
        var buffer: [UInt8] = []
        try encodeToBuffer(values, into: &buffer, columnOrder: Self.columnOrder(for: T.self))
        return Data(buffer)
    }

    /// Encodes an array of values to a CSV string.
    /// - Parameter values: The values to encode.
    /// - Returns: The encoded CSV string.
    public func encodeToString<T: Encodable>(_ values: [T]) throws -> String {
        var buffer: [UInt8] = []
        try encodeToBuffer(values, into: &buffer, columnOrder: Self.columnOrder(for: T.self))
        return String(decoding: buffer, as: UTF8.self)
    }

    /// Encodes an array of values directly to a file URL.
    /// Uses buffered writing to support large datasets with constant memory usage.
    /// - Parameters:
    ///   - values: The values to encode.
    ///   - url: The destination file URL.
    public func encode<T: Encodable>(_ values: [T], to url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        var writer = BufferedCSVWriter(handle: handle)

        try encodeToWriter(values, writer: &writer, columnOrder: Self.columnOrder(for: T.self))
        try writer.close()
    }

    /// Encodes a single value to a CSV row string (without headers).
    ///
    /// Column order honours ``CSVIndexedEncodable`` conformance when present.
    ///
    /// - Parameter value: The value to encode.
    /// - Returns: A single CSV row string.
    public func encodeRow<T: Encodable>(_ value: T) throws -> String {
        let storage = CSVEncodingStorage()
        let encoder = CSVRowEncoder(configuration: configuration, storage: storage)
        try value.encode(to: encoder)

        let (encodedKeys, row) = storage.snapshot()
        let lookupKeys = Self.columnOrder(for: T.self) ?? encodedKeys
        let delimiter = String(configuration.delimiter)

        return lookupKeys.map { escapeField(row[$0] ?? "") }.joined(separator: delimiter)
    }

    /// Encodes a single value to a dictionary representation keyed by the configured header names.
    ///
    /// Applies ``Configuration/keyEncodingStrategy`` to the output keys for symmetry with batch encoding.
    ///
    /// - Parameter value: The value to encode.
    /// - Returns: A dictionary of field names to string values.
    public func encodeToDictionary<T: Encodable>(_ value: T) throws -> [String: String] {
        let storage = CSVEncodingStorage()
        let encoder = CSVRowEncoder(configuration: configuration, storage: storage)
        try value.encode(to: encoder)

        let (encodedKeys, row) = storage.snapshot()
        let lookupKeys = Self.columnOrder(for: T.self) ?? encodedKeys

        var result: [String: String] = [:]
        result.reserveCapacity(lookupKeys.count)
        for key in lookupKeys {
            result[transformKey(key)] = row[key] ?? ""
        }
        return result
    }

    /// Returns the header row for a given type.
    ///
    /// Honours ``CSVIndexedEncodable`` column order and applies ``Configuration/keyEncodingStrategy``.
    ///
    /// - Parameters:
    ///   - type: The type to get headers for.
    ///   - sample: A sample instance to encode for extracting property names.
    /// - Returns: An array of header names.
    public func headers<T: Encodable>(for type: T.Type, sample: T) throws -> [String] {
        let storage = CSVEncodingStorage()
        let encoder = CSVRowEncoder(configuration: configuration, storage: storage)
        try sample.encode(to: encoder)
        let encodedKeys = storage.allKeys()
        let lookupKeys = Self.columnOrder(for: T.self) ?? encodedKeys
        return lookupKeys.map { transformKey($0) }
    }

    // MARK: Internal

    // MARK: - CSVIndexedEncodable Detection

    /// Returns the canonical column order for `T` when the type opts in via
    /// ``CSVIndexedEncodable`` / `@CSVIndexed`. Returns `nil` for plain `Encodable` types,
    /// in which case the encoder falls back to the order produced by `encode(to:)`.
    static func columnOrder<T>(for type: T.Type) -> [String]? {
        (T.self as? _CSVIndexedMarker.Type)?._csvColumnOrder
    }

    // MARK: - Key Transformation

    /// Transforms a property name using the configured strategy.
    func transformKey(_ key: String) -> String {
        switch configuration.keyEncodingStrategy {
        case .useDefaultKeys:
            key

        case .convertToSnakeCase:
            convertToSnakeCase(key)

        case .convertToKebabCase:
            convertToKebabCase(key)

        case .convertToScreamingSnakeCase:
            convertToScreamingSnakeCase(key)

        case .custom(let transform):
            transform(key)
        }
    }

    // MARK: - Field Escaping

    /// Escapes a field value for CSV output per RFC 4180.
    /// Quotes fields containing delimiters, quotes, or newlines.
    func escapeField(_ value: String) -> String {
        CSVFieldEscaper.escapeField(value, delimiter: configuration.delimiter)
    }

    // MARK: Private

    // MARK: - Internal Streaming Helpers

    private func encodeToBuffer(
        _ values: [some Encodable],
        into buffer: inout [UInt8],
        columnOrder: [String]? = nil,
    ) throws {
        guard !values.isEmpty else { return }

        var lookupKeys: [String]?
        let delimiterByte = configuration.delimiter.asciiValue ?? 0x2C
        let lineEndingBytes = Array(configuration.lineEnding.rawValue.utf8)

        for (index, value) in values.enumerated() {
            let (rowData, encodedKeys) = try encodeValue(value)

            // First row: resolve lookup keys (raw, used to index rowData) and emit transformed header
            if lookupKeys == nil {
                let resolved = columnOrder ?? encodedKeys
                lookupKeys = resolved
                if configuration.hasHeaders {
                    let outputHeaders = resolved.map { transformKey($0) }
                    for (i, key) in outputHeaders.enumerated() {
                        if i > 0 { buffer.append(delimiterByte) }
                        appendEscaped(key, to: &buffer, delimiter: delimiterByte)
                    }
                    buffer.append(contentsOf: lineEndingBytes)
                }
            }

            guard let keys = lookupKeys else { continue }

            for (i, key) in keys.enumerated() {
                if i > 0 { buffer.append(delimiterByte) }
                appendEscaped(rowData[key] ?? "", to: &buffer, delimiter: delimiterByte)
            }

            if index < values.count - 1 || configuration.includesTrailingNewline {
                buffer.append(contentsOf: lineEndingBytes)
            }
        }
    }

    private func encodeToWriter(
        _ values: [some Encodable],
        writer: inout BufferedCSVWriter,
        columnOrder: [String]? = nil,
    ) throws {
        guard !values.isEmpty else { return }

        var lookupKeys: [String]?
        let delimiter = String(configuration.delimiter)
        let lineEnding = configuration.lineEnding.rawValue

        for (index, value) in values.enumerated() {
            let (rowData, encodedKeys) = try encodeValue(value)

            if lookupKeys == nil {
                let resolved = columnOrder ?? encodedKeys
                lookupKeys = resolved
                if configuration.hasHeaders {
                    let outputHeaders = resolved.map { transformKey($0) }
                    for (i, key) in outputHeaders.enumerated() {
                        if i > 0 { try writer.write(delimiter) }
                        try writer.write(escapeField(key))
                    }
                    try writer.write(lineEnding)
                }
            }

            guard let keys = lookupKeys else { continue }

            for (i, key) in keys.enumerated() {
                if i > 0 { try writer.write(delimiter) }
                try writer.write(escapeField(rowData[key] ?? ""))
            }

            if index < values.count - 1 || configuration.includesTrailingNewline {
                try writer.write(lineEnding)
            }
        }
    }

    /// Appends an escaped field directly to the byte buffer.
    /// Uses SIMD acceleration for fields >= 64 bytes.
    private func appendEscaped(_ value: String, to buffer: inout [UInt8], delimiter: UInt8) {
        CSVFieldEscaper.appendEscaped(value, to: &buffer, delimiter: delimiter)
    }

    private func convertToSnakeCase(_ key: String) -> String {
        JSONStyleCaseConverter.convert(key, separator: "_", uppercase: false)
    }

    private func convertToKebabCase(_ key: String) -> String {
        JSONStyleCaseConverter.convert(key, separator: "-", uppercase: false)
    }

    private func convertToScreamingSnakeCase(_ key: String) -> String {
        JSONStyleCaseConverter.convert(key, separator: "_", uppercase: true)
    }
}

// MARK: - JSONStyleCaseConverter

/// Acronym-aware camelCase splitter, matching `JSONEncoder._convertToSnakeCase`
/// from swift-foundation.
///
/// Splits a camelCase identifier on the same word boundaries the standard
/// library uses, then joins the lowercased (or uppercased) parts with the
/// requested separator.
///
/// Examples (snake_case form):
/// - `myProperty` → `my_property`
/// - `myURLProperty` → `my_url_property`
/// - `URLEncoder` → `url_encoder`
/// - `ID` → `id`
/// - `iPhone` → `i_phone`
enum JSONStyleCaseConverter {
    /// Converts a camelCase string to a separator-joined form.
    /// - Parameters:
    ///   - key: The camelCase identifier.
    ///   - separator: The character to insert between words.
    ///   - uppercase: When `true`, joined words are uppercased; otherwise lowercased.
    static func convert(_ key: String, separator: Character, uppercase: Bool) -> String {
        guard !key.isEmpty else { return key }

        // Walk through the string finding word boundaries.  The algorithm
        // mirrors swift-foundation's `JSONEncoder._convertToSnakeCase`:
        // it identifies runs of uppercase letters and treats a trailing
        // uppercase-followed-by-lowercase as the start of a new word.
        var wordRanges: [Range<String.Index>] = []
        wordRanges.reserveCapacity(8)

        var wordStart = key.startIndex
        var searchIndex = key.index(after: key.startIndex)

        while searchIndex < key.endIndex {
            // Find the next uppercase character.
            guard let upperBoundary = key[searchIndex ..< key.endIndex].firstIndex(where: { $0.isUppercase }) else {
                wordRanges.append(wordStart ..< key.endIndex)
                wordStart = key.endIndex
                break
            }

            // Find the end of the uppercase run.
            let upperRunEnd = key[upperBoundary ..< key.endIndex].firstIndex(where: { !$0.isUppercase })

            guard let upperRunEnd else {
                // The uppercase run extends to the end of the string.
                wordRanges.append(wordStart ..< upperBoundary)
                wordRanges.append(upperBoundary ..< key.endIndex)
                wordStart = key.endIndex
                break
            }
            if upperRunEnd == key.index(after: upperBoundary) {
                // Single uppercase letter (camelCase boundary).
                wordRanges.append(wordStart ..< upperBoundary)
                wordStart = upperBoundary
                searchIndex = key.index(after: upperBoundary)
            } else {
                // Run of uppercase letters: the previous word ends at the
                // start of the run, and a new word begins at the last
                // uppercase letter before a lowercase letter (acronym tail).
                wordRanges.append(wordStart ..< upperBoundary)
                let acronymTailStart = key.index(before: upperRunEnd)
                wordRanges.append(upperBoundary ..< acronymTailStart)
                wordStart = acronymTailStart
                searchIndex = upperRunEnd
            }
        }

        if wordStart < key.endIndex {
            wordRanges.append(wordStart ..< key.endIndex)
        }

        // Drop empty ranges (defensive against single-character inputs).
        let words = wordRanges.compactMap { range -> Substring? in
            range.isEmpty ? nil : key[range]
        }

        guard !words.isEmpty else { return key }

        let transform: (Substring) -> String = uppercase ? { $0.uppercased() } : { $0.lowercased() }
        return words.map(transform).joined(separator: String(separator))
    }

    /// Inverts the conversion above: splits on the separator and capitalises
    /// every word after the first.  This matches
    /// `JSONDecoder.KeyDecodingStrategy.convertFromSnakeCase`, which is lossy
    /// for acronyms (`my_url` → `myUrl`, not `myURL`).
    static func invert(_ key: String, separator: Character) -> String {
        guard !key.isEmpty else { return key }

        // Preserve any leading or trailing separator runs (e.g. `_foo`, `foo_`).
        let leading = key.prefix(while: { $0 == separator })
        let trailing = key.reversed().prefix(while: { $0 == separator })
        let core = key.dropFirst(leading.count).dropLast(trailing.count)

        guard !core.isEmpty else { return key }

        let parts = core.split(separator: separator, omittingEmptySubsequences: true)
        guard let first = parts.first else { return key }

        var result = String(leading)
        result.append(first.lowercased())
        for part in parts.dropFirst() {
            result.append(part.prefix(1).uppercased())
            result.append(part.dropFirst().lowercased())
        }
        result.append(String(trailing.reversed()))
        return result
    }
}
