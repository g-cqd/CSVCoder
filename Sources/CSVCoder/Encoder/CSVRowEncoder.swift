//
//  CSVRowEncoder.swift
//  CSVCoder
//
//  Implements the Encoder protocol for CSV row encoding.
//

import Foundation

// MARK: - CSVRowEncoder

/// An encoder for a single CSV row.
/// nonisolated utility type for encoding
nonisolated struct CSVRowEncoder: Encoder {
    // MARK: Lifecycle

    init(configuration: CSVEncoder.Configuration, codingPath: [CodingKey] = [], storage: CSVEncodingStorage) {
        self.configuration = configuration
        self.codingPath = codingPath
        self.storage = storage
    }

    // MARK: Internal

    let configuration: CSVEncoder.Configuration
    let codingPath: [CodingKey]
    let storage: CSVEncodingStorage

    nonisolated var userInfo: [CodingUserInfoKey: Any] { [:] }

    nonisolated func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        KeyedEncodingContainer(CSVKeyedEncodingContainer(
            configuration: configuration,
            codingPath: codingPath,
            storage: storage,
        ))
    }

    nonisolated func unkeyedContainer() -> UnkeyedEncodingContainer {
        fatalError("Unkeyed containers are not supported in CSV encoding")
    }

    nonisolated func singleValueContainer() -> SingleValueEncodingContainer {
        fatalError("Single value containers are not supported at root level")
    }
}

// MARK: - CSVKeyedEncodingContainer

/// A keyed encoding container for CSV data.
nonisolated struct CSVKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    // MARK: Lifecycle

    init(
        configuration: CSVEncoder.Configuration,
        codingPath: [CodingKey],
        storage: CSVEncodingStorage,
        keyPrefix: String = "",
    ) {
        self.configuration = configuration
        self.codingPath = codingPath
        self.storage = storage
        self.keyPrefix = keyPrefix
    }

    // MARK: Internal

    let configuration: CSVEncoder.Configuration
    let codingPath: [CodingKey]

    mutating func encodeNil(forKey key: Key) throws {
        storage.setValue("", forKey: prefixedKey(key))
    }

    mutating func encode(_ value: Bool, forKey key: Key) throws {
        let stringValue: String = switch configuration.boolEncodingStrategy {
        case .trueFalse:
            value ? "true" : "false"

        case .numeric:
            value ? "1" : "0"

        case .yesNo:
            value ? "yes" : "no"

        case let .custom(trueValue, falseValue):
            value ? trueValue : falseValue
        }
        storage.setValue(stringValue, forKey: prefixedKey(key))
    }

    mutating func encode(_ value: String, forKey key: Key) throws {
        storage.setValue(value, forKey: prefixedKey(key))
    }

    mutating func encode(_ value: Double, forKey key: Key) throws {
        if value.isNaN || value.isInfinite {
            throw CSVEncodingError.invalidValue("Cannot encode \(value) for key '\(prefixedKey(key))'")
        }
        let stringValue = try formatNumber(value)
        storage.setValue(stringValue, forKey: prefixedKey(key))
    }

    mutating func encode(_ value: Float, forKey key: Key) throws {
        if value.isNaN || value.isInfinite {
            throw CSVEncodingError.invalidValue("Cannot encode \(value) for key '\(prefixedKey(key))'")
        }
        let stringValue = try formatNumber(Double(value))
        storage.setValue(stringValue, forKey: prefixedKey(key))
    }

    mutating func encode(_ value: Int, forKey key: Key) throws {
        storage.setValue(String(value), forKey: prefixedKey(key))
    }

    mutating func encode(_ value: Int8, forKey key: Key) throws {
        storage.setValue(String(value), forKey: prefixedKey(key))
    }

    mutating func encode(_ value: Int16, forKey key: Key) throws {
        storage.setValue(String(value), forKey: prefixedKey(key))
    }

    mutating func encode(_ value: Int32, forKey key: Key) throws {
        storage.setValue(String(value), forKey: prefixedKey(key))
    }

    mutating func encode(_ value: Int64, forKey key: Key) throws {
        storage.setValue(String(value), forKey: prefixedKey(key))
    }

    mutating func encode(_ value: UInt, forKey key: Key) throws {
        storage.setValue(String(value), forKey: prefixedKey(key))
    }

    mutating func encode(_ value: UInt8, forKey key: Key) throws {
        storage.setValue(String(value), forKey: prefixedKey(key))
    }

    mutating func encode(_ value: UInt16, forKey key: Key) throws {
        storage.setValue(String(value), forKey: prefixedKey(key))
    }

    mutating func encode(_ value: UInt32, forKey key: Key) throws {
        storage.setValue(String(value), forKey: prefixedKey(key))
    }

    mutating func encode(_ value: UInt64, forKey key: Key) throws {
        storage.setValue(String(value), forKey: prefixedKey(key))
    }

    mutating func encode(_ value: some Encodable, forKey key: Key) throws {
        let fullKey = prefixedKey(key)

        // Handle Date specially
        if let date = value as? Date {
            let encoded = try encodeDate(date)
            storage.setValue(encoded, forKey: fullKey)
            return
        }

        // Handle Decimal specially
        if let decimal = value as? Decimal {
            storage.setValue("\(decimal)", forKey: fullKey)
            return
        }

        // Handle UUID specially
        if let uuid = value as? UUID {
            storage.setValue(uuid.uuidString, forKey: fullKey)
            return
        }

        // Handle URL specially
        if let url = value as? URL {
            storage.setValue(url.absoluteString, forKey: fullKey)
            return
        }

        // Handle Optional by checking for nil
        if let optional = value as? OptionalEncodable {
            if optional.isNil {
                storage.setValue("", forKey: fullKey)
                return
            }
        }

        // Handle nested Codable types based on strategy
        switch configuration.nestedTypeEncodingStrategy {
        case .error:
            // Try to encode using single value container (fails for complex types)
            let singleValueEncoder = CSVSingleValueEncoder(
                configuration: configuration,
                codingPath: codingPath + [key],
                storage: storage,
            )
            try value.encode(to: singleValueEncoder)

        case let .flatten(separator):
            // Encode nested type with prefixed keys
            let nestedEncoder = CSVNestedEncoder(
                configuration: configuration,
                codingPath: codingPath + [key],
                storage: storage,
                keyPrefix: fullKey + separator,
            )
            try value.encode(to: nestedEncoder)

        case .codable,
             .json:
            // Encode as JSON string
            let jsonEncoder = JSONEncoder()
            jsonEncoder.outputFormatting = [.sortedKeys]
            let jsonData = try jsonEncoder.encode(value)
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                throw CSVEncodingError.invalidValue("Failed to encode nested type as JSON for key '\(fullKey)'")
            }
            storage.setValue(jsonString, forKey: fullKey)
        }
    }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type,
                                                        forKey key: Key) -> KeyedEncodingContainer<NestedKey> {
        switch configuration.nestedTypeEncodingStrategy {
        case .error:
            fatalError("Nested containers are not supported in CSV. Configure nestedTypeEncodingStrategy to enable.")

        case let .flatten(separator):
            let nestedPrefix = prefixedKey(key) + separator
            let nestedContainer = CSVKeyedEncodingContainer<NestedKey>(
                configuration: configuration,
                codingPath: codingPath + [key],
                storage: storage,
                keyPrefix: nestedPrefix,
            )
            return KeyedEncodingContainer(nestedContainer)

        case .codable,
             .json:
            // For JSON strategy, we can't return a proper nested container
            // since we need to buffer all values and serialize at the end.
            // This case is handled in encode<T: Encodable> instead.
            fatalError("JSON/Codable nested encoding requires using encode(_:forKey:) with the nested value directly")
        }
    }

    mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        fatalError("Nested unkeyed containers are not supported in CSV")
    }

    mutating func superEncoder() -> Encoder {
        fatalError("Super encoder is not supported in CSV")
    }

    mutating func superEncoder(forKey key: Key) -> Encoder {
        fatalError("Super encoder is not supported in CSV")
    }

    // MARK: - Optional Encoding (encodeIfPresent)

    // These are called by Swift's synthesized Codable for optional properties

    mutating func encodeIfPresent(_ value: Bool?, forKey key: Key) throws {
        storage.setValue(value.map { $0 ? "1" : "0" } ?? "", forKey: prefixedKey(key))
    }

    mutating func encodeIfPresent(_ value: String?, forKey key: Key) throws {
        storage.setValue(value ?? "", forKey: prefixedKey(key))
    }

    mutating func encodeIfPresent(_ value: Double?, forKey key: Key) throws {
        storage.setValue(value.map { String($0) } ?? "", forKey: prefixedKey(key))
    }

    mutating func encodeIfPresent(_ value: Float?, forKey key: Key) throws {
        storage.setValue(value.map { String($0) } ?? "", forKey: prefixedKey(key))
    }

    mutating func encodeIfPresent(_ value: Int?, forKey key: Key) throws {
        storage.setValue(value.map { String($0) } ?? "", forKey: prefixedKey(key))
    }

    mutating func encodeIfPresent(_ value: Int8?, forKey key: Key) throws {
        storage.setValue(value.map { String($0) } ?? "", forKey: prefixedKey(key))
    }

    mutating func encodeIfPresent(_ value: Int16?, forKey key: Key) throws {
        storage.setValue(value.map { String($0) } ?? "", forKey: prefixedKey(key))
    }

    mutating func encodeIfPresent(_ value: Int32?, forKey key: Key) throws {
        storage.setValue(value.map { String($0) } ?? "", forKey: prefixedKey(key))
    }

    mutating func encodeIfPresent(_ value: Int64?, forKey key: Key) throws {
        storage.setValue(value.map { String($0) } ?? "", forKey: prefixedKey(key))
    }

    mutating func encodeIfPresent(_ value: UInt?, forKey key: Key) throws {
        storage.setValue(value.map { String($0) } ?? "", forKey: prefixedKey(key))
    }

    mutating func encodeIfPresent(_ value: UInt8?, forKey key: Key) throws {
        storage.setValue(value.map { String($0) } ?? "", forKey: prefixedKey(key))
    }

    mutating func encodeIfPresent(_ value: UInt16?, forKey key: Key) throws {
        storage.setValue(value.map { String($0) } ?? "", forKey: prefixedKey(key))
    }

    mutating func encodeIfPresent(_ value: UInt32?, forKey key: Key) throws {
        storage.setValue(value.map { String($0) } ?? "", forKey: prefixedKey(key))
    }

    mutating func encodeIfPresent(_ value: UInt64?, forKey key: Key) throws {
        storage.setValue(value.map { String($0) } ?? "", forKey: prefixedKey(key))
    }

    mutating func encodeIfPresent(_ value: (some Encodable)?, forKey key: Key) throws {
        if let value = value {
            try encode(value, forKey: key)
        } else {
            storage.setValue("", forKey: prefixedKey(key))
        }
    }

    // MARK: Private

    private let storage: CSVEncodingStorage
    private let keyPrefix: String

    /// Returns the full key name including any prefix.
    private func prefixedKey(_ key: Key) -> String {
        keyPrefix.isEmpty ? key.stringValue : keyPrefix + key.stringValue
    }

    private func formatNumber(_ value: Double) throws -> String {
        switch configuration.numberEncodingStrategy {
        case .standard:
            return String(value)

        case let .locale(locale):
            let formatter = NumberFormatter()
            formatter.locale = locale
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 15
            return formatter.string(from: NSNumber(value: value)) ?? String(value)

        case let .custom(transform):
            return try transform(value)
        }
    }

    private func encodeDate(_ date: Date) throws -> String {
        switch configuration.dateEncodingStrategy {
        case .deferredToDate:
            throw CSVEncodingError.unsupportedType("deferredToDate requires a date encoding strategy")

        case .secondsSince1970:
            return String(date.timeIntervalSince1970)

        case .millisecondsSince1970:
            return String(date.timeIntervalSince1970 * 1000)

        case .iso8601:
            let formatter = ISO8601DateFormatter()
            return formatter.string(from: date)

        case let .formatted(format):
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            return formatter.string(from: date)

        case let .custom(closure):
            return try closure(date)
        }
    }
}

// MARK: - CSVNestedEncoder

/// An encoder for nested types that uses prefixed keys.
nonisolated struct CSVNestedEncoder: Encoder {
    let configuration: CSVEncoder.Configuration
    let codingPath: [CodingKey]
    let storage: CSVEncodingStorage
    let keyPrefix: String

    nonisolated var userInfo: [CodingUserInfoKey: Any] { [:] }

    nonisolated func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        KeyedEncodingContainer(CSVKeyedEncodingContainer(
            configuration: configuration,
            codingPath: codingPath,
            storage: storage,
            keyPrefix: keyPrefix,
        ))
    }

    nonisolated func unkeyedContainer() -> UnkeyedEncodingContainer {
        fatalError("Unkeyed containers are not supported in CSV encoding")
    }

    nonisolated func singleValueContainer() -> SingleValueEncodingContainer {
        fatalError("Single value containers are not supported for nested types")
    }
}

// MARK: - OptionalEncodable

/// Protocol for handling optional encoding.
private protocol OptionalEncodable {
    nonisolated var isNil: Bool { get }
}

// MARK: - Optional + OptionalEncodable

extension Optional: OptionalEncodable {
    nonisolated var isNil: Bool { self == nil }
}
