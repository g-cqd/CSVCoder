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
        bufferSize: Int = 65536,
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
        bufferSize: Int = 65536,
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
                let transformedKeys = orderedKeys.map { transformKey($0) }
                keys = transformedKeys
                if configuration.hasHeaders {
                    rowBuilder.buildHeader(transformedKeys, into: &rowBuffer)
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
    public func encode(
        _ values: [some Encodable & Sendable],
        to url: URL,
        bufferSize: Int = 65536,
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
        _ values: S,
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
                            keys = orderedKeys.map { self.transformKey($0) }
                            if configuration.hasHeaders {
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
    internal func encodeValue(_ value: some Encodable) throws -> (row: [String: String], keys: [String]) {
        let storage = CSVEncodingStorage()
        let encoder = CSVRowEncoder(configuration: configuration, storage: storage)
        try value.encode(to: encoder)
        return (storage.allValues(), storage.allKeys())
    }

    /// Processes encoding and header initialization for async streaming.
    /// Returns row bytes if successful, writes header on first call.
    internal func processAsyncRow(
        _ value: some Encodable,
        keys: inout [String]?,
        rowBuilder: CSVRowBuilder,
        writer: AsyncCSVWriter
    ) async throws -> [UInt8] {
        let (row, orderedKeys) = try encodeValue(value)

        // Write header on first row
        if keys == nil {
            let transformedKeys = orderedKeys.map { transformKey($0) }
            keys = transformedKeys
            if configuration.hasHeaders {
                let headerBytes = rowBuilder.buildHeader(transformedKeys)
                try await writer.writeRow(headerBytes)
            }
        }

        // Build row bytes
        let fields = orderedKeys.map { row[$0] ?? "" }
        return rowBuilder.buildRow(fields)
    }

    // MARK: - Actor-Isolated Async Encoding

    /// Stream encodes values using actor-isolated async writer.
    /// Provides better isolation and backpressure handling.
    ///
    /// - Parameters:
    ///   - values: An async sequence of encodable values.
    ///   - url: The file URL to write to.
    ///   - bufferSize: The write buffer size in bytes. Default is 64KB.
    /// - Throws: `CSVEncodingError` or `AsyncCSVWriterError` if encoding fails.
    public func encodeAsync<S: AsyncSequence>(
        _ values: S,
        to url: URL,
        bufferSize: Int = 65536,
    ) async throws where S.Element: Encodable & Sendable {
        let writer = try AsyncCSVWriter(url: url, bufferCapacity: bufferSize)
        let rowBuilder = CSVRowBuilder(delimiter: configuration.delimiter, lineEnding: configuration.lineEnding)

        var keys: [String]?

        for try await value in values {
            let rowBytes = try await processAsyncRow(value, keys: &keys, rowBuilder: rowBuilder, writer: writer)
            try await writer.writeRow(rowBytes)
        }

        try await writer.close()
    }

    /// Stream encodes values with progress reporting.
    /// Calls the progress handler after each row is written.
    ///
    /// - Parameters:
    ///   - values: An async sequence of encodable values.
    ///   - url: The file URL to write to.
    ///   - bufferSize: The write buffer size in bytes.
    ///   - progress: Handler called with (rowsWritten, bytesWritten) after each row.
    public func encodeAsync<S: AsyncSequence>(
        _ values: S,
        to url: URL,
        bufferSize: Int = 65536,
        progress: @Sendable @escaping (Int, Int) async -> Void,
    ) async throws where S.Element: Encodable & Sendable {
        let writer = try AsyncCSVWriter(url: url, bufferCapacity: bufferSize)
        let rowBuilder = CSVRowBuilder(delimiter: configuration.delimiter, lineEnding: configuration.lineEnding)

        var keys: [String]?
        var rowCount = 0

        for try await value in values {
            let rowBytes = try await processAsyncRow(value, keys: &keys, rowBuilder: rowBuilder, writer: writer)
            try await writer.writeRow(rowBytes)

            rowCount += 1
            await progress(rowCount, writer.totalBytesWritten)
        }

        try await writer.close()
    }

    // MARK: - Batched Async Encoding

    /// Encodes values in batches for improved throughput.
    /// Buffers multiple rows before writing to reduce I/O overhead.
    ///
    /// - Parameters:
    ///   - values: An async sequence of encodable values.
    ///   - url: The file URL to write to.
    ///   - batchSize: Number of rows to buffer before writing. Default is 100.
    ///   - bufferSize: The write buffer size in bytes. Default is 64KB.
    public func encodeBatched<S: AsyncSequence>(
        _ values: S,
        to url: URL,
        batchSize: Int = 100,
        bufferSize: Int = 65536,
    ) async throws where S.Element: Encodable & Sendable {
        let writer = try AsyncCSVWriter(url: url, bufferCapacity: bufferSize)
        let rowBuilder = CSVRowBuilder(delimiter: configuration.delimiter, lineEnding: configuration.lineEnding)

        var keys: [String]?
        var batch: [[UInt8]] = []
        batch.reserveCapacity(batchSize)

        for try await value in values {
            let rowBytes = try await processAsyncRow(value, keys: &keys, rowBuilder: rowBuilder, writer: writer)
            batch.append(rowBytes)

            // Flush batch when full
            if batch.count >= batchSize {
                for row in batch {
                    try await writer.writeRow(row)
                }
                batch.removeAll(keepingCapacity: true)
            }
        }

        // Flush remaining rows
        for row in batch {
            try await writer.writeRow(row)
        }

        try await writer.close()
    }
}
