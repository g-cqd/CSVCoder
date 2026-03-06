//
//  CSVDecoder+Parallel.swift
//  CSVCoder
//
//  Parallel decoding extension for multi-core CSV processing.
//  Uses a pipeline: sequential parse → parallel Codable decode.
//

import Foundation

// MARK: - CSVDecoder.ParallelConfiguration

extension CSVDecoder {
    /// Configuration for parallel decoding operations.
    public struct ParallelConfiguration: Sendable {
        // MARK: Lifecycle

        /// Creates a parallel configuration with default values.
        public init(
            parallelism: Int = ProcessInfo.processInfo.activeProcessorCount,
            chunkSize: Int = 1024 * 1024,  // 1MB chunks
            maxBufferedRows: Int = 10000,
            preserveOrder: Bool = true,
        ) {
            self.parallelism = max(1, parallelism)
            self.chunkSize = max(64 * 1024, chunkSize)  // Minimum 64KB
            self.maxBufferedRows = max(100, maxBufferedRows)
            self.preserveOrder = preserveOrder
        }

        // MARK: Public

        /// Number of concurrent decoding tasks. Default uses all available processors.
        public var parallelism: Int

        /// Target chunk size in bytes. Actual chunks may be larger to align with row boundaries.
        public var chunkSize: Int

        /// Maximum number of rows to buffer before applying backpressure.
        public var maxBufferedRows: Int

        /// Whether to preserve original row order. Disabling may improve performance.
        public var preserveOrder: Bool
    }
}

// MARK: - Parallel Decoding Extension

extension CSVDecoder {
    /// Decodes CSV data in parallel using multiple cores.
    ///
    /// Uses a pipeline architecture for optimal throughput:
    /// 1. **Sequential parse**: SIMD-accelerated parsing extracts string fields (memory-bound, fast)
    /// 2. **Parallel decode**: Codable decode runs concurrently across cores (CPU-bound)
    ///
    /// - Parameters:
    ///   - type: The array type to decode.
    ///   - url: The file URL to read CSV data from.
    ///   - parallelConfig: Configuration for parallel processing.
    /// - Returns: An array of all decoded values in original order.
    public func decodeParallel<T: Decodable & Sendable>(
        _ type: [T].Type,
        from url: URL,
        parallelConfig: ParallelConfiguration = ParallelConfiguration(),
    ) async throws -> [T] {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try await decodeParallel(type, from: data, parallelConfig: parallelConfig)
    }

    /// Decodes CSV Data in parallel using multiple cores.
    public func decodeParallel<T: Decodable & Sendable>(
        _ type: [T].Type,
        from data: Data,
        parallelConfig: ParallelConfiguration = ParallelConfiguration(),
    ) async throws -> [T] {
        // For single core or small data, use the regular decode path directly
        // to avoid intermediate string extraction overhead
        guard parallelConfig.parallelism > 1 else {
            return try decodeRowsFromBytes(type, from: data, columnOrder: nil)
        }

        // Phase 1: Sequential parse — extract string rows (SIMD-fast, memory-bound)
        let (headerMap, rows) = try parseToStringRows(data: data)

        guard !rows.isEmpty else { return [] }

        // For small datasets, skip parallelism overhead
        guard rows.count > 500 else {
            return try decodeStringRowsSequential(rows, headerMap: headerMap)
        }

        // Phase 2: Parallel Codable decode (CPU-bound, scales with cores)
        return try await decodeStringRowsParallel(
            rows,
            headerMap: headerMap,
            parallelism: parallelConfig.parallelism,
            preserveOrder: parallelConfig.preserveOrder,
        )
    }

    // MARK: - Phase 1: Sequential Parse

    /// Parses CSV data into string rows. Runs sequentially since parsing
    /// is memory-bound and already SIMD-accelerated.
    private func parseToStringRows(
        data: Data,
    ) throws -> (headerMap: [String: Int], rows: [[String]]) {
        let encoding = configuration.encoding
        let isASCIICompatible = CSVUtilities.isASCIICompatible(encoding)

        let effectiveData: Data
        if !isASCIICompatible {
            guard let transcoded = CSVUtilities.transcodeToUTF8(data, from: encoding) else {
                throw CSVDecodingError.parsingError(
                    "Failed to transcode data from \(encoding) to UTF-8",
                    line: nil,
                    column: nil,
                )
            }
            effectiveData = transcoded
        } else {
            effectiveData = data
        }

        return try effectiveData.withUnsafeBytes { buffer in
            guard let bytes = CSVUtilities.adjustedBuffer(from: buffer) else {
                return ([:], [])
            }
            let delimiter = configuration.delimiter.asciiValue ?? 0x2C
            let parser = CSVParser(buffer: bytes, delimiter: delimiter)

            var allRows: [[String]] = []
            var headers: [String] = []
            var headerMap: [String: Int] = [:]
            var isFirstRow = true

            for rowView in parser {
                if isFirstRow {
                    isFirstRow = false

                    // Extract headers
                    var rawHeaders: [String] = []
                    rawHeaders.reserveCapacity(rowView.count)
                    for i in 0 ..< rowView.count {
                        if let s = rowView.string(at: i) {
                            rawHeaders.append(
                                configuration.trimWhitespace ? s.trimmingCharacters(in: .whitespaces) : s
                            )
                        } else {
                            rawHeaders.append("column\(i)")
                        }
                    }
                    headers = resolveHeaders(
                        rawHeaders: rawHeaders,
                        columnOrder: nil,
                        columnCount: rowView.count,
                    )
                    for (index, header) in headers.enumerated() {
                        headerMap[header] = index
                    }

                    // If no headers config, this row is data too
                    if !configuration.hasHeaders {
                        let row = extractStringRow(from: rowView, fieldCount: headers.count)
                        allRows.append(row)
                    }
                    continue
                }

                let row = extractStringRow(from: rowView, fieldCount: headers.count)
                allRows.append(row)
            }

            return (headerMap, allRows)
        }
    }

    /// Extracts string values from a CSVRowView into a flat array.
    @inline(__always)
    private func extractStringRow(from rowView: CSVRowView, fieldCount: Int) -> [String] {
        var row: [String] = []
        row.reserveCapacity(fieldCount)
        for i in 0 ..< rowView.count {
            if let s = rowView.string(at: i) {
                row.append(configuration.trimWhitespace ? s.trimmingCharacters(in: .whitespaces) : s)
            } else {
                row.append("")
            }
        }
        return row
    }

    // MARK: - Phase 2: Parallel Decode

    /// Builds a `[String: String]` dictionary from header map and field array.
    @inline(__always)
    private static func buildRowDict(
        fields: some RandomAccessCollection<String>,
        headerMap: [String: Int],
    ) -> [String: String] {
        var dict: [String: String] = [:]
        dict.reserveCapacity(headerMap.count)
        for (key, columnIndex) in headerMap {
            if columnIndex < fields.count {
                dict[key] = fields[fields.index(fields.startIndex, offsetBy: columnIndex)]
            }
        }
        return dict
    }

    /// Decodes pre-parsed string rows in parallel using TaskGroup.
    private func decodeStringRowsParallel<T: Decodable & Sendable>(
        _ rows: [[String]],
        headerMap: [String: Int],
        parallelism: Int,
        preserveOrder: Bool,
    ) async throws -> [T] {
        let config = configuration
        let chunkCount = min(parallelism, rows.count)
        let chunkSize = (rows.count + chunkCount - 1) / chunkCount

        typealias ChunkResult = (index: Int, values: [T])

        let results: [ChunkResult] = try await withThrowingTaskGroup(of: ChunkResult.self) { group in
            var collected: [ChunkResult] = []
            collected.reserveCapacity(chunkCount)

            for chunkIndex in 0 ..< chunkCount {
                let start = chunkIndex * chunkSize
                let end = min(start + chunkSize, rows.count)
                let slice = rows[start ..< end]

                group.addTask {
                    var decoded: [T] = []
                    decoded.reserveCapacity(slice.count)

                    for (localIndex, fields) in slice.enumerated() {
                        let dict = Self.buildRowDict(fields: fields, headerMap: headerMap)
                        let decoder = CSVRowDecoder(
                            row: dict,
                            configuration: config,
                            codingPath: [],
                            rowIndex: start + localIndex + 1,
                        )
                        try decoded.append(T(from: decoder))
                    }
                    return (chunkIndex, decoded)
                }
            }

            for try await result in group {
                collected.append(result)
            }
            return collected
        }

        if preserveOrder {
            return results.sorted { $0.index < $1.index }.flatMap(\.values)
        }
        return results.flatMap(\.values)
    }

    /// Sequential decode fallback for small datasets.
    private func decodeStringRowsSequential<T: Decodable>(
        _ rows: [[String]],
        headerMap: [String: Int],
    ) throws -> [T] {
        var results: [T] = []
        results.reserveCapacity(rows.count)

        for (index, fields) in rows.enumerated() {
            let dict = Self.buildRowDict(fields: fields, headerMap: headerMap)
            let decoder = CSVRowDecoder(
                row: dict,
                configuration: configuration,
                codingPath: [],
                rowIndex: index + 1,
            )
            try results.append(T(from: decoder))
        }
        return results
    }
}

// MARK: - Parallel Streaming Extension

extension CSVDecoder {
    /// Decodes CSV data in parallel, yielding batches of decoded values.
    /// Provides backpressure through AsyncThrowingStream buffering.
    ///
    /// - Parameters:
    ///   - type: The type to decode.
    ///   - url: The file URL to read CSV data from.
    ///   - parallelConfig: Configuration for parallel processing.
    /// - Returns: An AsyncThrowingStream yielding arrays of decoded values (batches).
    public func decodeParallelBatched<T: Decodable & Sendable>(
        _ type: T.Type,
        from url: URL,
        parallelConfig: ParallelConfiguration = ParallelConfiguration(),
    ) -> AsyncThrowingStream<[T], Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let data = try Data(contentsOf: url, options: .mappedIfSafe)
                    let (headerMap, rows) = try self.parseToStringRows(data: data)

                    guard !rows.isEmpty else {
                        continuation.finish()
                        return
                    }

                    let config = self.configuration
                    let chunkCount = min(parallelConfig.parallelism, rows.count)
                    let chunkSize = (rows.count + chunkCount - 1) / chunkCount

                    try await withThrowingTaskGroup(of: (Int, [T]).self) { group in
                        var pendingResults: [Int: [T]] = [:]
                        var nextExpectedIndex = 0

                        for chunkIndex in 0 ..< chunkCount {
                            let start = chunkIndex * chunkSize
                            let end = min(start + chunkSize, rows.count)
                            let slice = Array(rows[start ..< end])

                            group.addTask {
                                var decoded: [T] = []
                                decoded.reserveCapacity(slice.count)
                                for (localIndex, fields) in slice.enumerated() {
                                    var dict: [String: String] = [:]
                                    dict.reserveCapacity(headerMap.count)
                                    for (key, columnIndex) in headerMap {
                                        if columnIndex < fields.count {
                                            dict[key] = fields[columnIndex]
                                        }
                                    }
                                    let decoder = CSVRowDecoder(
                                        row: dict,
                                        configuration: config,
                                        codingPath: [],
                                        rowIndex: start + localIndex + 1,
                                    )
                                    try decoded.append(T(from: decoder))
                                }
                                return (chunkIndex, decoded)
                            }
                        }

                        for try await (index, values) in group {
                            if parallelConfig.preserveOrder {
                                pendingResults[index] = values
                                while let batch = pendingResults.removeValue(forKey: nextExpectedIndex) {
                                    continuation.yield(batch)
                                    nextExpectedIndex += 1
                                }
                            } else {
                                continuation.yield(values)
                            }
                        }

                        // Yield any remaining ordered results
                        for index in pendingResults.keys.sorted() {
                            if let batch = pendingResults[index] {
                                continuation.yield(batch)
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
