//
//  CSVSingleValueEncoder.swift
//  CSVCoder
//
//  Implements single value encoding for CSV fields.
//

import Foundation

/// An encoder for single values in CSV fields.
/// nonisolated utility type for encoding
nonisolated struct CSVSingleValueEncoder: Encoder {
    let configuration: CSVEncoder.Configuration
    let codingPath: [CodingKey]
    nonisolated var userInfo: [CodingUserInfoKey: Any] { [:] }

    private let storage: CSVEncodingStorage

    init(configuration: CSVEncoder.Configuration, codingPath: [CodingKey], storage: CSVEncodingStorage) {
        self.configuration = configuration
        self.codingPath = codingPath
        self.storage = storage
    }

    nonisolated func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        fatalError("Keyed containers not supported for single values")
    }

    nonisolated func unkeyedContainer() -> UnkeyedEncodingContainer {
        fatalError("Unkeyed containers not supported for single values")
    }

    nonisolated func singleValueContainer() -> SingleValueEncodingContainer {
        CSVSingleValueEncodingContainer(configuration: configuration, codingPath: codingPath, storage: storage)
    }
}

/// A single value container for CSV encoding.
nonisolated struct CSVSingleValueEncodingContainer: SingleValueEncodingContainer {
    let configuration: CSVEncoder.Configuration
    let codingPath: [CodingKey]
    private let storage: CSVEncodingStorage

    init(configuration: CSVEncoder.Configuration, codingPath: [CodingKey], storage: CSVEncodingStorage) {
        self.configuration = configuration
        self.codingPath = codingPath
        self.storage = storage
    }

    private var currentKey: String {
        codingPath.last?.stringValue ?? ""
    }

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

    mutating func encode<T: Encodable>(_ value: T) throws {
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

        case .formatted(let format):
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            return formatter.string(from: date)

        case .custom(let closure):
            return try closure(date)
        }
    }
}

/// Storage for encoded CSV values during encoding.
/// nonisolated with thread-safe access via NSLock
nonisolated final class CSVEncodingStorage: @unchecked Sendable {
    private var values: [String: String] = [:]
    private var orderedKeys: [String] = []
    private let lock = NSLock()

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
}
