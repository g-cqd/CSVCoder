//
//  CSVEncoder+Parallel.swift
//  CSVCoder
//
//  Parallel encoding extension for multi-core utilization.
//  Encodes rows in parallel then writes sequentially.
//

import Foundation

extension CSVEncoder {
    /// Configuration for parallel encoding.
    public struct ParallelEncodingConfiguration: Sendable {
        // MARK: Lifecycle

        /// Creates a parallel encoding configuration.
        public init(
            parallelism: Int = ProcessInfo.processInfo.activeProcessorCount,
            chunkSize: Int = 10000,
            bufferSize: Int = 65536,
        ) {
            self.parallelism = max(1, parallelism)
            self.chunkSize = max(1, chunkSize)
            self.bufferSize = bufferSize
        }

        // MARK: Public

        /// Default configuration using all available cores.
        public static var `default`: Self { .init() }

        /// Maximum number of concurrent encoding tasks.
        public var parallelism: Int

        /// Number of rows to process per chunk for batched encoding.
        public var chunkSize: Int

        /// Write buffer size in bytes.
        public var bufferSize: Int
    }

    // MARK: - Parallel Encode to File

    /// Encodes an array in parallel and writes to a file.
    /// Rows are encoded concurrently, then written in order.
    ///
    /// - Parameters:
    ///   - values: The values to encode.
    ///   - url: The file URL to write to.
    ///   - parallelConfig: Configuration for parallel encoding.
    ///
    /// - Example:
    /// ```swift
    /// let encoder = CSVEncoder()
    /// try await encoder.encodeParallel(records, to: fileURL,
    ///     parallelConfig: .init(parallelism: 8, chunkSize: 5_000))
    /// ```
    public func encodeParallel(
        _ values: [some Encodable & Sendable],
        to url: URL,
        parallelConfig: ParallelEncodingConfiguration = .default,
    ) async throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        try await encodeParallel(values, to: handle, parallelConfig: parallelConfig)
    }

    /// Encodes an array in parallel and writes to a file handle.
    public func encodeParallel(
        _ values: [some Encodable & Sendable],
        to handle: FileHandle,
        parallelConfig: ParallelEncodingConfiguration = .default,
    ) async throws {
        guard !values.isEmpty else { return }

        var writer = BufferedCSVWriter(handle: handle, bufferSize: parallelConfig.bufferSize)
        let rowBuilder = CSVRowBuilder(delimiter: configuration.delimiter, lineEnding: configuration.lineEnding)

        // Get headers from first value (must be sync to establish key order)
        let (_, orderedKeys) = try encodeValue(values[0])

        // Write header row
        if configuration.hasHeaders {
            var headerBuffer: [UInt8] = []
            rowBuilder.buildHeader(orderedKeys, into: &headerBuffer)
            try writer.write(contentsOf: headerBuffer)
        }

        // Encode all rows in parallel, preserving order
        let encodedRows = try await encodeRowsParallel(
            values,
            keys: orderedKeys,
            parallelism: parallelConfig.parallelism,
            chunkSize: parallelConfig.chunkSize,
        )

        // Write rows sequentially (I/O bound)
        var rowBuffer: [UInt8] = []
        rowBuffer.reserveCapacity(1024)

        for fields in encodedRows {
            rowBuilder.buildRow(fields, into: &rowBuffer)
            try writer.write(contentsOf: rowBuffer)
            rowBuffer.removeAll(keepingCapacity: true)
        }

        try writer.flush()
    }

    // MARK: - Parallel Encode to Data

    /// Encodes an array in parallel and returns Data.
    ///
    /// - Parameters:
    ///   - values: The values to encode.
    ///   - parallelConfig: Configuration for parallel encoding.
    /// - Returns: The encoded CSV data.
    public func encodeParallel(
        _ values: [some Encodable & Sendable],
        parallelConfig: ParallelEncodingConfiguration = .default,
    ) async throws -> Data {
        guard !values.isEmpty else {
            return Data()
        }

        // Get headers from first value
        let (_, orderedKeys) = try encodeValue(values[0])
        let rowBuilder = CSVRowBuilder(delimiter: configuration.delimiter, lineEnding: configuration.lineEnding)

        // Estimate output size
        let estimatedRowSize = orderedKeys.count * 20  // ~20 bytes per field average
        var output: [UInt8] = []
        output.reserveCapacity(values.count * estimatedRowSize + estimatedRowSize)

        // Write header
        if configuration.hasHeaders {
            rowBuilder.buildHeader(orderedKeys, into: &output)
        }

        // Encode rows in parallel
        let encodedRows = try await encodeRowsParallel(
            values,
            keys: orderedKeys,
            parallelism: parallelConfig.parallelism,
            chunkSize: parallelConfig.chunkSize,
        )

        // Append all rows
        for fields in encodedRows {
            rowBuilder.buildRow(fields, into: &output)
        }

        return Data(output)
    }

    /// Encodes an array in parallel and returns a String.
    public func encodeParallelToString(
        _ values: [some Encodable & Sendable],
        parallelConfig: ParallelEncodingConfiguration = .default,
    ) async throws -> String {
        let data = try await encodeParallel(values, parallelConfig: parallelConfig)
        guard let string = String(data: data, encoding: configuration.encoding) else {
            throw CSVEncodingError.invalidOutput("Could not convert data to string using \(configuration.encoding)")
        }
        return string
    }

    // MARK: - Chunked Parallel Encoding

    /// Encodes an array in parallel chunks, yielding each chunk as it completes.
    /// Useful for progress reporting or incremental processing.
    ///
    /// - Parameters:
    ///   - values: The values to encode.
    ///   - parallelConfig: Configuration for parallel encoding.
    /// - Returns: An async stream of encoded row batches.
    public func encodeParallelBatched(
        _ values: [some Encodable & Sendable],
        parallelConfig: ParallelEncodingConfiguration = .default,
    ) -> AsyncThrowingStream<[String], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !values.isEmpty else {
                        continuation.finish()
                        return
                    }

                    let (_, orderedKeys) = try encodeValue(values[0])
                    let delimiter = String(configuration.delimiter)

                    // Yield header
                    if configuration.hasHeaders {
                        let header = orderedKeys.map { escapeField($0) }.joined(separator: delimiter)
                        continuation.yield([header])
                    }

                    // Process chunks
                    let chunks = stride(from: 0, to: values.count, by: parallelConfig.chunkSize).map {
                        Array(values[$0 ..< min($0 + parallelConfig.chunkSize, values.count)])
                    }

                    for chunk in chunks {
                        let encoded = try await encodeRowsParallel(
                            chunk,
                            keys: orderedKeys,
                            parallelism: parallelConfig.parallelism,
                            chunkSize: chunk.count,
                        )

                        let rows = encoded.map { fields in
                            fields.map { escapeField($0) }.joined(separator: delimiter)
                        }

                        continuation.yield(rows)
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

    // MARK: - Internal Parallel Encoding

    /// Encodes rows in parallel using TaskGroup.
    private func encodeRowsParallel<T: Encodable & Sendable>(
        _ values: [T],
        keys: [String],
        parallelism: Int,
        chunkSize: Int,
    ) async throws -> [[String]] {
        // For small arrays, encode sequentially
        guard values.count > parallelism * 2 else {
            return try values.map { value in
                let (row, _) = try encodeValue(value)
                return keys.map { row[$0] ?? "" }
            }
        }

        // Create chunks for parallel processing
        let chunkCount = min(parallelism, (values.count + chunkSize - 1) / chunkSize)
        let effectiveChunkSize = (values.count + chunkCount - 1) / chunkCount

        let chunks: [(offset: Int, values: ArraySlice<T>)] = stride(from: 0, to: values.count, by: effectiveChunkSize)
            .map {
                let end = min($0 + effectiveChunkSize, values.count)
                return ($0, values[$0 ..< end])
            }

        // Process chunks in parallel
        return try await withThrowingTaskGroup(of: (Int, [[String]]).self) { group in
            for (offset, chunk) in chunks {
                group.addTask {
                    let encoded = try chunk.map { value -> [String] in
                        let (row, _) = try self.encodeValue(value)
                        return keys.map { row[$0] ?? "" }
                    }
                    return (offset, encoded)
                }
            }

            // Collect results preserving order
            var results: [(Int, [[String]])] = []
            results.reserveCapacity(chunks.count)

            for try await result in group {
                results.append(result)
            }

            // Sort by offset and flatten
            return
                results
                .sorted { $0.0 < $1.0 }
                .flatMap(\.1)
        }
    }
}
