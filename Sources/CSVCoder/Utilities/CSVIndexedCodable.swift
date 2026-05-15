//
//  CSVIndexedCodable.swift
//  CSVCoder
//
//  Protocols and aliases that let a `Codable` type declare its CSV row layout.
//

import Foundation

// MARK: - _CSVRowMarker

/// Internal marker protocol for runtime conformance detection.
///
/// Carries no associated types so `as?` casting works at runtime — this is how
/// the decoder discovers a type's declared column order without requiring
/// callers to thread a generic constraint through every API.
///
/// The leading underscore signals "internal contract, not a stable API"; the
/// protocol is `public` only because the `@CSVRow` macro emits conformances
/// in user modules.
public protocol _CSVRowMarker {
    static var _csvColumnOrder: [String] { get }
}

// MARK: - CSVRowConvertible

/// Base protocol shared by ``CSVRowDecodable`` and ``CSVRowEncodable``.
///
/// Provides the canonical column order derived from a `CaseIterable`
/// `CodingKeys` enum. Conformers rarely write this by hand — the `@CSVRow`
/// macro generates everything needed.
public protocol CSVRowConvertible: _CSVRowMarker {
    /// The `CodingKeys` type, which must be `CaseIterable` so the library can
    /// enumerate column positions.
    associatedtype CSVCodingKeys: CodingKey, CaseIterable

    /// The CSV column order, derived by default from `CSVCodingKeys.allCases`.
    static var csvColumnOrder: [String] { get }
}

extension CSVRowConvertible {
    /// Default implementation: extracts column names from `CSVCodingKeys.allCases`
    /// in declaration order.
    public static var csvColumnOrder: [String] {
        CSVCodingKeys.allCases.map(\.stringValue)
    }

    /// Marker-protocol bridge used by the decoder's runtime dispatch.
    public static var _csvColumnOrder: [String] { csvColumnOrder }
}

// MARK: - CSVRowDecodable

/// A `Decodable` type that maps to a single CSV row with explicit column
/// ordering.
///
/// Conform when decoding **headerless** CSV files: the order of cases in your
/// `CodingKeys` enum determines which CSV column populates which property.
/// With a header row, the conformance is harmless — the decoder uses the
/// header names as usual.
///
/// ```swift
/// struct Person: CSVRowDecodable {
///     let name: String
///     let age: Int
///     let score: Double
///
///     enum CodingKeys: String, CodingKey, CaseIterable {
///         case name, age, score
///     }
///     typealias CSVCodingKeys = CodingKeys
/// }
///
/// // No `indexMapping` needed — the decoder detects the conformance at runtime.
/// let config = CSVDecoder.Configuration(hasHeaders: false)
/// let decoder = CSVDecoder(configuration: config)
/// let people = try decoder.decode([Person].self, from: csv)
/// ```
///
/// The `@CSVRow` macro generates this conformance automatically.
public protocol CSVRowDecodable: Decodable, CSVRowConvertible {}

// MARK: - CSVRowEncodable

/// An `Encodable` type whose CSV column order is declared via its
/// `CodingKeys`.
///
/// The order of cases in `CodingKeys` defines the column order produced by
/// any encode entry point (sync, streaming, parallel). The `@CSVRow` macro
/// generates this conformance automatically.
public protocol CSVRowEncodable: Encodable, CSVRowConvertible {}

// MARK: - Combined alias

/// A `Codable` type that maps to a CSV row in either direction.
public typealias CSVRowCodable = CSVRowDecodable & CSVRowEncodable

// MARK: - Internal helpers

extension CSVDecoder {
    /// Extracts column order from a ``CSVRowDecodable`` type.
    func columnOrder<T: CSVRowDecodable>(for type: T.Type) -> [String] {
        T.csvColumnOrder
    }

    /// Builds an `[Int: String]` mapping from a ``CSVRowDecodable`` type's
    /// column order, for callers that prefer the dictionary shape.
    func indexMapping<T: CSVRowDecodable>(for type: T.Type) -> [Int: String] {
        let columns = T.csvColumnOrder
        var mapping: [Int: String] = [:]
        for (index, column) in columns.enumerated() {
            mapping[index] = column
        }
        return mapping
    }
}

// MARK: - Deprecated aliases (one-cycle migration)

@available(*, deprecated, renamed: "_CSVRowMarker")
public typealias _CSVIndexedMarker = _CSVRowMarker

@available(*, deprecated, renamed: "CSVRowConvertible")
public typealias CSVIndexedBase = CSVRowConvertible

@available(*, deprecated, renamed: "CSVRowDecodable")
public typealias CSVIndexedDecodable = CSVRowDecodable

@available(*, deprecated, renamed: "CSVRowEncodable")
public typealias CSVIndexedEncodable = CSVRowEncodable

@available(*, deprecated, renamed: "CSVRowCodable")
public typealias CSVIndexedCodable = CSVRowCodable
