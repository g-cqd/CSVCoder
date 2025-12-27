//
//  CSVEncoder+Streaming.swift
//  CSVCoder
//
//  Streaming encode extension for handling large datasets.
//  Provides O(1) memory usage via incremental row encoding.
//

import Foundation

extension CSVEncoder {
    // MARK: - Streaming to File

    /// Stream encodes values from an async sequence to a file.
    /// Uses O(1) memory regardless of dataset size.
    ///
    /// - Parameters:
    ///   - values: An async sequence of encodable values.
    ///   - url: The file URL to write to.
    ///   - bufferSize: The write buffer size in bytes. Default is 64KB.
    /// - Throws: `CSVEncodingError` if encoding fails.
    ///
    /// - Example:
    /// ```swift
    /// let encoder = CSVEncoder()
    /// let records = AsyncStream { continuation in
    ///     for record in generateRecords() {
    ///         continuation.yield(record)
    ///     }
    ///     continuation.finish()
    /// }
    /// try await encoder.encode(records, to: fileURL)
    /// ```
    public func encode<S: AsyncSequence>(
        _ values: S,
        to url: URL,
        bufferSize: Int = 65_536
    ) async throws where S.Element: Encodable & Sendable {
        // Create or truncate the file
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        try await encode(values, to: handle, bufferSize: bufferSize)
    }

    /// Stream encodes values from an async sequence to a file handle.
    ///
    /// - Parameters:
    ///   - values: An async sequence of encodable values.
    ///   - handle: The file handle to write to.
    ///   - bufferSize: The write buffer size in bytes.
    public func encode<S: AsyncSequence>(
        _ values: S,
        to handle: FileHandle,
        bufferSize: Int = 65_536
    ) async throws where S.Element: Encodable & Sendable {
        var writer = BufferedCSVWriter(handle: handle, bufferSize: bufferSize)
        let rowBuilder = CSVRowBuilder(delimiter: configuration.delimiter, lineEnding: configuration.lineEnding)

        var keys: [String]?
        var rowBuffer: [UInt8] = []
        rowBuffer.reserveCapacity(1024)

        for try await value in values {
            let (row, orderedKeys) = try encodeValue(value)

            // Write header on first row
            if keys == nil {
                keys = orderedKeys
                if configuration.includeHeaders {
                    rowBuilder.buildHeader(orderedKeys, into: &rowBuffer)
                    try writer.write(contentsOf: rowBuffer)
                    rowBuffer.removeAll(keepingCapacity: true)
                }
            }

            // Build and write row
            let fields = orderedKeys.map { row[$0] ?? "" }
            rowBuilder.buildRow(fields, into: &rowBuffer)
            try writer.write(contentsOf: rowBuffer)
            rowBuffer.removeAll(keepingCapacity: true)
        }

        try writer.flush()
    }

    // MARK: - Streaming Array to File

    /// Stream encodes an array to a file with O(1) memory.
    /// Unlike `encode(_:)`, this writes incrementally instead of building the entire output in memory.
    ///
    /// - Parameters:
    ///   - values: The values to encode.
    ///   - url: The file URL to write to.
    ///   - bufferSize: The write buffer size in bytes.
    public func encode<T: Encodable & Sendable>(
        _ values: [T],
        to url: URL,
        bufferSize: Int = 65_536
    ) async throws {
        let stream = AsyncStream { continuation in
            for value in values {
                continuation.yield(value)
            }
            continuation.finish()
        }
        try await encode(stream, to: url, bufferSize: bufferSize)
    }

    // MARK: - Streaming to AsyncStream

    /// Encodes values and yields rows as an async stream.
    /// Useful for piping to network streams or other async consumers.
    ///
    /// - Parameter values: An async sequence of encodable values.
    /// - Returns: An async throwing stream of CSV row strings.
    public func encodeToStream<S: AsyncSequence>(
        _ values: S
    ) -> AsyncThrowingStream<String, Error> where S.Element: Encodable & Sendable, S: Sendable {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var keys: [String]?
                    let delimiter = String(configuration.delimiter)
                    let lineEnding = configuration.lineEnding.rawValue

                    for try await value in values {
                        let (row, orderedKeys) = try encodeValue(value)

                        // Yield header on first row
                        if keys == nil {
                            keys = orderedKeys
                            if configuration.includeHeaders {
                                let headerRow = orderedKeys.map { escapeField($0) }.joined(separator: delimiter)
                                continuation.yield(headerRow + lineEnding)
                            }
                        }

                        // Yield data row
                        let fields = orderedKeys.map { escapeField(row[$0] ?? "") }
                        let rowString = fields.joined(separator: delimiter) + lineEnding
                        continuation.yield(rowString)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    // MARK: - Row-by-Row Encoding

    /// Encodes a single value to an ordered dictionary.
    /// Returns both the dictionary and the key order.
    func encodeValue<T: Encodable>(_ value: T) throws -> (row: [String: String], keys: [String]) {
        let storage = CSVEncodingStorage()
        let encoder = CSVRowEncoder(configuration: configuration, storage: storage)
        try value.encode(to: encoder)
        return (storage.allValues(), storage.allKeys())
    }
}
