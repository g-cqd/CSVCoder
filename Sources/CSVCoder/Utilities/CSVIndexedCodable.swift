//
//  CSVIndexedCodable.swift
//  CSVCoder
//
//  Protocol for types that define column order via CaseIterable CodingKeys.
//  Eliminates the need for manual indexMapping configuration.
//

import Foundation

// MARK: - Internal Runtime Detection

/// Internal marker protocol for runtime conformance detection.
/// Has no associated types, enabling `as?` casting at runtime.
/// Public to allow protocol refinement but prefixed with underscore to signal internal use.
public protocol _CSVIndexedMarker {
    static var _csvColumnOrder: [String] { get }
}

// MARK: - Base Protocol

/// Base protocol providing the common requirements for CSV indexed types.
/// Both CSVIndexedDecodable and CSVIndexedEncodable refine this protocol.
public protocol CSVIndexedBase: _CSVIndexedMarker {
    /// The CodingKeys type, which must be CaseIterable to define column order.
    associatedtype CSVCodingKeys: CodingKey & CaseIterable

    /// Returns the ordered column names derived from CodingKeys.
    /// Default implementation uses `CSVCodingKeys.allCases`.
    static var csvColumnOrder: [String] { get }
}

extension CSVIndexedBase {
    /// Default implementation: extracts column names from CodingKeys.allCases in order.
    public static var csvColumnOrder: [String] {
        CSVCodingKeys.allCases.map { $0.stringValue }
    }

    /// Internal marker implementation for runtime detection.
    public static var _csvColumnOrder: [String] { csvColumnOrder }
}

// MARK: - CSVIndexedDecodable Protocol

/// A type that can be decoded from headerless CSV using the order of its CodingKeys.
///
/// Conform to this protocol when decoding CSV files without headers. The order of
/// cases in your `CodingKeys` enum defines the column order.
///
/// ```swift
/// struct Person: CSVIndexedDecodable {
///     let name: String
///     let age: Int
///     let score: Double
///
///     enum CodingKeys: String, CodingKey, CaseIterable {
///         case name, age, score  // Column 0, 1, 2
///     }
///     typealias CSVCodingKeys = CodingKeys
/// }
///
/// // Decode headerless CSV - no indexMapping needed
/// let config = CSVDecoder.Configuration(hasHeaders: false)
/// let decoder = CSVDecoder(configuration: config)
/// let people = try decoder.decode([Person].self, from: csv)
/// ```
///
/// - Note: The decoder automatically detects conformance at runtime.
///   You can use the standard `decode([T].self, from:)` method.
public protocol CSVIndexedDecodable: Decodable, CSVIndexedBase {}

// MARK: - CSVIndexedEncodable Protocol

/// A type that can be encoded to CSV with columns in the order of its CodingKeys.
///
/// The encoding order matches the order of cases in your `CodingKeys` enum.
public protocol CSVIndexedEncodable: Encodable, CSVIndexedBase {}

// MARK: - Combined Protocol

/// A type that can be both encoded and decoded with ordered CSV columns.
public typealias CSVIndexedCodable = CSVIndexedDecodable & CSVIndexedEncodable

// MARK: - Internal Helpers

extension CSVDecoder {
    /// Extracts column order from a CSVIndexedDecodable type.
    func columnOrder<T: CSVIndexedDecodable>(for type: T.Type) -> [String] {
        T.csvColumnOrder
    }

    /// Builds index mapping from CSVIndexedDecodable column order.
    func indexMapping<T: CSVIndexedDecodable>(for type: T.Type) -> [Int: String] {
        let columns = T.csvColumnOrder
        var mapping: [Int: String] = [:]
        for (index, column) in columns.enumerated() {
            mapping[index] = column
        }
        return mapping
    }
}
