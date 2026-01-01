//
//  StreamingRowProcessor.swift
//  CSVCoder
//
//  Helper for processing CSV rows during streaming decoding.
//  Eliminates duplication in CSVDecoder+Backpressure.swift.
//

import Foundation

// MARK: - StreamingRowProcessor

/// Processes raw CSV rows into decoded values.
/// Handles header detection, dictionary building, and decoding.
struct StreamingRowProcessor<T: Decodable> {
    // MARK: Lifecycle

    init(configuration: CSVDecoder.Configuration) {
        self.configuration = configuration
    }

    // MARK: Internal

    /// Processes a raw CSV row and returns a decoded value.
    /// Returns nil for the header row (when `hasHeaders` is true).
    ///
    /// - Parameter row: The raw CSV row as an array of strings.
    /// - Returns: The decoded value, or nil if this was the header row.
    /// - Throws: `CSVDecodingError` if decoding fails.
    mutating func process(_ row: [String]) throws -> T? {
        // Handle headers on first row
        if headers == nil {
            if configuration.hasHeaders {
                headers = row
                return nil
            } else {
                headers = (0 ..< row.count).map { "column\($0)" }
            }
        }

        guard let headerRow = headers else { return nil }

        // Build dictionary for row
        var dictionary: [String: String] = [:]
        dictionary.reserveCapacity(headerRow.count)
        for (index, header) in headerRow.enumerated() {
            if index < row.count {
                dictionary[header] = row[index]
            }
        }

        // Decode row
        let decoder = CSVRowDecoder(
            row: dictionary,
            configuration: configuration,
            codingPath: [],
        )
        return try T(from: decoder)
    }

    // MARK: Private

    private let configuration: CSVDecoder.Configuration
    private var headers: [String]?
}
