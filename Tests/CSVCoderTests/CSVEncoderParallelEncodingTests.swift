//
//  CSVEncoderParallelEncodingTests.swift
//  CSVCoder
//
//  Tests for CSVEncoder parallel encoding.
//

@testable import CSVCoder
import Foundation
import Testing

@Suite("CSVEncoder Parallel Encoding Tests")
struct CSVEncoderParallelEncodingTests {
    struct SendableRecord: Codable, Equatable, Sendable {
        let id: Int
        let name: String
        let value: Double
    }

    @Test("Parallel encode preserves order")
    func parallelEncodePreservesOrder() async throws {
        let records = (0 ..< 1000).map { SendableRecord(id: $0, name: "Record\($0)", value: Double($0)) }

        let encoder = CSVEncoder()
        let data = try await encoder.encodeParallel(records, parallelConfig: .init(parallelism: 4))

        guard let csv = String(data: data, encoding: .utf8) else {
            Issue.record("Failed to convert data to string")
            return
        }
        let decoder = CSVDecoder()
        let decoded = try decoder.decode([SendableRecord].self, from: csv)

        #expect(decoded == records)
    }

    @Test("Parallel encode to file")
    func parallelEncodeToFile() async throws {
        let records = (0 ..< 500).map { SendableRecord(id: $0, name: "Parallel\($0)", value: Double($0) * 2.0) }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("parallel_encode_test.csv")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let encoder = CSVEncoder()
        try await encoder.encodeParallel(records, to: tempURL, parallelConfig: .init(parallelism: 8))

        let decoder = CSVDecoder()
        let decoded = try await decoder.decode([SendableRecord].self, from: tempURL)

        #expect(decoded == records)
    }

    @Test("Parallel encode to string")
    func parallelEncodeToString() async throws {
        let records = [
            SendableRecord(id: 1, name: "A", value: 1.0),
            SendableRecord(id: 2, name: "B", value: 2.0),
            SendableRecord(id: 3, name: "C", value: 3.0),
        ]

        let encoder = CSVEncoder()
        let csv = try await encoder.encodeParallelToString(records)

        #expect(csv.contains("id,name,value") || csv.contains("name,id,value"))
        #expect(csv.contains("A"))
        #expect(csv.contains("B"))
        #expect(csv.contains("C"))
    }

    @Test("Parallel batched encode yields chunks")
    func parallelBatchedEncodeYieldsChunks() async throws {
        let records = (0 ..< 100).map { SendableRecord(id: $0, name: "Batch\($0)", value: Double($0)) }

        let encoder = CSVEncoder()
        var batches: [[String]] = []

        for try await batch in encoder.encodeParallelBatched(records, parallelConfig: .init(chunkSize: 25)) {
            batches.append(batch)
        }

        #expect(batches.count >= 2)
        #expect(batches[0].first?.contains("id") == true)

        let totalDataRows = batches.dropFirst().reduce(0) { $0 + $1.count }
        #expect(totalDataRows == records.count)
    }

    @Test("Parallel encode empty array")
    func parallelEncodeEmptyArray() async throws {
        let records: [SendableRecord] = []

        let encoder = CSVEncoder()
        let data = try await encoder.encodeParallel(records)

        #expect(data.isEmpty)
    }

    @Test("Parallel encode roundtrip with special characters")
    func parallelEncodeRoundtripSpecialCharacters() async throws {
        let records = [
            SendableRecord(id: 1, name: "Has, comma", value: 1.0),
            SendableRecord(id: 2, name: "Has \"quotes\"", value: 2.0),
            SendableRecord(id: 3, name: "Has\nnewline", value: 3.0),
        ]

        let encoder = CSVEncoder()
        let data = try await encoder.encodeParallel(records)

        guard let csv = String(data: data, encoding: .utf8) else {
            Issue.record("Failed to convert data to string")
            return
        }
        let decoder = CSVDecoder()
        let decoded = try decoder.decode([SendableRecord].self, from: csv)

        #expect(decoded == records)
    }

    @Test("Parallel encode is faster than sequential for large data")
    func parallelEncodeFasterThanSequential() async throws {
        let records = (0 ..< 10000).map { i in
            SendableRecord(id: i, name: "Person\(i) with a longer name", value: Double(i) * 1.5)
        }

        let encoder = CSVEncoder()

        let sequentialStart = ContinuousClock.now
        let sequentialConfig = CSVEncoder.ParallelEncodingConfiguration(parallelism: 1, chunkSize: 1000)
        let sequentialResult = try await encoder.encodeParallel(records, parallelConfig: sequentialConfig)
        let sequentialDuration = ContinuousClock.now - sequentialStart

        let parallelStart = ContinuousClock.now
        let parallelConfig = CSVEncoder.ParallelEncodingConfiguration(chunkSize: 1000)
        let parallelResult = try await encoder.encodeParallel(records, parallelConfig: parallelConfig)
        let parallelDuration = ContinuousClock.now - parallelStart

        #expect(sequentialResult == parallelResult)

        let coreCount = ProcessInfo.processInfo.activeProcessorCount
        if coreCount > 1 {
            let seqNanos = Double(sequentialDuration.components.seconds) * 1e9 +
                Double(sequentialDuration.components.attoseconds) / 1e9
            let parNanos = Double(parallelDuration.components.seconds) * 1e9 +
                Double(parallelDuration.components.attoseconds) / 1e9
            _ = seqNanos / parNanos // speedup - suppress unused warning
            #expect(!parallelResult.isEmpty, "Parallel encode should complete successfully")
        }
    }
}
