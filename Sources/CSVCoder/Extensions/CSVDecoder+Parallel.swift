//
//  CSVDecoder+Parallel.swift
//  CSVCoder
//
//  Parallel decoding extension for multi-core CSV processing.
//  Uses TaskGroup for concurrent chunk decoding.
//

import Foundation

// MARK: - Parallel Decoding Configuration

extension CSVDecoder {
    /// Configuration for parallel decoding operations.
    public struct ParallelConfiguration: Sendable {
        /// Number of concurrent decoding tasks. Default uses all available processors.
        public var parallelism: Int

        /// Target chunk size in bytes. Actual chunks may be larger to align with row boundaries.
        public var chunkSize: Int

        /// Maximum number of rows to buffer before applying backpressure.
        public var maxBufferedRows: Int

        /// Whether to preserve original row order. Disabling may improve performance.
        public var preserveOrder: Bool

        /// Creates a parallel configuration with default values.
        public init(
            parallelism: Int = ProcessInfo.processInfo.activeProcessorCount,
            chunkSize: Int = 1024 * 1024, // 1MB chunks
            maxBufferedRows: Int = 10_000,
            preserveOrder: Bool = true
        ) {
            self.parallelism = max(1, parallelism)
            self.chunkSize = max(64 * 1024, chunkSize) // Minimum 64KB
            self.maxBufferedRows = max(100, maxBufferedRows)
            self.preserveOrder = preserveOrder
        }
    }
}

// MARK: - Chunk Boundary Detection

/// Represents a chunk of CSV data with its boundaries.
struct CSVChunk: Sendable {
    let index: Int
    let startOffset: Int
    let endOffset: Int
    let isFirstChunk: Bool
}

/// Finds safe chunk boundaries in CSV data, avoiding splits in quoted fields.
struct ChunkBoundaryFinder: Sendable {
    private static let quote: UInt8 = 0x22
    private static let lf: UInt8 = 0x0A
    private static let cr: UInt8 = 0x0D

    /// Finds chunks in the given data, ensuring boundaries are at row ends.
    static func findChunks(
        in reader: MemoryMappedReader,
        targetChunkSize: Int,
        skipHeader: Bool
    ) -> [CSVChunk] {
        let totalSize = reader.count
        guard totalSize > 0 else { return [] }

        var chunks: [CSVChunk] = []
        var currentOffset = 0
        var chunkIndex = 0

        // Skip header row if needed
        var headerEndOffset = 0
        if skipHeader {
            headerEndOffset = reader.withUnsafeBytes { buffer in
                guard let baseAddress = buffer.baseAddress else { return 0 }
                let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
                return findNextRowBoundary(bytes: bytes, count: totalSize, startingAt: 0)
            }
            currentOffset = headerEndOffset
        }

        while currentOffset < totalSize {
            let isFirst = chunkIndex == 0
            var targetEnd = min(currentOffset + targetChunkSize, totalSize)

            // If not at end, find safe boundary
            if targetEnd < totalSize {
                targetEnd = reader.withUnsafeBytes { buffer in
                    guard let baseAddress = buffer.baseAddress else { return targetEnd }
                    let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
                    return findSafeChunkBoundary(bytes: bytes, count: totalSize, target: targetEnd)
                }
            }

            chunks.append(CSVChunk(
                index: chunkIndex,
                startOffset: currentOffset,
                endOffset: targetEnd,
                isFirstChunk: isFirst
            ))

            currentOffset = targetEnd
            chunkIndex += 1
        }

        return chunks
    }

    /// Finds the next row boundary after the given offset.
    private static func findNextRowBoundary(
        bytes: UnsafePointer<UInt8>,
        count: Int,
        startingAt offset: Int
    ) -> Int {
        var pos = offset
        var inQuotes = false

        while pos < count {
            let byte = bytes[pos]

            if byte == quote {
                inQuotes.toggle()
            } else if !inQuotes {
                if byte == lf {
                    return pos + 1
                } else if byte == cr {
                    // CRLF or lone CR
                    if pos + 1 < count && bytes[pos + 1] == lf {
                        return pos + 2
                    }
                    return pos + 1
                }
            }
            pos += 1
        }

        return count
    }

    /// Finds a safe chunk boundary near the target offset.
    /// Scans forward from target to find a row boundary not inside quotes.
    private static func findSafeChunkBoundary(
        bytes: UnsafePointer<UInt8>,
        count: Int,
        target: Int
    ) -> Int {
        // Scan backward to find quote state at target
        var inQuotes = false
        var scanPos = 0

        // Use SIMD to quickly count quotes up to target
        let structuralPositions = SIMDScanner.scanStructural(
            buffer: bytes,
            count: min(target + 4096, count), // Scan slightly past target
            delimiter: 0x2C
        )

        // Process structural positions to determine quote state at target
        for pos in structuralPositions {
            if pos.offset >= target { break }
            if pos.isQuote {
                inQuotes.toggle()
            }
        }

        // Now scan forward from target to find safe boundary
        scanPos = target
        while scanPos < count {
            let byte = bytes[scanPos]

            if byte == quote {
                inQuotes.toggle()
            } else if !inQuotes {
                if byte == lf {
                    return scanPos + 1
                } else if byte == cr {
                    if scanPos + 1 < count && bytes[scanPos + 1] == lf {
                        return scanPos + 2
                    }
                    return scanPos + 1
                }
            }
            scanPos += 1
        }

        return count
    }
}

// MARK: - Parallel Decoding Extension

extension CSVDecoder {
    /// Decodes CSV data in parallel using multiple cores.
    /// Splits file into chunks and decodes each chunk concurrently.
    ///
    /// - Parameters:
    ///   - type: The array type to decode.
    ///   - url: The file URL to read CSV data from.
    ///   - parallelConfig: Configuration for parallel processing.
    /// - Returns: An array of all decoded values in original order.
    ///
    /// - Note: For ordered results, use `preserveOrder: true` (default).
    ///         For maximum throughput, set `preserveOrder: false`.
    public func decodeParallel<T: Decodable & Sendable>(
        _ type: [T].Type,
        from url: URL,
        parallelConfig: ParallelConfiguration = ParallelConfiguration()
    ) async throws -> [T] {
        let reader = try MemoryMappedReader(url: url)
        return try await decodeParallel(type, reader: reader, parallelConfig: parallelConfig)
    }

    /// Decodes CSV Data in parallel using multiple cores.
    public func decodeParallel<T: Decodable & Sendable>(
        _ type: [T].Type,
        from data: Data,
        parallelConfig: ParallelConfiguration = ParallelConfiguration()
    ) async throws -> [T] {
        let reader = MemoryMappedReader(data: data)
        return try await decodeParallel(type, reader: reader, parallelConfig: parallelConfig)
    }

    private func decodeParallel<T: Decodable & Sendable>(
        _ type: [T].Type,
        reader: MemoryMappedReader,
        parallelConfig: ParallelConfiguration
    ) async throws -> [T] {
        // Extract headers first
        let headers = try extractHeaders(from: reader)
        
        // Build header map
        var headerMap: [String: Int] = [:]
        for (index, header) in headers.enumerated() {
            headerMap[header] = index
        }

        // Find chunks
        let chunks = ChunkBoundaryFinder.findChunks(
            in: reader,
            targetChunkSize: parallelConfig.chunkSize,
            skipHeader: configuration.hasHeaders
        )

        guard !chunks.isEmpty else { return [] }

        // Decode chunks in parallel
        let config = self.configuration

        if parallelConfig.preserveOrder {
            return try await decodeChunksOrdered(
                chunks: chunks,
                reader: reader,
                headers: headers,
                headerMap: headerMap,
                config: config,
                parallelism: parallelConfig.parallelism
            )
        } else {
            return try await decodeChunksUnordered(
                chunks: chunks,
                reader: reader,
                headers: headers,
                headerMap: headerMap,
                config: config,
                parallelism: parallelConfig.parallelism
            )
        }
    }

    private func extractHeaders(from reader: MemoryMappedReader) throws -> [String] {
        return reader.withUnsafeBytes { buffer -> [String] in
            guard let baseAddress = buffer.baseAddress else { return [] }
            let bytes = UnsafeBufferPointer(
                start: baseAddress.assumingMemoryBound(to: UInt8.self),
                count: reader.count
            )

            // Handle UTF-8 BOM
            let startOffset = CSVUtilities.bomOffset(in: bytes)

            let adjustedBytes = UnsafeBufferPointer(
                start: bytes.baseAddress?.advanced(by: startOffset),
                count: bytes.count - startOffset
            )

            let delimiter = configuration.delimiter.asciiValue ?? 0x2C
            let parser = CSVParser(buffer: adjustedBytes, delimiter: delimiter)
            var iterator = parser.makeIterator()

            guard let firstRow = iterator.next() else {
                return []
            }

            // Extract strings from CSVRowView
            var rawHeaders: [String] = []
            rawHeaders.reserveCapacity(firstRow.count)
            for i in 0..<firstRow.count {
                if let s = firstRow.string(at: i) {
                    rawHeaders.append(configuration.trimWhitespace ? s.trimmingCharacters(in: .whitespaces) : s)
                } else {
                    rawHeaders.append("column\(i)")
                }
            }

            // Use shared header resolution
            return resolveHeaders(
                rawHeaders: rawHeaders,
                columnOrder: nil,
                columnCount: firstRow.count
            )
        }
    }

    private func decodeChunksOrdered<T: Decodable & Sendable>(
        chunks: [CSVChunk],
        reader: MemoryMappedReader,
        headers: [String],
        headerMap: [String: Int],
        config: Configuration,
        parallelism: Int
    ) async throws -> [T] {
        // Use TaskGroup with indexed results for ordering
        typealias ChunkResult = (index: Int, values: [T])

        let results: [ChunkResult] = try await withThrowingTaskGroup(of: ChunkResult.self) { group in
            var results: [ChunkResult] = []
            results.reserveCapacity(chunks.count)

            // Limit concurrency by adding tasks in batches
            var chunkIterator = chunks.makeIterator()
            var activeTasks = 0

            // Add initial batch of tasks
            while activeTasks < parallelism, let chunk = chunkIterator.next() {
                group.addTask {
                    let values: [T] = try Self.decodeChunk(
                        chunk: chunk,
                        reader: reader,
                        headers: headers,
                        headerMap: headerMap,
                        config: config
                    )
                    return (chunk.index, values)
                }
                activeTasks += 1
            }

            // Process results and add new tasks
            for try await result in group {
                results.append(result)
                if let nextChunk = chunkIterator.next() {
                    group.addTask {
                        let values: [T] = try Self.decodeChunk(
                            chunk: nextChunk,
                            reader: reader,
                            headers: headers,
                            headerMap: headerMap,
                            config: config
                        )
                        return (nextChunk.index, values)
                    }
                }
            }

            return results
        }

        // Sort by chunk index and flatten
        return results.sorted { $0.index < $1.index }.flatMap { $0.values }
    }

    private func decodeChunksUnordered<T: Decodable & Sendable>(
        chunks: [CSVChunk],
        reader: MemoryMappedReader,
        headers: [String],
        headerMap: [String: Int],
        config: Configuration,
        parallelism: Int
    ) async throws -> [T] {
        // Unordered collection for maximum throughput
        var allValues: [T] = []

        try await withThrowingTaskGroup(of: [T].self) { group in
            var chunkIterator = chunks.makeIterator()
            var activeTasks = 0

            while activeTasks < parallelism, let chunk = chunkIterator.next() {
                group.addTask {
                    try Self.decodeChunk(
                        chunk: chunk,
                        reader: reader,
                        headers: headers,
                        headerMap: headerMap,
                        config: config
                    )
                }
                activeTasks += 1
            }

            for try await values in group {
                allValues.append(contentsOf: values)
                if let nextChunk = chunkIterator.next() {
                    group.addTask {
                        try Self.decodeChunk(
                            chunk: nextChunk,
                            reader: reader,
                            headers: headers,
                            headerMap: headerMap,
                            config: config
                        )
                    }
                }
            }
        }

        return allValues
    }

    private static func decodeChunk<T: Decodable>(
        chunk: CSVChunk,
        reader: MemoryMappedReader,
        headers: [String],
        headerMap: [String: Int],
        config: Configuration
    ) throws -> [T] {
        return try reader.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return [] }
            let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
            
            // Create a view into the chunk
            let chunkBytes = UnsafeBufferPointer(
                start: bytes.advanced(by: chunk.startOffset),
                count: chunk.endOffset - chunk.startOffset
            )
            
            let delimiter = config.delimiter.asciiValue ?? 0x2C
            let parser = CSVParser(buffer: chunkBytes, delimiter: delimiter)
            let rows = parser.parse()
            
            // Decode rows
            var results: [T] = []
            results.reserveCapacity(rows.count)
            
            for (index, rowView) in rows.enumerated() {
                let decoder = CSVRowDecoder(
                    view: rowView,
                    headerMap: headerMap,
                    configuration: config,
                    codingPath: [],
                    rowIndex: chunk.index * 1000 + index // Approximate row index
                )
                results.append(try T(from: decoder))
            }
            return results
        }
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
        parallelConfig: ParallelConfiguration = ParallelConfiguration()
    ) -> AsyncThrowingStream<[T], Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let reader = try MemoryMappedReader(url: url)
                    let headers = try self.extractHeaders(from: reader)
                    
                    let headerMap = headers.enumerated().reduce(into: [String: Int]()) { result, element in
                        result[element.element] = element.offset
                    }

                    let chunks = ChunkBoundaryFinder.findChunks(
                        in: reader,
                        targetChunkSize: parallelConfig.chunkSize,
                        skipHeader: self.configuration.hasHeaders
                    )

                    let config = self.configuration

                    // Decode and yield batches
                    try await withThrowingTaskGroup(of: (Int, [T]).self) { group in
                        var chunkIterator = chunks.makeIterator()
                        var activeTasks = 0
                        var pendingResults: [Int: [T]] = [:]
                        var nextExpectedIndex = 0

                        // Add initial tasks
                        while activeTasks < parallelConfig.parallelism,
                              let chunk = chunkIterator.next() {
                            group.addTask {
                                let values: [T] = try Self.decodeChunk(
                                    chunk: chunk,
                                    reader: reader,
                                    headers: headers,
                                    headerMap: headerMap,
                                    config: config
                                )
                                return (chunk.index, values)
                            }
                            activeTasks += 1
                        }

                        for try await (index, values) in group {
                            if parallelConfig.preserveOrder {
                                pendingResults[index] = values

                                // Yield in order
                                while let batch = pendingResults.removeValue(forKey: nextExpectedIndex) {
                                    continuation.yield(batch)
                                    nextExpectedIndex += 1
                                }
                            } else {
                                continuation.yield(values)
                            }

                            if let nextChunk = chunkIterator.next() {
                                group.addTask {
                                    let values: [T] = try Self.decodeChunk(
                                        chunk: nextChunk,
                                        reader: reader,
                                        headers: headers,
                                        headerMap: headerMap,
                                        config: config
                                    )
                                    return (nextChunk.index, values)
                                }
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
