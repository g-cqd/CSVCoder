//
//  CSVSingleValueEncoder.swift
//  CSVCoder
//
//  Implements single value encoding for CSV fields.
//

import Foundation

// MARK: - CSVSingleValueEncoder

/// An encoder for single values in CSV fields.
/// nonisolated utility type for encoding
nonisolated struct CSVSingleValueEncoder: Encoder {
    // MARK: Lifecycle

    init(configuration: CSVEncoder.Configuration, codingPath: [CodingKey], storage: CSVEncodingStorage) {
        self.configuration = configuration
        self.codingPath = codingPath
        self.storage = storage
    }

    // MARK: Internal

    let configuration: CSVEncoder.Configuration
    let codingPath: [CodingKey]

    nonisolated var userInfo: [CodingUserInfoKey: Any] { [:] }

    nonisolated func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        // Return a container that will throw when used
        KeyedEncodingContainer(CSVThrowingKeyedEncodingContainer<Key>(codingPath: codingPath))
    }

    nonisolated func unkeyedContainer() -> UnkeyedEncodingContainer {
        fatalError("Unkeyed containers not supported for single values")
    }

    nonisolated func singleValueContainer() -> SingleValueEncodingContainer {
        CSVSingleValueEncodingContainer(configuration: configuration, codingPath: codingPath, storage: storage)
    }

    // MARK: Private

    private let storage: CSVEncodingStorage
}

// MARK: - CSVThrowingKeyedEncodingContainer

/// A throwing keyed encoding container for detecting nested types.
nonisolated struct CSVThrowingKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let codingPath: [CodingKey]

    mutating func encodeNil(forKey key: Key) throws {
        throw
            CSVEncodingError
            .unsupportedType("Nested types are not supported. Configure nestedTypeEncodingStrategy to enable.")
    }

    mutating func encode(_ value: Bool, forKey key: Key) throws {
        throw
            CSVEncodingError
            .unsupportedType("Nested types are not supported. Configure nestedTypeEncodingStrategy to enable.")
    }

    mutating func encode(_ value: String, forKey key: Key) throws {
        throw
            CSVEncodingError
            .unsupportedType("Nested types are not supported. Configure nestedTypeEncodingStrategy to enable.")
    }

    mutating func encode(_ value: Double, forKey key: Key) throws {
        throw
            CSVEncodingError
            .unsupportedType("Nested types are not supported. Configure nestedTypeEncodingStrategy to enable.")
    }

    mutating func encode(_ value: Float, forKey key: Key) throws {
        throw
            CSVEncodingError
            .unsupportedType("Nested types are not supported. Configure nestedTypeEncodingStrategy to enable.")
    }

    mutating func encode(_ value: Int, forKey key: Key) throws {
        throw
            CSVEncodingError
            .unsupportedType("Nested types are not supported. Configure nestedTypeEncodingStrategy to enable.")
    }

    mutating func encode(_ value: Int8, forKey key: Key) throws {
        throw
            CSVEncodingError
            .unsupportedType("Nested types are not supported. Configure nestedTypeEncodingStrategy to enable.")
    }

    mutating func encode(_ value: Int16, forKey key: Key) throws {
        throw
            CSVEncodingError
            .unsupportedType("Nested types are not supported. Configure nestedTypeEncodingStrategy to enable.")
    }

    mutating func encode(_ value: Int32, forKey key: Key) throws {
        throw
            CSVEncodingError
            .unsupportedType("Nested types are not supported. Configure nestedTypeEncodingStrategy to enable.")
    }

    mutating func encode(_ value: Int64, forKey key: Key) throws {
        throw
            CSVEncodingError
            .unsupportedType("Nested types are not supported. Configure nestedTypeEncodingStrategy to enable.")
    }

    mutating func encode(_ value: UInt, forKey key: Key) throws {
        throw
            CSVEncodingError
            .unsupportedType("Nested types are not supported. Configure nestedTypeEncodingStrategy to enable.")
    }

    mutating func encode(_ value: UInt8, forKey key: Key) throws {
        throw
            CSVEncodingError
            .unsupportedType("Nested types are not supported. Configure nestedTypeEncodingStrategy to enable.")
    }

    mutating func encode(_ value: UInt16, forKey key: Key) throws {
        throw
            CSVEncodingError
            .unsupportedType("Nested types are not supported. Configure nestedTypeEncodingStrategy to enable.")
    }

    mutating func encode(_ value: UInt32, forKey key: Key) throws {
        throw
            CSVEncodingError
            .unsupportedType("Nested types are not supported. Configure nestedTypeEncodingStrategy to enable.")
    }

    mutating func encode(_ value: UInt64, forKey key: Key) throws {
        throw
            CSVEncodingError
            .unsupportedType("Nested types are not supported. Configure nestedTypeEncodingStrategy to enable.")
    }

    mutating func encode(_ value: some Encodable, forKey key: Key) throws {
        throw
            CSVEncodingError
            .unsupportedType("Nested types are not supported. Configure nestedTypeEncodingStrategy to enable.")
    }

    mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy _: NestedKey.Type,
        forKey _: Key
    ) -> KeyedEncodingContainer<NestedKey> {
        fatalError("Nested containers are not supported")
    }

    mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        fatalError("Nested containers are not supported")
    }

    mutating func superEncoder() -> Encoder {
        fatalError("Super encoder is not supported")
    }

    mutating func superEncoder(forKey key: Key) -> Encoder {
        fatalError("Super encoder is not supported")
    }
}

// MARK: - CSVSingleValueEncodingContainer

/// A single value container for CSV encoding.
nonisolated struct CSVSingleValueEncodingContainer: SingleValueEncodingContainer {
    // MARK: Lifecycle

    init(configuration: CSVEncoder.Configuration, codingPath: [CodingKey], storage: CSVEncodingStorage) {
        self.configuration = configuration
        self.codingPath = codingPath
        self.storage = storage
    }

    // MARK: Internal

    let configuration: CSVEncoder.Configuration
    let codingPath: [CodingKey]

    mutating func encodeNil() throws {
        storage.setValue("", forKey: currentKey)
    }

    mutating func encode(_ value: Bool) throws {
        storage.setValue(value ? "1" : "0", forKey: currentKey)
    }

    mutating func encode(_ value: String) throws {
        storage.setValue(value, forKey: currentKey)
    }

    mutating func encode(_ value: Double) throws {
        if value.isNaN || value.isInfinite {
            throw CSVEncodingError.invalidValue("Cannot encode \(value) as CSV field")
        }
        storage.setValue(String(value), forKey: currentKey)
    }

    mutating func encode(_ value: Float) throws {
        if value.isNaN || value.isInfinite {
            throw CSVEncodingError.invalidValue("Cannot encode \(value) as CSV field")
        }
        storage.setValue(String(value), forKey: currentKey)
    }

    mutating func encode(_ value: Int) throws {
        storage.setValue(String(value), forKey: currentKey)
    }

    mutating func encode(_ value: Int8) throws {
        storage.setValue(String(value), forKey: currentKey)
    }

    mutating func encode(_ value: Int16) throws {
        storage.setValue(String(value), forKey: currentKey)
    }

    mutating func encode(_ value: Int32) throws {
        storage.setValue(String(value), forKey: currentKey)
    }

    mutating func encode(_ value: Int64) throws {
        storage.setValue(String(value), forKey: currentKey)
    }

    mutating func encode(_ value: UInt) throws {
        storage.setValue(String(value), forKey: currentKey)
    }

    mutating func encode(_ value: UInt8) throws {
        storage.setValue(String(value), forKey: currentKey)
    }

    mutating func encode(_ value: UInt16) throws {
        storage.setValue(String(value), forKey: currentKey)
    }

    mutating func encode(_ value: UInt32) throws {
        storage.setValue(String(value), forKey: currentKey)
    }

    mutating func encode(_ value: UInt64) throws {
        storage.setValue(String(value), forKey: currentKey)
    }

    mutating func encode(_ value: some Encodable) throws {
        // Handle Date specially
        if let date = value as? Date {
            let encoded = try encodeDate(date)
            storage.setValue(encoded, forKey: currentKey)
            return
        }

        // Handle Decimal specially
        if let decimal = value as? Decimal {
            storage.setValue("\(decimal)", forKey: currentKey)
            return
        }

        // Handle UUID specially
        if let uuid = value as? UUID {
            storage.setValue(uuid.uuidString, forKey: currentKey)
            return
        }

        // Handle URL specially
        if let url = value as? URL {
            storage.setValue(url.absoluteString, forKey: currentKey)
            return
        }

        throw CSVEncodingError.unsupportedType("Cannot encode \(type(of: value)) as single CSV value")
    }

    // MARK: Private

    private let storage: CSVEncodingStorage

    private var currentKey: String {
        codingPath.last?.stringValue ?? ""
    }

    private func encodeDate(_ date: Date) throws -> String {
        try CSVValueFormatter.formatDate(date, strategy: configuration.dateEncodingStrategy)
    }
}

// MARK: - CSVEncodingStorage

/// Storage for encoded CSV values during encoding.
/// nonisolated with thread-safe access via NSLock
nonisolated final class CSVEncodingStorage: @unchecked Sendable {
    // MARK: Internal

    func setValue(_ value: String, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }

        if values[key] == nil {
            orderedKeys.append(key)
        }
        values[key] = value
    }

    func getValue(forKey key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func allKeys() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return orderedKeys
    }

    func allValues() -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        values.removeAll()
        orderedKeys.removeAll()
    }

    // MARK: Private

    private var values: [String: String] = [:]
    private var orderedKeys: [String] = []
    private let lock = NSLock()
}
