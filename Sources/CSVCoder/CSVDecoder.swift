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
        /// The delimiter character used to separate fields. Default is semicolon (;).
        public var delimiter: Character

        /// Whether the first row contains headers. Default is true.
        public var hasHeaders: Bool

        /// The encoding to use when reading data. Default is UTF-8.
        public var encoding: String.Encoding

        /// Whether to trim whitespace from field values. Default is true.
        public var trimWhitespace: Bool

        /// The date decoding strategy.
        public var dateDecodingStrategy: DateDecodingStrategy

        /// Creates a new configuration with default values.
        public init(
            delimiter: Character = ";",
            hasHeaders: Bool = true,
            encoding: String.Encoding = .utf8,
            trimWhitespace: Bool = true,
            dateDecodingStrategy: DateDecodingStrategy = .deferredToDate
        ) {
            self.delimiter = delimiter
            self.hasHeaders = hasHeaders
            self.encoding = encoding
            self.trimWhitespace = trimWhitespace
            self.dateDecodingStrategy = dateDecodingStrategy
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
    }

    /// The configuration used for decoding.
    public let configuration: Configuration

    /// Creates a new CSV decoder with the given configuration.
    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Decodes an array of values from the given CSV data.
    /// - Parameters:
    ///   - type: The type to decode.
    ///   - data: The CSV data to decode.
    /// - Returns: An array of decoded values.
    public func decode<T: Decodable>(_ type: [T].Type, from data: Data) throws -> [T] {
        guard let string = String(data: data, encoding: configuration.encoding) else {
            throw CSVDecodingError.invalidEncoding
        }
        return try decode(type, from: string)
    }

    /// Decodes an array of values from the given CSV string.
    /// - Parameters:
    ///   - type: The type to decode.
    ///   - string: The CSV string to decode.
    /// - Returns: An array of decoded values.
    public func decode<T: Decodable>(_ type: [T].Type, from string: String) throws -> [T] {
        let parser = CSVParser(string: string, configuration: configuration)
        let rows = try parser.parse()

        guard !rows.isEmpty else { return [] }

        let headers: [String]
        let dataRows: [[String]]

        if configuration.hasHeaders {
            headers = rows[0]
            dataRows = Array(rows.dropFirst())
        } else {
            headers = (0..<(rows.first?.count ?? 0)).map { "column\($0)" }
            dataRows = rows
        }

        return try dataRows.compactMap { row in
            var dictionary: [String: String] = [:]
            for (index, header) in headers.enumerated() {
                if index < row.count {
                    dictionary[header] = row[index]
                }
            }
            let decoder = CSVRowDecoder(
                row: dictionary,
                configuration: configuration,
                codingPath: []
            )
            return try T(from: decoder)
        }
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
}
