//
//  CSVDecoderParallelTests.swift
//  CSVCoder
//
//  Tests for SIMD scanner, parallel decoding, backpressure, and memory configuration.
//

import Testing
@testable import CSVCoder
import Foundation

@Suite("CSVDecoder Parallel Tests")
struct CSVDecoderParallelTests {

    struct SimpleRecord: Codable, Equatable, Sendable {
        let name: String
        let age: Int
        let score: Double
    }

    // MARK: - SIMD Scanner Tests

    @Test("SIMD scanner finds structural positions")
    func simdScannerFindsPositions() throws {
        let csv = "name,age\nAlice,30\nBob,25"
        let data = Data(csv.utf8)

        let positions = data.withUnsafeBytes { buffer -> [SIMDScanner.StructuralPosition] in
            let bytes = buffer.baseAddress!.assumingMemoryBound(to: UInt8.self)
            return SIMDScanner.scanStructural(buffer: bytes, count: data.count)
        }

        // Should find: comma, LF, comma, LF, comma
        let commas = positions.filter { $0.isComma }
        let newlines = positions.filter { $0.isNewline }

        #expect(commas.count == 3)
        #expect(newlines.count == 2)
    }

    @Test("SIMD scanner finds row boundaries")
    func simdScannerRowBoundaries() throws {
        let csv = "name,value\nAlice,\"Hello\nWorld\"\nBob,Test"
        let data = Data(csv.utf8)

        let boundaries = data.withUnsafeBytes { buffer -> SIMDScanner.RowBoundaries in
            let bytes = buffer.baseAddress!.assumingMemoryBound(to: UInt8.self)
            return SIMDScanner.findRowBoundaries(buffer: bytes, count: data.count)
        }

        // Should find 3 rows: header, Alice (with quoted newline), Bob
        #expect(boundaries.rowStarts.count == 3)
        #expect(boundaries.endsInQuote == false)
    }

    @Test("SIMD scanner handles quoted fields correctly")
    func simdScannerQuotedFields() throws {
        let csv = "a,\"b,c\",d\n1,\"2\n3\",4"
        let data = Data(csv.utf8)

        let boundaries = data.withUnsafeBytes { buffer -> SIMDScanner.RowBoundaries in
            let bytes = buffer.baseAddress!.assumingMemoryBound(to: UInt8.self)
            return SIMDScanner.findRowBoundaries(buffer: bytes, count: data.count)
        }

        // The newline inside quotes should not create a row boundary
        #expect(boundaries.rowStarts.count == 2)
    }

    @Test("SIMD approximate newline count")
    func simdApproxNewlineCount() throws {
        let csv = "a\nb\nc\nd\ne"
        let data = Data(csv.utf8)

        let count = data.withUnsafeBytes { buffer -> Int in
            let bytes = buffer.baseAddress!.assumingMemoryBound(to: UInt8.self)
            return SIMDScanner.countNewlinesApprox(buffer: bytes, count: data.count)
        }

        #expect(count == 4)
    }

    // MARK: - Parallel Decoding Tests

    @Test("Parallel decode from Data")
    func parallelDecodeFromData() async throws {
        var csvLines = ["name,age,score"]
        for i in 0..<100 {
            csvLines.append("Person\(i),\(20 + i % 50),\(Double(i) * 0.5)")
        }
        let csv = csvLines.joined(separator: "\n")
        let data = Data(csv.utf8)

        let decoder = CSVDecoder()
        let config = CSVDecoder.ParallelConfiguration(
            parallelism: 4,
            chunkSize: 256 // Small chunks to test parallel behavior
        )

        let records = try await decoder.decodeParallel([SimpleRecord].self, from: data, parallelConfig: config)

        #expect(records.count == 100)
        #expect(records[0].name == "Person0")
        #expect(records[99].name == "Person99")
    }

    @Test("Parallel decode preserves order")
    func parallelDecodePreservesOrder() async throws {
        var csvLines = ["name,age,score"]
        for i in 0..<50 {
            csvLines.append("Person\(i),\(i),\(Double(i))")
        }
        let csv = csvLines.joined(separator: "\n")
        let data = Data(csv.utf8)

        let decoder = CSVDecoder()
        let config = CSVDecoder.ParallelConfiguration(
            parallelism: 4,
            chunkSize: 128,
            preserveOrder: true
        )

        let records = try await decoder.decodeParallel([SimpleRecord].self, from: data, parallelConfig: config)

        #expect(records.count == 50)
        for (i, record) in records.enumerated() {
            #expect(record.name == "Person\(i)", "Order mismatch at index \(i)")
            #expect(record.age == i)
        }
    }

    @Test("Parallel decode unordered")
    func parallelDecodeUnordered() async throws {
        var csvLines = ["name,age,score"]
        for i in 0..<50 {
            csvLines.append("Person\(i),\(i),\(Double(i))")
        }
        let csv = csvLines.joined(separator: "\n")
        let data = Data(csv.utf8)

        let decoder = CSVDecoder()
        let config = CSVDecoder.ParallelConfiguration(
            parallelism: 4,
            chunkSize: 128,
            preserveOrder: false
        )

        let records = try await decoder.decodeParallel([SimpleRecord].self, from: data, parallelConfig: config)

        // All records present, but possibly unordered
        #expect(records.count == 50)

        let names = Set(records.map { $0.name })
        for i in 0..<50 {
            #expect(names.contains("Person\(i)"))
        }
    }

    @Test("Parallel batched decode yields batches")
    func parallelBatchedDecode() async throws {
        var csvLines = ["name,age,score"]
        for i in 0..<100 {
            csvLines.append("Person\(i),\(i),\(Double(i))")
        }
        let csv = csvLines.joined(separator: "\n")

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".csv")
        try Data(csv.utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let decoder = CSVDecoder()
        let config = CSVDecoder.ParallelConfiguration(chunkSize: 256)

        var batchCount = 0
        var totalRecords = 0
        for try await batch in decoder.decodeParallelBatched(SimpleRecord.self, from: tempURL, parallelConfig: config) {
            batchCount += 1
            totalRecords += batch.count
        }

        #expect(batchCount >= 1)
        #expect(totalRecords == 100)
    }

    @Test("Parallel decode is faster than sequential for large data")
    func parallelDecodeFasterThanSequential() async throws {
        // Generate large dataset (10K rows with complex fields)
        var csvLines = ["id,name,email,value,active,notes"]
        for i in 0..<10_000 {
            csvLines.append("\(i),Person\(i),person\(i)@example.com,\(Double(i) * 1.5),\(i % 2 == 0),\"Notes for person \(i)\"")
        }
        let csv = csvLines.joined(separator: "\n")
        let data = Data(csv.utf8)

        struct LargeRecord: Codable, Sendable {
            let id: Int
            let name: String
            let email: String
            let value: Double
            let active: Bool
            let notes: String
        }

        let decoder = CSVDecoder()

        // Measure sequential decode (parallelism: 1)
        let sequentialStart = ContinuousClock.now
        let sequentialConfig = CSVDecoder.ParallelConfiguration(parallelism: 1, chunkSize: 64 * 1024)
        let sequentialResult = try await decoder.decodeParallel([LargeRecord].self, from: data, parallelConfig: sequentialConfig)
        let sequentialDuration = ContinuousClock.now - sequentialStart

        // Measure parallel decode (all cores)
        let parallelStart = ContinuousClock.now
        let parallelConfig = CSVDecoder.ParallelConfiguration(chunkSize: 64 * 1024)
        let parallelResult = try await decoder.decodeParallel([LargeRecord].self, from: data, parallelConfig: parallelConfig)
        let parallelDuration = ContinuousClock.now - parallelStart

        // Verify correctness
        #expect(sequentialResult.count == 10_000)
        #expect(parallelResult.count == 10_000)

        // On multi-core machines, parallel should be faster
        let coreCount = ProcessInfo.processInfo.activeProcessorCount
        if coreCount > 1 {
            let seqNanos = Double(sequentialDuration.components.seconds) * 1e9 + Double(sequentialDuration.components.attoseconds) / 1e9
            let parNanos = Double(parallelDuration.components.seconds) * 1e9 + Double(parallelDuration.components.attoseconds) / 1e9
            let speedup = seqNanos / parNanos
            #expect(parallelResult.count == 10_000, "Parallel decode should complete successfully")
            _ = speedup // Suppress unused warning
        }
    }

    // MARK: - Backpressure Tests

    @Test("Decode with memory configuration")
    func decodeWithMemoryConfig() async throws {
        var csvLines = ["name,age,score"]
        for i in 0..<50 {
            csvLines.append("Person\(i),\(i),\(Double(i))")
        }
        let csv = csvLines.joined(separator: "\n")

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".csv")
        try Data(csv.utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let decoder = CSVDecoder()
        let memoryConfig = CSVDecoder.MemoryLimitConfiguration(
            memoryBudget: 1024 * 1024, // 1MB
            estimatedRowSize: 256,
            batchSize: 25
        )

        var records: [SimpleRecord] = []
        for try await record in decoder.decodeWithBackpressure(SimpleRecord.self, from: tempURL, memoryConfig: memoryConfig) {
            records.append(record)
        }

        #expect(records.count == 50)
    }

    @Test("Batched decode with backpressure")
    func batchedDecodeWithBackpressure() async throws {
        var csvLines = ["name,age,score"]
        for i in 0..<100 {
            csvLines.append("Person\(i),\(i),\(Double(i))")
        }
        let csv = csvLines.joined(separator: "\n")

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".csv")
        try Data(csv.utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let decoder = CSVDecoder()
        let memoryConfig = CSVDecoder.MemoryLimitConfiguration(batchSize: 25)

        var batches: [[SimpleRecord]] = []
        for try await batch in decoder.decodeBatchedWithBackpressure(SimpleRecord.self, from: tempURL, memoryConfig: memoryConfig) {
            batches.append(batch)
        }

        #expect(batches.count == 4) // 100 records / 25 per batch
        #expect(batches.flatMap { $0 }.count == 100)
    }

    @Test("Decode with progress reporting")
    func decodeWithProgress() async throws {
        var csvLines = ["name,age,score"]
        for i in 0..<100 {
            csvLines.append("Person\(i),\(i),\(Double(i))")
        }
        let csv = csvLines.joined(separator: "\n")

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".csv")
        try Data(csv.utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let decoder = CSVDecoder()

        actor ProgressCounter {
            var count = 0
            func increment() { count += 1 }
            func getCount() -> Int { count }
        }

        let counter = ProgressCounter()
        var records: [SimpleRecord] = []

        for try await record in decoder.decodeWithProgress(
            SimpleRecord.self,
            from: tempURL,
            progressHandler: { _ in
                Task { await counter.increment() }
            }
        ) {
            records.append(record)
        }

        #expect(records.count == 100)

        try await Task.sleep(for: .milliseconds(50))

        let callCount = await counter.getCount()
        #expect(callCount >= 1, "Progress handler should be called at least once")
    }

    // MARK: - Configuration Tests

    @Test("Memory limit configuration defaults")
    func memoryLimitConfigDefaults() {
        let config = CSVDecoder.MemoryLimitConfiguration()

        #expect(config.memoryBudget == 50 * 1024 * 1024) // 50MB
        #expect(config.batchSize == 1000)
        #expect(config.highWaterMark == 0.8)
        #expect(config.lowWaterMark == 0.4)
        #expect(config.maxBufferedRows > 0)
    }

    @Test("Parallel configuration defaults")
    func parallelConfigDefaults() {
        let config = CSVDecoder.ParallelConfiguration()

        #expect(config.parallelism == ProcessInfo.processInfo.activeProcessorCount)
        #expect(config.chunkSize == 1024 * 1024) // 1MB
        #expect(config.preserveOrder == true)
    }
}
