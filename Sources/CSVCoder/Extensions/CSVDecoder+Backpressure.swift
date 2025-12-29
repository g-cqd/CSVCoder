//
//  CSVDecoder+Backpressure.swift
//  CSVCoder
//
//  Memory-aware streaming with configurable backpressure.
//  Provides control over memory usage during large file processing.
//

import Foundation

// MARK: - CSVDecoder.MemoryLimitConfiguration

public extension CSVDecoder {
    /// Configuration for memory-limited streaming operations.
    struct MemoryLimitConfiguration: Sendable {
        // MARK: Lifecycle

        /// Creates a memory limit configuration with sensible defaults.
        public init(
            memoryBudget: Int = 50 * 1024 * 1024, // 50MB
            estimatedRowSize: Int = 256,
            batchSize: Int = 1000,
            useWatermarks: Bool = true,
            highWaterMark: Double = 0.8,
            lowWaterMark: Double = 0.4,
        ) {
            self.memoryBudget = max(1024 * 1024, memoryBudget) // Minimum 1MB
            self.estimatedRowSize = max(64, estimatedRowSize)
            self.batchSize = max(1, batchSize)
            self.useWatermarks = useWatermarks
            self.highWaterMark = min(1.0, max(0.5, highWaterMark))
            self.lowWaterMark = min(highWaterMark - 0.1, max(0.1, lowWaterMark))
        }

        // MARK: Public

        /// Maximum memory budget in bytes for buffering decoded values.
        /// When exceeded, streaming will pause until consumer catches up.
        public var memoryBudget: Int

        /// Estimated memory per decoded row in bytes.
        /// Used for calculating buffer capacity.
        public var estimatedRowSize: Int

        /// Batch size for yielding results.
        /// Larger batches reduce overhead but increase memory spikes.
        public var batchSize: Int

        /// Whether to use high-water/low-water mark backpressure.
        /// When true, production pauses at high water and resumes at low water.
        public var useWatermarks: Bool

        /// High water mark as fraction of memory budget (0.0-1.0).
        /// Production pauses when buffer exceeds this threshold.
        public var highWaterMark: Double

        /// Low water mark as fraction of memory budget (0.0-1.0).
        /// Production resumes when buffer drops below this threshold.
        public var lowWaterMark: Double

        // MARK: Internal

        /// Maximum rows that fit in memory budget.
        var maxBufferedRows: Int {
            memoryBudget / estimatedRowSize
        }

        /// High water mark in row count.
        var highWaterRows: Int {
            Int(Double(maxBufferedRows) * highWaterMark)
        }

        /// Low water mark in row count.
        var lowWaterRows: Int {
            Int(Double(maxBufferedRows) * lowWaterMark)
        }
    }
}

// MARK: - BackpressureController

/// Actor managing backpressure state for memory-aware streaming.
actor BackpressureController {
    // MARK: Lifecycle

    init(config: CSVDecoder.MemoryLimitConfiguration) {
        self.config = config
    }

    // MARK: Internal

    /// Current buffer state for diagnostics.
    var state: (buffered: Int, maxAllowed: Int, isPaused: Bool) {
        (bufferedCount, config.maxBufferedRows, isPaused)
    }

    /// Records items added to buffer. Returns true if should pause.
    func recordProduced(_ count: Int) -> Bool {
        bufferedCount += count

        if config.useWatermarks {
            if bufferedCount >= config.highWaterRows, !isPaused {
                isPaused = true
                return true
            }
        } else {
            if bufferedCount >= config.maxBufferedRows {
                isPaused = true
                return true
            }
        }

        return isPaused
    }

    /// Records items consumed from buffer. Signals waiters if below low water.
    func recordConsumed(_ count: Int) {
        bufferedCount = max(0, bufferedCount - count)

        let shouldResume: Bool = if config.useWatermarks {
            isPaused && bufferedCount <= config.lowWaterRows
        } else {
            isPaused && bufferedCount < config.maxBufferedRows
        }

        if shouldResume {
            isPaused = false
            let currentWaiters = waiters
            waiters.removeAll()
            for waiter in currentWaiters {
                waiter.resume()
            }
        }
    }

    /// Waits until buffer has space for more items.
    func waitForSpace() async {
        guard isPaused else { return }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    // MARK: Private

    private let config: CSVDecoder.MemoryLimitConfiguration
    private var bufferedCount: Int = 0
    private var isPaused: Bool = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
}

// MARK: - Memory-Aware Streaming Extension

public extension CSVDecoder {
    /// Decodes CSV with memory-aware backpressure.
    /// Automatically pauses production when memory limits are approached.
    ///
    /// - Parameters:
    ///   - type: The type to decode.
    ///   - url: The file URL to read CSV data from.
    ///   - memoryConfig: Configuration for memory limits and backpressure.
    /// - Returns: An AsyncThrowingStream yielding decoded values with backpressure.
    ///
    /// - Note: The stream applies backpressure when buffered rows exceed
    ///         the configured memory budget, pausing production until
    ///         the consumer catches up.
    func decodeWithBackpressure<T: Decodable & Sendable>(
        _ type: T.Type,
        from url: URL,
        memoryConfig: MemoryLimitConfiguration = MemoryLimitConfiguration(),
    ) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(memoryConfig.batchSize * 2)) { continuation in
            let controller = BackpressureController(config: memoryConfig)

            Task {
                do {
                    let parser = try StreamingCSVParser(url: url, configuration: configuration)
                    var iterator = parser.makeAsyncIterator()
                    var headers: [String]?
                    var batchBuffer: [T] = []
                    batchBuffer.reserveCapacity(memoryConfig.batchSize)

                    while let row = try await iterator.next() {
                        if headers == nil {
                            if configuration.hasHeaders {
                                headers = row
                                continue
                            } else {
                                headers = (0 ..< row.count).map { "column\($0)" }
                            }
                        }

                        guard let headerRow = headers else { continue }

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
                        let value = try T(from: decoder)
                        batchBuffer.append(value)

                        // Flush batch when full
                        if batchBuffer.count >= memoryConfig.batchSize {
                            // Check backpressure before yielding
                            let shouldPause = await controller.recordProduced(batchBuffer.count)
                            if shouldPause {
                                await controller.waitForSpace()
                            }

                            for item in batchBuffer {
                                continuation.yield(item)
                            }
                            batchBuffer.removeAll(keepingCapacity: true)
                        }
                    }

                    // Flush remaining
                    if !batchBuffer.isEmpty {
                        for item in batchBuffer {
                            continuation.yield(item)
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            // Set up consumption tracking
            continuation.onTermination = { @Sendable _ in
                Task {
                    await controller.recordConsumed(Int.max) // Signal completion
                }
            }
        }
    }

    /// Decodes CSV in batches with memory-aware backpressure.
    /// Each yielded batch respects memory limits.
    ///
    /// - Parameters:
    ///   - type: The type to decode.
    ///   - url: The file URL to read CSV data from.
    ///   - memoryConfig: Configuration for memory limits.
    /// - Returns: An AsyncThrowingStream yielding batches of decoded values.
    func decodeBatchedWithBackpressure<T: Decodable & Sendable>(
        _ type: T.Type,
        from url: URL,
        memoryConfig: MemoryLimitConfiguration = MemoryLimitConfiguration(),
    ) -> AsyncThrowingStream<[T], Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(4)) { continuation in
            Task {
                do {
                    let parser = try StreamingCSVParser(url: url, configuration: configuration)
                    var iterator = parser.makeAsyncIterator()
                    var headers: [String]?
                    var batch: [T] = []
                    batch.reserveCapacity(memoryConfig.batchSize)

                    while let row = try await iterator.next() {
                        if headers == nil {
                            if configuration.hasHeaders {
                                headers = row
                                continue
                            } else {
                                headers = (0 ..< row.count).map { "column\($0)" }
                            }
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
                            codingPath: [],
                        )
                        let value = try T(from: decoder)
                        batch.append(value)

                        if batch.count >= memoryConfig.batchSize {
                            continuation.yield(batch)
                            batch.removeAll(keepingCapacity: true)
                        }
                    }

                    if !batch.isEmpty {
                        continuation.yield(batch)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - Progress Tracking

public extension CSVDecoder {
    /// Progress information during decoding.
    struct DecodingProgress: Sendable {
        /// Number of rows decoded so far.
        public let rowsDecoded: Int
        /// Estimated total rows (if known).
        public let estimatedTotal: Int?
        /// Bytes processed so far.
        public let bytesProcessed: Int
        /// Total bytes in file.
        public let totalBytes: Int

        /// Progress as fraction (0.0 to 1.0).
        public var fraction: Double {
            guard totalBytes > 0 else { return 0 }
            return Double(bytesProcessed) / Double(totalBytes)
        }
    }

    /// Decodes CSV with progress reporting.
    ///
    /// - Parameters:
    ///   - type: The type to decode.
    ///   - url: The file URL to read CSV data from.
    ///   - progressHandler: Called periodically with progress updates.
    /// - Returns: An AsyncThrowingStream yielding decoded values.
    func decodeWithProgress<T: Decodable & Sendable>(
        _ type: T.Type,
        from url: URL,
        progressHandler: @escaping @Sendable (DecodingProgress) -> Void,
    ) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let reader = try MemoryMappedReader(url: url)
                    let totalBytes = reader.count

                    // Estimate total rows using SIMD newline count
                    let estimatedRows = reader.withUnsafeBytes { buffer -> Int in
                        guard let baseAddress = buffer.baseAddress else { return 0 }
                        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
                        return SIMDScanner.countNewlinesApprox(buffer: bytes, count: totalBytes)
                    }

                    let parser = try StreamingCSVParser(url: url, configuration: configuration)
                    var iterator = parser.makeAsyncIterator()
                    var headers: [String]?
                    var rowsDecoded = 0
                    var lastReportedRow = 0
                    let reportInterval = max(1, estimatedRows / 100) // Report ~100 times

                    while let row = try await iterator.next() {
                        if headers == nil {
                            if configuration.hasHeaders {
                                headers = row
                                continue
                            } else {
                                headers = (0 ..< row.count).map { "column\($0)" }
                            }
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
                            codingPath: [],
                        )
                        let value = try T(from: decoder)
                        continuation.yield(value)
                        rowsDecoded += 1

                        // Report progress periodically
                        if rowsDecoded - lastReportedRow >= reportInterval {
                            let bytesEstimate = totalBytes * rowsDecoded / max(1, estimatedRows)
                            progressHandler(DecodingProgress(
                                rowsDecoded: rowsDecoded,
                                estimatedTotal: estimatedRows,
                                bytesProcessed: min(bytesEstimate, totalBytes),
                                totalBytes: totalBytes,
                            ))
                            lastReportedRow = rowsDecoded
                        }
                    }

                    // Final progress report
                    progressHandler(DecodingProgress(
                        rowsDecoded: rowsDecoded,
                        estimatedTotal: rowsDecoded,
                        bytesProcessed: totalBytes,
                        totalBytes: totalBytes,
                    ))

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
