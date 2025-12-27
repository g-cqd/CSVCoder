//
//  CSVDecoder+Streaming.swift
//  CSVCoder
//
//  Streaming decode extension for handling large CSV files.
//  Provides O(1) memory usage via AsyncThrowingStream.
//

import Foundation

extension CSVDecoder {
    /// Decodes values from a CSV file URL, yielding each row as it's parsed.
    /// Uses memory-mapped I/O for O(1) memory usage regardless of file size.
    ///
    /// For headerless CSV, the decoder automatically detects `CSVIndexedDecodable`
    /// conformance and uses the type's `CodingKeys` order for column mapping.
    ///
    /// - Parameters:
    ///   - type: The type to decode.
    ///   - url: The file URL to read CSV data from.
    /// - Returns: An `AsyncThrowingStream` that yields decoded values one at a time.
    ///
    /// - Example:
    /// ```swift
    /// let decoder = CSVDecoder()
    /// for try await record in decoder.decode(Record.self, from: fileURL) {
    ///     process(record)
    /// }
    /// ```
    public func decode<T: Decodable & Sendable>(
        _ type: T.Type,
        from url: URL
    ) -> AsyncThrowingStream<T, Error> {
        // Runtime detection of CSVIndexedDecodable conformance
        let columnOrder = (T.self as? _CSVIndexedDecodableMarker.Type)?._csvColumnOrder
        return streamDecode(type, from: url, columnOrder: columnOrder)
    }

    /// Decodes values from CSV Data, yielding each row as it's parsed.
    /// Uses streaming parser for efficient memory usage.
    ///
    /// For headerless CSV, the decoder automatically detects `CSVIndexedDecodable`
    /// conformance and uses the type's `CodingKeys` order for column mapping.
    ///
    /// - Parameters:
    ///   - type: The type to decode.
    ///   - data: The CSV data to decode.
    /// - Returns: An `AsyncThrowingStream` that yields decoded values one at a time.
    public func decode<T: Decodable & Sendable>(
        _ type: T.Type,
        from data: Data
    ) -> AsyncThrowingStream<T, Error> {
        // Runtime detection of CSVIndexedDecodable conformance
        let columnOrder = (T.self as? _CSVIndexedDecodableMarker.Type)?._csvColumnOrder
        return streamDecode(type, from: data, columnOrder: columnOrder)
    }

    /// Decodes all values from a CSV file URL into an array.
    /// Convenience async method that collects all streamed results.
    ///
    /// For headerless CSV, the decoder automatically detects `CSVIndexedDecodable`
    /// conformance and uses the type's `CodingKeys` order for column mapping.
    ///
    /// - Parameters:
    ///   - type: The array type to decode.
    ///   - url: The file URL to read CSV data from.
    /// - Returns: An array of all decoded values.
    ///
    /// - Note: For very large files, prefer the streaming `decode(_:from:)` method
    ///   to avoid loading all records into memory.
    public func decode<T: Decodable & Sendable>(
        _ type: [T].Type,
        from url: URL
    ) async throws -> [T] {
        var results: [T] = []
        for try await value in decode(T.self, from: url) {
            results.append(value)
        }
        return results
    }

    // MARK: - Internal Streaming Helpers

    private func streamDecode<T: Decodable & Sendable>(
        _ type: T.Type,
        from url: URL,
        columnOrder: [String]?
    ) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let parser = try StreamingCSVParser(url: url, configuration: configuration)
                    var iterator = parser.makeAsyncIterator()
                    var headers: [String]?

                    while let row = try await iterator.next() {
                        if headers == nil {
                            headers = self.resolveHeaders(
                                firstRow: row,
                                columnOrder: columnOrder
                            )
                            if configuration.hasHeaders { continue }
                        }

                        guard let headerRow = headers else { continue }

                        var dictionary: [String: String] = [:]
                        dictionary.reserveCapacity(headerRow.count)
                        for (index, header) in headerRow.enumerated() {
                            if index < row.count {
                                dictionary[header] = row[index]
                            }
                        }

                        let decoder = CSVRowDecoder(
                            row: dictionary,
                            configuration: configuration,
                            codingPath: []
                        )
                        let value = try T(from: decoder)
                        continuation.yield(value)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func streamDecode<T: Decodable & Sendable>(
        _ type: T.Type,
        from data: Data,
        columnOrder: [String]?
    ) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let parser = StreamingCSVParser(data: data, configuration: configuration)
                    var iterator = parser.makeAsyncIterator()
                    var headers: [String]?

                    while let row = try await iterator.next() {
                        if headers == nil {
                            headers = self.resolveHeaders(
                                firstRow: row,
                                columnOrder: columnOrder
                            )
                            if configuration.hasHeaders { continue }
                        }

                        guard let headerRow = headers else { continue }

                        var dictionary: [String: String] = [:]
                        dictionary.reserveCapacity(headerRow.count)
                        for (index, header) in headerRow.enumerated() {
                            if index < row.count {
                                dictionary[header] = row[index]
                            }
                        }

                        let decoder = CSVRowDecoder(
                            row: dictionary,
                            configuration: configuration,
                            codingPath: []
                        )
                        let value = try T(from: decoder)
                        continuation.yield(value)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Resolves headers based on configuration priority:
    /// indexMapping > columnOrder (CSVIndexedDecodable) > hasHeaders > generated
    private func resolveHeaders(firstRow: [String], columnOrder: [String]?) -> [String] {
        if !configuration.indexMapping.isEmpty {
            // Explicit index mapping takes precedence
            let maxIndex = configuration.indexMapping.keys.max() ?? 0
            return (0...maxIndex).map { configuration.indexMapping[$0] ?? "column\($0)" }
        } else if configuration.hasHeaders {
            // Use first row as headers with key transformation
            return firstRow.map { transformKey($0) }
        } else if let columnOrder = columnOrder {
            // Use CSVIndexedDecodable column order
            return columnOrder
        } else {
            // Generate column names
            return (0..<firstRow.count).map { "column\($0)" }
        }
    }
}
