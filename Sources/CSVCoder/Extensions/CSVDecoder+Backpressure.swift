//
//  CSVDecoder+Backpressure.swift
//  CSVCoder
//
//  Memory-aware streaming with configurable backpressure.
//  Provides control over memory usage during large file processing.
//

import Foundation

// MARK: - CSVDecoder.MemoryLimitConfiguration

extension CSVDecoder {
    /// Configuration for memory-limited streaming operations.
    ///
    /// The backpressure streams are pull-based, so they hold at most one row (or one batch) ahead
    /// of the consumer whatever the file size. Only ``batchSize`` still affects their behaviour;
    /// the budget, row-size estimate and watermark fields are kept so existing code compiles.
    public struct MemoryLimitConfiguration: Sendable {
        // MARK: Lifecycle

        /// Creates a memory limit configuration with sensible defaults.
        public init(
            memoryBudget: Int = 50 * 1024 * 1024,  // 50MB
            estimatedRowSize: Int = 256,
            batchSize: Int = 1000,
            useWatermarks: Bool = true,
            highWaterMark: Double = 0.8,
            lowWaterMark: Double = 0.4,
        ) {
            self.memoryBudget = max(1024 * 1024, memoryBudget)  // Minimum 1MB
            self.estimatedRowSize = max(64, estimatedRowSize)
            self.batchSize = max(1, batchSize)
            self.useWatermarks = useWatermarks
            self.highWaterMark = min(1.0, max(0.5, highWaterMark))
            self.lowWaterMark = min(highWaterMark - 0.1, max(0.1, lowWaterMark))
        }

        // MARK: Public

        /// Maximum memory budget in bytes for buffering decoded values.
        ///
        /// When exceeded, streaming will pause until consumer catches up.
        public var memoryBudget: Int

        /// Estimated memory per decoded row in bytes.
        ///
        /// Used for calculating buffer capacity.
        public var estimatedRowSize: Int

        /// Batch size for yielding results.
        ///
        /// Larger batches reduce overhead but increase memory spikes.
        public var batchSize: Int

        /// Whether to use high-water/low-water mark backpressure.
        ///
        /// When true, production pauses at high water and resumes at low water.
        public var useWatermarks: Bool

        /// High water mark as fraction of memory budget (0.0-1.0).
        ///
        /// Production pauses when buffer exceeds this threshold.
        public var highWaterMark: Double

        /// Low water mark as fraction of memory budget (0.0-1.0).
        ///
        /// Production resumes when buffer drops below this threshold.
        public var lowWaterMark: Double
    }
}

// MARK: - Memory-Aware Streaming Extension

extension CSVDecoder {
    /// Decodes CSV one row at a time, never reading ahead of the consumer.
    ///
    /// The stream is pull-based: a row is parsed and decoded when the consumer asks for it, so a
    /// slow consumer holds production back by construction and no row is ever dropped.
    ///
    /// - Parameters:
    ///   - type: The type to decode.
    ///   - url: The file URL to read CSV data from.
    ///   - memoryConfig: Retained for source compatibility; see ``MemoryLimitConfiguration``.
    /// - Returns: An AsyncThrowingStream yielding every decoded value in file order.
    ///
    /// - Note: Cancelling the consuming task ends the stream at the next row.
    public func decodeWithBackpressure<T: Decodable & Sendable>(
        _ type: T.Type,
        from url: URL,
        memoryConfig: MemoryLimitConfiguration = MemoryLimitConfiguration(),
    ) -> AsyncThrowingStream<T, Error> {
        let source = PulledRowSource<T>(url: url, configuration: configuration)
        return AsyncThrowingStream(unfolding: {
            guard !Task.isCancelled else { return nil }
            return try source.next()
        })
    }

    /// Decodes CSV in batches of `memoryConfig.batchSize` rows, never reading ahead of the consumer.
    ///
    /// - Parameters:
    ///   - type: The type to decode.
    ///   - url: The file URL to read CSV data from.
    ///   - memoryConfig: `batchSize` sets the rows per batch; the other fields are retained for
    ///     source compatibility.
    /// - Returns: An AsyncThrowingStream yielding every row, in file order, in batches.
    public func decodeBatchedWithBackpressure<T: Decodable & Sendable>(
        _ type: T.Type,
        from url: URL,
        memoryConfig: MemoryLimitConfiguration = MemoryLimitConfiguration(),
    ) -> AsyncThrowingStream<[T], Error> {
        let source = PulledRowSource<T>(url: url, configuration: configuration)
        let batchSize = memoryConfig.batchSize
        return AsyncThrowingStream(unfolding: {
            guard !Task.isCancelled else { return nil }
            return try source.nextBatch(limit: batchSize)
        })
    }
}

// MARK: - Progress Tracking

extension CSVDecoder {
    /// Progress information during decoding.
    public struct DecodingProgress: Sendable {
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
    public func decodeWithProgress<T: Decodable & Sendable>(
        _ type: T.Type,
        from url: URL,
        progressHandler: @escaping @Sendable (DecodingProgress) -> Void,
    ) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let data = try Data(contentsOf: url, options: .mappedIfSafe)
                    let totalBytes = data.count

                    // Estimate total rows using SIMD newline count
                    let estimatedRows = data.withUnsafeBytes { buffer -> Int in
                        guard let baseAddress = buffer.baseAddress else { return 0 }
                        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
                        return SIMDScanner.countNewlinesApprox(buffer: bytes, count: totalBytes)
                    }

                    var producer = try CSVRowStreamProducer(data: data, configuration: configuration)
                    var processor = StreamingRowProcessor<T>(configuration: configuration)
                    var rowsDecoded = 0
                    var lastReportedRow = 0
                    let reportInterval = max(1, estimatedRows / 100)  // Report ~100 times

                    while let row = try producer.nextRow() {
                        guard let value = try processor.process(row) else { continue }
                        continuation.yield(value)
                        rowsDecoded += 1

                        // Report progress periodically
                        if rowsDecoded - lastReportedRow >= reportInterval {
                            let bytesEstimate = totalBytes * rowsDecoded / max(1, estimatedRows)
                            progressHandler(
                                DecodingProgress(
                                    rowsDecoded: rowsDecoded,
                                    estimatedTotal: estimatedRows,
                                    bytesProcessed: min(bytesEstimate, totalBytes),
                                    totalBytes: totalBytes,
                                )
                            )
                            lastReportedRow = rowsDecoded
                        }
                    }

                    // Final progress report
                    progressHandler(
                        DecodingProgress(
                            rowsDecoded: rowsDecoded,
                            estimatedTotal: rowsDecoded,
                            bytesProcessed: totalBytes,
                            totalBytes: totalBytes,
                        )
                    )

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
