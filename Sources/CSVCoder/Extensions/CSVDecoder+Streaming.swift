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
        from url: URL,
    ) -> AsyncThrowingStream<T, Error> {
        // Runtime detection of CSVIndexedDecodable conformance
        let columnOrder = (T.self as? _CSVIndexedMarker.Type)?._csvColumnOrder
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
        from data: Data,
    ) -> AsyncThrowingStream<T, Error> {
        // Runtime detection of CSVIndexedDecodable conformance
        let columnOrder = (T.self as? _CSVIndexedMarker.Type)?._csvColumnOrder
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
        from url: URL,
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
        columnOrder: [String]?,
    ) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let reader = try MemoryMappedReader(url: url)
                    try self.decodeFromReader(reader, columnOrder: columnOrder, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func decodeFromReader<T: Decodable & Sendable>(
        _ reader: MemoryMappedReader,
        columnOrder: [String]?,
        continuation: AsyncThrowingStream<T, Error>.Continuation,
    ) throws {
        reader.withUnsafeBytes { buffer in
            guard let bytes = CSVUtilities.adjustedBuffer(from: buffer) else {
                continuation.finish()
                return
            }
            let delimiter = configuration.delimiter.asciiValue ?? 0x2C

            let parser = CSVParser(buffer: bytes, delimiter: delimiter)
            var iterator = parser.makeIterator()
            var headers: [String]?
            var headerMap: [String: Int]?
            var rowIndex = 0

            let isStrict = configuration.parsingMode == .strict
            let expectedFieldCount = configuration.expectedFieldCount

            while let rowView = iterator.next() {
                // Check for unterminated quotes (always an error)
                if rowView.hasUnterminatedQuote {
                    continuation.finish(
                        throwing: CSVDecodingError.parsingError(
                            "Unterminated quoted field",
                            line: rowIndex + 1,
                            column: nil,
                        )
                    )
                    return
                }

                // Strict mode: reject quotes in unquoted fields
                if isStrict, rowView.hasQuoteInUnquotedField {
                    continuation.finish(
                        throwing: CSVDecodingError.parsingError(
                            "Quote character in unquoted field (RFC 4180 violation)",
                            line: rowIndex + 1,
                            column: nil,
                        )
                    )
                    return
                }

                // Strict mode: validate field count
                if isStrict, let expected = expectedFieldCount, rowView.count != expected {
                    continuation.finish(
                        throwing: CSVDecodingError.parsingError(
                            "Expected \(expected) fields but found \(rowView.count)",
                            line: rowIndex + 1,
                            column: nil,
                        )
                    )
                    return
                }

                if headers == nil {
                    // Extract potential headers
                    var firstRowStrings: [String] = []
                    firstRowStrings.reserveCapacity(rowView.count)
                    for i in 0 ..< rowView.count {
                        if let s = rowView.string(at: i) {
                            firstRowStrings.append(s)
                        } else {
                            firstRowStrings.append("column\(i)")
                        }
                    }

                    let resolvedHeaders = self.resolveHeaders(
                        rawHeaders: firstRowStrings,
                        columnOrder: columnOrder,
                        columnCount: rowView.count,
                    )
                    headers = resolvedHeaders

                    // Build map
                    var map: [String: Int] = [:]
                    for (index, header) in resolvedHeaders.enumerated() {
                        map[header] = index
                    }
                    headerMap = map

                    if configuration.hasHeaders {
                        rowIndex += 1
                        continue
                    }
                }

                guard let map = headerMap else { continue }

                let decoder = CSVRowDecoder(
                    view: rowView,
                    headerMap: map,
                    configuration: configuration,
                    codingPath: [],
                    rowIndex: rowIndex + 1,
                )

                do {
                    let value = try T(from: decoder)
                    continuation.yield(value)
                } catch {
                    continuation.finish(throwing: error)
                    return
                }

                rowIndex += 1
            }
            continuation.finish()
        }
    }

    private func streamDecode<T: Decodable & Sendable>(
        _ type: T.Type,
        from data: Data,
        columnOrder: [String]?,
    ) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let reader = MemoryMappedReader(data: data)
                    try self.decodeFromReader(reader, columnOrder: columnOrder, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
