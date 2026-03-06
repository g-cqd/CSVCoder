//
//  CSVPoisonContainers.swift
//  CSVCoder
//
//  Poison-pill containers that throw stored errors on use.
//  Used instead of fatalError() in non-throwing Encoder protocol methods.
//

import Foundation

// MARK: - CSVPoisonEncoder

/// An encoder that throws a stored error on any container request.
nonisolated struct CSVPoisonEncoder: Encoder {
    let error: CSVEncodingError
    let codingPath: [CodingKey]

    nonisolated var userInfo: [CodingUserInfoKey: Any] { [:] }

    nonisolated func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        KeyedEncodingContainer(CSVPoisonKeyedEncodingContainer<Key>(error: error, codingPath: codingPath))
    }

    nonisolated func unkeyedContainer() -> UnkeyedEncodingContainer {
        CSVPoisonUnkeyedEncodingContainer(error: error, codingPath: codingPath)
    }

    nonisolated func singleValueContainer() -> SingleValueEncodingContainer {
        CSVPoisonSingleValueEncodingContainer(error: error, codingPath: codingPath)
    }
}

// MARK: - CSVPoisonKeyedEncodingContainer

/// A keyed encoding container that throws a stored error on any encode call.
nonisolated struct CSVPoisonKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let error: CSVEncodingError
    let codingPath: [CodingKey]

    mutating func encodeNil(forKey key: Key) throws { throw error }
    mutating func encode(_ value: Bool, forKey key: Key) throws { throw error }
    mutating func encode(_ value: String, forKey key: Key) throws { throw error }
    mutating func encode(_ value: Double, forKey key: Key) throws { throw error }
    mutating func encode(_ value: Float, forKey key: Key) throws { throw error }
    mutating func encode(_ value: Int, forKey key: Key) throws { throw error }
    mutating func encode(_ value: Int8, forKey key: Key) throws { throw error }
    mutating func encode(_ value: Int16, forKey key: Key) throws { throw error }
    mutating func encode(_ value: Int32, forKey key: Key) throws { throw error }
    mutating func encode(_ value: Int64, forKey key: Key) throws { throw error }
    mutating func encode(_ value: UInt, forKey key: Key) throws { throw error }
    mutating func encode(_ value: UInt8, forKey key: Key) throws { throw error }
    mutating func encode(_ value: UInt16, forKey key: Key) throws { throw error }
    mutating func encode(_ value: UInt32, forKey key: Key) throws { throw error }
    mutating func encode(_ value: UInt64, forKey key: Key) throws { throw error }
    mutating func encode(_ value: some Encodable, forKey key: Key) throws { throw error }

    mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy _: NestedKey.Type,
        forKey _: Key
    ) -> KeyedEncodingContainer<NestedKey> {
        KeyedEncodingContainer(CSVPoisonKeyedEncodingContainer<NestedKey>(error: error, codingPath: codingPath))
    }

    mutating func nestedUnkeyedContainer(forKey _: Key) -> UnkeyedEncodingContainer {
        CSVPoisonUnkeyedEncodingContainer(error: error, codingPath: codingPath)
    }

    mutating func superEncoder() -> Encoder {
        CSVPoisonEncoder(error: error, codingPath: codingPath)
    }

    mutating func superEncoder(forKey _: Key) -> Encoder {
        CSVPoisonEncoder(error: error, codingPath: codingPath)
    }
}

// MARK: - CSVPoisonUnkeyedEncodingContainer

/// An unkeyed encoding container that throws a stored error on any encode call.
nonisolated struct CSVPoisonUnkeyedEncodingContainer: UnkeyedEncodingContainer {
    let error: CSVEncodingError
    let codingPath: [CodingKey]
    var count: Int { 0 }

    mutating func encodeNil() throws { throw error }
    mutating func encode(_ value: Bool) throws { throw error }
    mutating func encode(_ value: String) throws { throw error }
    mutating func encode(_ value: Double) throws { throw error }
    mutating func encode(_ value: Float) throws { throw error }
    mutating func encode(_ value: Int) throws { throw error }
    mutating func encode(_ value: Int8) throws { throw error }
    mutating func encode(_ value: Int16) throws { throw error }
    mutating func encode(_ value: Int32) throws { throw error }
    mutating func encode(_ value: Int64) throws { throw error }
    mutating func encode(_ value: UInt) throws { throw error }
    mutating func encode(_ value: UInt8) throws { throw error }
    mutating func encode(_ value: UInt16) throws { throw error }
    mutating func encode(_ value: UInt32) throws { throw error }
    mutating func encode(_ value: UInt64) throws { throw error }
    mutating func encode(_ value: some Encodable) throws { throw error }

    mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy _: NestedKey.Type
    ) -> KeyedEncodingContainer<NestedKey> {
        KeyedEncodingContainer(CSVPoisonKeyedEncodingContainer<NestedKey>(error: error, codingPath: codingPath))
    }

    mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        self
    }

    mutating func superEncoder() -> Encoder {
        CSVPoisonEncoder(error: error, codingPath: codingPath)
    }
}

// MARK: - CSVPoisonSingleValueEncodingContainer

/// A single-value encoding container that throws a stored error on any encode call.
nonisolated struct CSVPoisonSingleValueEncodingContainer: SingleValueEncodingContainer {
    let error: CSVEncodingError
    let codingPath: [CodingKey]

    mutating func encodeNil() throws { throw error }
    mutating func encode(_ value: Bool) throws { throw error }
    mutating func encode(_ value: String) throws { throw error }
    mutating func encode(_ value: Double) throws { throw error }
    mutating func encode(_ value: Float) throws { throw error }
    mutating func encode(_ value: Int) throws { throw error }
    mutating func encode(_ value: Int8) throws { throw error }
    mutating func encode(_ value: Int16) throws { throw error }
    mutating func encode(_ value: Int32) throws { throw error }
    mutating func encode(_ value: Int64) throws { throw error }
    mutating func encode(_ value: UInt) throws { throw error }
    mutating func encode(_ value: UInt8) throws { throw error }
    mutating func encode(_ value: UInt16) throws { throw error }
    mutating func encode(_ value: UInt32) throws { throw error }
    mutating func encode(_ value: UInt64) throws { throw error }
    mutating func encode(_ value: some Encodable) throws { throw error }
}
