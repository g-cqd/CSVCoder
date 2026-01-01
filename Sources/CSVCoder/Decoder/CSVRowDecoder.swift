//
//  CSVRowDecoder.swift
//  CSVCoder
//
//  Implements the Decoder protocol for CSV row decoding.
//

import Foundation

// MARK: - CSVRowDecoder

/// A decoder for a single CSV row.
struct CSVRowDecoder: Decoder {
    // MARK: Lifecycle

    init(
        row: [String: String],
        configuration: CSVDecoder.Configuration,
        codingPath: [CodingKey],
        rowIndex: Int? = nil
    ) {
        source = .dictionary(row)
        self.configuration = configuration
        self.codingPath = codingPath
        self.rowIndex = rowIndex
        encoding = .utf8  // Dictionary source uses pre-decoded strings
    }

    init(
        view: CSVRowView,
        headerMap: [String: Int],
        configuration: CSVDecoder.Configuration,
        codingPath: [CodingKey],
        rowIndex: Int? = nil,
        encoding: String.Encoding = .utf8,
    ) {
        source = .view(view, headerMap: headerMap)
        self.configuration = configuration
        self.codingPath = codingPath
        self.rowIndex = rowIndex
        self.encoding = encoding
    }

    // MARK: Internal

    enum RowSource {
        case dictionary([String: String])
        case view(CSVRowView, headerMap: [String: Int])
    }

    let source: RowSource
    let configuration: CSVDecoder.Configuration
    let codingPath: [CodingKey]
    let rowIndex: Int?
    /// The effective encoding to use for string conversion (may differ from configuration.encoding after transcoding).
    let encoding: String.Encoding

    var userInfo: [CodingUserInfoKey: Any] { [:] }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        KeyedDecodingContainer(
            CSVKeyedDecodingContainer(
                source: source,
                configuration: configuration,
                codingPath: codingPath,
                rowIndex: rowIndex,
                encoding: encoding,
            )
        )
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        throw CSVDecodingError.unsupportedType("Unkeyed containers are not supported in CSV decoding")
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        throw CSVDecodingError.unsupportedType("Single value containers are not supported at root level")
    }
}

// MARK: - CSVKeyedDecodingContainer

/// A keyed decoding container for CSV data.
struct CSVKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    // MARK: Lifecycle

    init(
        source: CSVRowDecoder.RowSource,
        configuration: CSVDecoder.Configuration,
        codingPath: [CodingKey],
        rowIndex: Int?,
        keyPrefix: String? = nil,
        encoding: String.Encoding = .utf8,
    ) {
        self.source = source
        self.configuration = configuration
        self.codingPath = codingPath
        self.rowIndex = rowIndex
        self.keyPrefix = keyPrefix
        self.encoding = encoding
    }

    // MARK: Internal

    let source: CSVRowDecoder.RowSource
    let configuration: CSVDecoder.Configuration
    let codingPath: [CodingKey]
    let rowIndex: Int?
    let keyPrefix: String?
    /// The effective encoding to use for string conversion from CSVRowView.
    let encoding: String.Encoding

    var allKeys: [Key] {
        switch source {
        case .dictionary(let row):
            row.keys.compactMap { Key(stringValue: $0) }

        case .view(_, let headerMap):
            headerMap.keys.compactMap { Key(stringValue: $0) }
        }
    }

    func contains(_ key: Key) -> Bool {
        switch source {
        case .dictionary(let row):
            return row[key.stringValue] != nil

        case .view(let view, let headerMap):
            guard let index = headerMap[key.stringValue] else { return false }
            return index < view.count
        }
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        let value: String?
        switch source {
        case .dictionary(let row):
            guard let v = row[key.stringValue] else { return true }
            value = v

        case .view(let view, let headerMap):
            guard let index = headerMap[key.stringValue] else { return true }
            if index >= view.count { return true }
            guard let v = view.string(at: index) else { return true }
            value = v
        }

        guard let value = value else { return true }

        // Apply nil decoding strategy
        switch configuration.nilDecodingStrategy {
        case .emptyString:
            return value.isEmpty

        case .nullLiteral:
            let lowered = value.lowercased()
            return value.isEmpty || lowered == "null"

        case .custom(let nilValues):
            return value.isEmpty || nilValues.contains(value)
        }
    }

    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
        let value = try getValue(for: key)
        let location = makeLocation(for: key)

        if let result = CSVValueParser.parseBoolean(value, strategy: configuration.boolDecodingStrategy) {
            return result
        }

        // For flexible strategy, also try numeric: any non-zero is true
        if case .flexible = configuration.boolDecodingStrategy {
            if let num = Int(value) { return num != 0 }
        }

        throw CSVDecodingError.typeMismatch(expected: "Bool", actual: value, location: location)
    }

    func decode(_ type: String.Type, forKey key: Key) throws -> String {
        try getValue(for: key)
    }

    func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
        let value = try getValue(for: key)
        guard let result = CSVValueParser.parseDouble(value, strategy: configuration.numberDecodingStrategy) else {
            throw CSVDecodingError.typeMismatch(expected: "Double", actual: value, location: makeLocation(for: key))
        }
        return result
    }

    func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
        let value = try getValue(for: key)
        guard let result = CSVValueParser.parseDouble(value, strategy: configuration.numberDecodingStrategy) else {
            throw CSVDecodingError.typeMismatch(expected: "Float", actual: value, location: makeLocation(for: key))
        }
        return Float(result)
    }

    func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
        let value = try getValue(for: key)
        guard let result = Int(value) else {
            throw CSVDecodingError.typeMismatch(expected: "Int", actual: value, location: makeLocation(for: key))
        }
        return result
    }

    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
        let value = try getValue(for: key)
        guard let result = Int8(value) else {
            throw CSVDecodingError.typeMismatch(expected: "Int8", actual: value, location: makeLocation(for: key))
        }
        return result
    }

    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
        let value = try getValue(for: key)
        guard let result = Int16(value) else {
            throw CSVDecodingError.typeMismatch(expected: "Int16", actual: value, location: makeLocation(for: key))
        }
        return result
    }

    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
        let value = try getValue(for: key)
        guard let result = Int32(value) else {
            throw CSVDecodingError.typeMismatch(expected: "Int32", actual: value, location: makeLocation(for: key))
        }
        return result
    }

    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
        let value = try getValue(for: key)
        guard let result = Int64(value) else {
            throw CSVDecodingError.typeMismatch(expected: "Int64", actual: value, location: makeLocation(for: key))
        }
        return result
    }

    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
        let value = try getValue(for: key)
        guard let result = UInt(value) else {
            throw CSVDecodingError.typeMismatch(expected: "UInt", actual: value, location: makeLocation(for: key))
        }
        return result
    }

    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
        let value = try getValue(for: key)
        guard let result = UInt8(value) else {
            throw CSVDecodingError.typeMismatch(expected: "UInt8", actual: value, location: makeLocation(for: key))
        }
        return result
    }

    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
        let value = try getValue(for: key)
        guard let result = UInt16(value) else {
            throw CSVDecodingError.typeMismatch(expected: "UInt16", actual: value, location: makeLocation(for: key))
        }
        return result
    }

    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
        let value = try getValue(for: key)
        guard let result = UInt32(value) else {
            throw CSVDecodingError.typeMismatch(expected: "UInt32", actual: value, location: makeLocation(for: key))
        }
        return result
    }

    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
        let value = try getValue(for: key)
        guard let result = UInt64(value) else {
            throw CSVDecodingError.typeMismatch(expected: "UInt64", actual: value, location: makeLocation(for: key))
        }
        return result
    }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        // Check if key exists - if not, check for nested type strategies
        let keyExists: Bool =
            switch source {
            case .dictionary(let row):
                row[key.stringValue] != nil

            case .view(let view, let headerMap):
                if let index = headerMap[key.stringValue] {
                    index < view.count
                } else {
                    false
                }
            }

        // Handle nested types based on strategy
        switch configuration.nestedTypeDecodingStrategy {
        case .flatten(let separator):
            // Check if this is a nested type by looking for prefixed keys
            let prefix = key.stringValue + separator
            let hasPrefixedKeys: Bool =
                switch source {
                case .dictionary(let row):
                    row.keys.contains { $0.hasPrefix(prefix) }

                case .view(_, let headerMap):
                    headerMap.keys.contains { $0.hasPrefix(prefix) }
                }

            if hasPrefixedKeys, !keyExists {
                // Decode as nested type with prefixed keys
                let nestedSource = createPrefixedSource(prefix: prefix)
                let decoder = CSVNestedRowDecoder(
                    source: nestedSource,
                    configuration: configuration,
                    codingPath: codingPath + [key],
                    rowIndex: rowIndex,
                )
                return try T(from: decoder)
            }

        case .codable,
            .json:
            // For JSON/codable, the value should exist and be a JSON string
            if keyExists {
                let value = try getValue(for: key)
                guard let data = value.data(using: .utf8) else {
                    throw CSVDecodingError.typeMismatch(
                        expected: "valid UTF-8 JSON",
                        actual: value,
                        location: makeLocation(for: key),
                    )
                }
                return try JSONDecoder().decode(T.self, from: data)
            }

        case .error:
            break
        }

        // Get value for standard decoding
        let value = try getValue(for: key)
        let location = makeLocation(for: key)

        // Handle Date specially
        if type == Date.self, let result = try decodeDate(from: value, key: key) as? T {
            return result
        }

        // Handle Decimal specially
        if type == Decimal.self {
            guard let decimal = CSVValueParser.parseDecimal(value, strategy: configuration.numberDecodingStrategy)
            else {
                throw CSVDecodingError.typeMismatch(expected: "Decimal", actual: value, location: location)
            }
            if let result = decimal as? T { return result }
        }

        // Handle UUID specially
        if type == UUID.self {
            guard let uuid = UUID(uuidString: value) else {
                throw CSVDecodingError.typeMismatch(expected: "UUID", actual: value, location: location)
            }
            if let result = uuid as? T { return result }
        }

        // Handle URL specially
        if type == URL.self {
            guard let url = URL(string: value) else {
                throw CSVDecodingError.typeMismatch(expected: "URL", actual: value, location: location)
            }
            if let result = url as? T { return result }
        }

        // Handle Optional types
        if let optionalType = T.self as? OptionalDecodable.Type {
            if value.isEmpty, let result = optionalType.nilValue as? T {
                return result
            }
        }

        // Try to decode using single value container
        let singleValueDecoder = CSVSingleValueDecoder(
            value: value,
            configuration: configuration,
            codingPath: codingPath + [key],
        )
        return try T(from: singleValueDecoder)
    }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy type: NestedKey.Type,
        forKey key: Key
    ) throws -> KeyedDecodingContainer<NestedKey> {
        switch configuration.nestedTypeDecodingStrategy {
        case .error:
            throw
                CSVDecodingError
                .unsupportedType(
                    "Nested containers are not supported in CSV. Configure nestedTypeDecodingStrategy to enable.",
                )

        case .flatten(let separator):
            // Create a container that reads keys with prefix "key<separator>"
            let prefix = key.stringValue + separator
            let nestedSource = createPrefixedSource(prefix: prefix)
            let nestedContainer = CSVKeyedDecodingContainer<NestedKey>(
                source: nestedSource,
                configuration: configuration,
                codingPath: codingPath + [key],
                rowIndex: rowIndex,
                keyPrefix: prefix,
            )
            return KeyedDecodingContainer(nestedContainer)

        case .json:
            // Get the field value and decode as JSON
            guard let jsonString = stringValue(forKey: key) else {
                throw CSVDecodingError.keyNotFound(
                    key.stringValue,
                    location: makeLocation(for: key, includeAvailableKeys: true),
                )
            }
            guard let jsonData = jsonString.data(using: .utf8) else {
                throw CSVDecodingError.typeMismatch(
                    expected: "valid UTF-8 JSON string",
                    actual: jsonString,
                    location: makeLocation(for: key),
                )
            }
            let jsonDecoder = JSONDecoder()
            // Create a wrapper that returns a keyed container from JSON
            let jsonContainer = try jsonDecoder.decode(NestedJSONContainer<NestedKey>.self, from: jsonData)
            return KeyedDecodingContainer(jsonContainer.container)

        case .codable:
            // Get the field value as Data and use it directly
            guard let fieldValue = stringValue(forKey: key) else {
                throw CSVDecodingError.keyNotFound(
                    key.stringValue,
                    location: makeLocation(for: key, includeAvailableKeys: true),
                )
            }
            guard let data = fieldValue.data(using: .utf8) else {
                throw CSVDecodingError.typeMismatch(
                    expected: "valid UTF-8 data",
                    actual: fieldValue,
                    location: makeLocation(for: key),
                )
            }
            // Try JSON first as the most common Codable format
            let jsonDecoder = JSONDecoder()
            let jsonContainer = try jsonDecoder.decode(NestedJSONContainer<NestedKey>.self, from: data)
            return KeyedDecodingContainer(jsonContainer.container)
        }
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        throw CSVDecodingError.unsupportedType("Nested unkeyed containers (arrays) are not supported in CSV")
    }

    func superDecoder() throws -> Decoder {
        throw CSVDecodingError.unsupportedType("Super decoder is not supported in CSV")
    }

    func superDecoder(forKey key: Key) throws -> Decoder {
        throw CSVDecodingError.unsupportedType("Super decoder is not supported in CSV")
    }

    // MARK: Private

    private func makeLocation(for key: Key, includeAvailableKeys: Bool = false) -> CSVLocation {
        let keys: [String]? =
            switch source {
            case .dictionary(let row): includeAvailableKeys ? Array(row.keys) : nil
            case .view(_, let headerMap): includeAvailableKeys ? Array(headerMap.keys) : nil
            }

        return CSVLocation(
            row: rowIndex,
            column: key.stringValue,
            codingPath: codingPath + [key],
            availableKeys: keys,
        )
    }

    private func getValue(for key: Key) throws -> String {
        let rawValue: String
        switch source {
        case .dictionary(let row):
            guard let value = row[key.stringValue] else {
                throw CSVDecodingError.keyNotFound(
                    key.stringValue,
                    location: makeLocation(for: key, includeAvailableKeys: true),
                )
            }
            rawValue = value

        case .view(let view, let headerMap):
            guard let index = headerMap[key.stringValue], index < view.count else {
                throw CSVDecodingError.keyNotFound(
                    key.stringValue,
                    location: makeLocation(for: key, includeAvailableKeys: true),
                )
            }
            // Decode string on demand using the effective encoding
            guard let value = view.string(at: index, encoding: encoding) else {
                throw CSVDecodingError.keyNotFound(
                    key.stringValue,
                    location: makeLocation(for: key, includeAvailableKeys: true),
                )
            }
            rawValue = value
        }

        // Apply trimWhitespace configuration
        return configuration.trimWhitespace ? rawValue.trimmingCharacters(in: .whitespaces) : rawValue
    }

    /// Returns the string value for a key, or nil if not present.
    private func stringValue(forKey key: Key) -> String? {
        switch source {
        case .dictionary(let row):
            return row[key.stringValue]

        case .view(let view, let headerMap):
            guard let index = headerMap[key.stringValue], index < view.count else { return nil }
            return view.string(at: index)
        }
    }

    private func decodeDate(from value: String, key: some CodingKey) throws -> Date {
        let location = CSVLocation(row: rowIndex, column: key.stringValue, codingPath: codingPath + [key])

        switch configuration.dateDecodingStrategy {
        case .deferredToDate:
            throw CSVDecodingError.typeMismatch(
                expected: "Date (use a date strategy)",
                actual: value,
                location: location,
            )

        case .secondsSince1970:
            guard let seconds = Double(value) else {
                throw CSVDecodingError.typeMismatch(expected: "Unix timestamp", actual: value, location: location)
            }
            return Date(timeIntervalSince1970: seconds)

        case .millisecondsSince1970:
            guard let milliseconds = Double(value) else {
                throw CSVDecodingError.typeMismatch(expected: "Unix timestamp (ms)", actual: value, location: location)
            }
            return Date(timeIntervalSince1970: milliseconds / 1000)

        case .iso8601:
            let formatter = ISO8601DateFormatter()
            guard let date = formatter.date(from: value) else {
                throw CSVDecodingError.typeMismatch(expected: "ISO8601 date", actual: value, location: location)
            }
            return date

        case .formatted(let format):
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale.autoupdatingCurrent
            formatter.timeZone = TimeZone.autoupdatingCurrent
            guard let date = formatter.date(from: value) else {
                throw CSVDecodingError.typeMismatch(
                    expected: "Date with format \(format)",
                    actual: value,
                    location: location,
                )
            }
            return date

        case .custom(let closure):
            return try closure(value)

        case .flexible:
            guard let date = CSVValueParser.parseFlexibleDate(value, hint: nil) else {
                throw CSVDecodingError.typeMismatch(
                    expected: "Date (no matching format found)",
                    actual: value,
                    location: location,
                )
            }
            return date

        case .flexibleWithHint(let preferred):
            guard let date = CSVValueParser.parseFlexibleDate(value, hint: preferred) else {
                throw CSVDecodingError.typeMismatch(
                    expected: "Date (no matching format found)",
                    actual: value,
                    location: location,
                )
            }
            return date

        case .localeAware(let locale, let style):
            guard #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) else {
                // Pre-iOS 15: use flexible parsing
                guard let date = CSVValueParser.parseFlexibleDate(value, hint: nil) else {
                    throw CSVDecodingError.typeMismatch(expected: "Date", actual: value, location: location)
                }
                return date
            }
            if let date = LocaleUtilities.parseDate(value, locale: locale, style: style) {
                return date
            }
            // Fall back to flexible parsing if locale-aware fails
            if let date = CSVValueParser.parseFlexibleDate(value, hint: nil) {
                return date
            }
            throw CSVDecodingError.typeMismatch(expected: "Date (locale-aware)", actual: value, location: location)
        }
    }

    /// Creates a source filtered to keys with the given prefix, stripping the prefix.
    private func createPrefixedSource(prefix: String) -> CSVRowDecoder.RowSource {
        switch source {
        case .dictionary(let row):
            var filtered: [String: String] = [:]
            for (key, value) in row where key.hasPrefix(prefix) {
                let strippedKey = String(key.dropFirst(prefix.count))
                filtered[strippedKey] = value
            }
            return .dictionary(filtered)

        case .view(let view, let headerMap):
            var filtered: [String: Int] = [:]
            for (key, index) in headerMap where key.hasPrefix(prefix) {
                let strippedKey = String(key.dropFirst(prefix.count))
                filtered[strippedKey] = index
            }
            return .view(view, headerMap: filtered)
        }
    }
}

// MARK: - OptionalDecodable

/// Protocol for handling optional decoding.
private protocol OptionalDecodable {
    static var nilValue: Any { get }
}

// MARK: - Optional + OptionalDecodable

extension Optional: OptionalDecodable {
    static var nilValue: Any { none as Any }
}

// MARK: - NestedJSONContainer

/// A wrapper to extract keyed container from JSON data.
private struct NestedJSONContainer<Key: CodingKey>: Decodable {
    // MARK: Lifecycle

    init(from decoder: Decoder) throws {
        let keyedContainer = try decoder.container(keyedBy: Key.self)
        container = JSONKeyedDecodingContainer(wrapped: keyedContainer)
    }

    // MARK: Internal

    let container: JSONKeyedDecodingContainer<Key>
}

// MARK: - JSONKeyedDecodingContainer

/// A keyed decoding container backed by a JSON decoder's container.
private struct JSONKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    // MARK: Lifecycle

    init(wrapped: KeyedDecodingContainer<Key>) {
        self.wrapped = wrapped
    }

    // MARK: Internal

    var codingPath: [CodingKey] { wrapped.codingPath }
    var allKeys: [Key] { wrapped.allKeys }

    func contains(_ key: Key) -> Bool { wrapped.contains(key) }
    func decodeNil(forKey key: Key) throws -> Bool { try wrapped.decodeNil(forKey: key) }
    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool { try wrapped.decode(type, forKey: key) }
    func decode(_ type: String.Type, forKey key: Key) throws -> String { try wrapped.decode(type, forKey: key) }
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double { try wrapped.decode(type, forKey: key) }
    func decode(_ type: Float.Type, forKey key: Key) throws -> Float { try wrapped.decode(type, forKey: key) }
    func decode(_ type: Int.Type, forKey key: Key) throws -> Int { try wrapped.decode(type, forKey: key) }
    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { try wrapped.decode(type, forKey: key) }
    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 { try wrapped.decode(type, forKey: key) }
    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 { try wrapped.decode(type, forKey: key) }
    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 { try wrapped.decode(type, forKey: key) }
    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { try wrapped.decode(type, forKey: key) }
    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 { try wrapped.decode(type, forKey: key) }
    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { try wrapped.decode(type, forKey: key) }
    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { try wrapped.decode(type, forKey: key) }
    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { try wrapped.decode(type, forKey: key) }
    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T { try wrapped.decode(type, forKey: key) }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy type: NestedKey.Type,
        forKey key: Key
    ) throws -> KeyedDecodingContainer<NestedKey> {
        try wrapped.nestedContainer(keyedBy: type, forKey: key)
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        try wrapped.nestedUnkeyedContainer(forKey: key)
    }

    func superDecoder() throws -> Decoder { try wrapped.superDecoder() }
    func superDecoder(forKey key: Key) throws -> Decoder { try wrapped.superDecoder(forKey: key) }

    // MARK: Private

    private let wrapped: KeyedDecodingContainer<Key>
}

// MARK: - CSVNestedRowDecoder

/// A decoder for nested types that reads from a filtered/prefixed source.
struct CSVNestedRowDecoder: Decoder {
    let source: CSVRowDecoder.RowSource
    let configuration: CSVDecoder.Configuration
    let codingPath: [CodingKey]
    let rowIndex: Int?

    var userInfo: [CodingUserInfoKey: Any] { [:] }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        KeyedDecodingContainer(
            CSVKeyedDecodingContainer(
                source: source,
                configuration: configuration,
                codingPath: codingPath,
                rowIndex: rowIndex,
            )
        )
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        throw CSVDecodingError.unsupportedType("Unkeyed containers are not supported in CSV decoding")
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        throw CSVDecodingError.unsupportedType("Single value containers are not supported for nested types")
    }
}
