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
///
/// Handles header detection, dictionary building, and decoding.
struct StreamingRowProcessor<T: Decodable> {
    // MARK: Lifecycle

    init(configuration: CSVDecoder.Configuration) {
        self.configuration = configuration
        // Build a top-level decoder once so we can route the first row through
        // its `resolveHeaders` — that path applies `indexMapping`,
        // `columnMapping`, and `keyDecodingStrategy` consistently with the
        // non-streaming code in `CSVDecoder.decode(_:from:)`. Without this,
        // streaming callers silently get the raw header strings.
        self.decoder = CSVDecoder(configuration: configuration)
    }

    // MARK: Internal

    /// Processes a raw CSV row and returns a decoded value.
    ///
    /// Returns nil for the header row (when `hasHeaders` is true).
    ///
    /// - Parameter row: The raw CSV row as an array of strings.
    /// - Returns: The decoded value, or nil if this was the header row.
    /// - Throws: `CSVDecodingError` if decoding fails.
    mutating func process(_ row: [String]) throws -> T? {
        // Handle headers on first row
        if headers == nil {
            if configuration.hasHeaders {
                headers = decoder.resolveHeaders(
                    rawHeaders: row,
                    columnOrder: nil,
                    columnCount: row.count
                )
                return nil
            } else {
                headers = decoder.resolveHeaders(
                    rawHeaders: (0..<row.count).map { "column\($0)" },
                    columnOrder: nil,
                    columnCount: row.count
                )
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
        let rowDecoder = CSVRowDecoder(
            row: dictionary,
            configuration: configuration,
            codingPath: [],
        )
        return try T(from: rowDecoder)
    }

    // MARK: Private

    private let configuration: CSVDecoder.Configuration
    private let decoder: CSVDecoder
    private var headers: [String]?
}
