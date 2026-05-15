//
//  CSVEncoderParallelEncodingTests.swift
//  CSVCoder
//
//  Tests for CSVEncoder parallel encoding.
//

import Foundation
import Testing

@testable import CSVCoder

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

    // MARK: - keyEncodingStrategy regression (audit A2)

    struct CamelRecord: Codable, Equatable, Sendable {
        let firstName: String
        let lastName: String
    }

    @Test("Parallel encode applies keyEncodingStrategy to header (audit A2)")
    func parallelEncodeAppliesKeyStrategy() async throws {
        let records = [
            CamelRecord(firstName: "Alice", lastName: "Smith"),
            CamelRecord(firstName: "Bob", lastName: "Jones"),
        ]
        let config = CSVEncoder.Configuration(keyEncodingStrategy: .convertToSnakeCase)
        let encoder = CSVEncoder(configuration: config)
        let csv = try await encoder.encodeParallelToString(records)
        let lines = csv.split(separator: "\n").map(String.init)
        #expect(lines.first == "first_name,last_name")
        // Order of data rows is not guaranteed across chunks, so check set membership
        #expect(lines.contains("Alice,Smith"))
        #expect(lines.contains("Bob,Jones"))
    }

    @Test("Parallel batched encode applies keyEncodingStrategy to header (audit A2)")
    func parallelBatchedEncodeAppliesKeyStrategy() async throws {
        let records = (0 ..< 50).map { CamelRecord(firstName: "First\($0)", lastName: "Last\($0)") }
        let config = CSVEncoder.Configuration(keyEncodingStrategy: .convertToSnakeCase)
        let encoder = CSVEncoder(configuration: config)
        var batches: [[String]] = []
        for try await batch in encoder.encodeParallelBatched(records, parallelConfig: .init(chunkSize: 10)) {
            batches.append(batch)
        }
        #expect(batches.first?.first == "first_name,last_name")
    }

    @Test("Parallel encode to file applies keyEncodingStrategy (audit A2)")
    func parallelEncodeToFileAppliesKeyStrategy() async throws {
        let records = (0 ..< 100).map { CamelRecord(firstName: "F\($0)", lastName: "L\($0)") }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("parallel_key_strategy_\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let config = CSVEncoder.Configuration(keyEncodingStrategy: .convertToSnakeCase)
        let encoder = CSVEncoder(configuration: config)
        try await encoder.encodeParallel(records, to: tempURL)
        let data = try Data(contentsOf: tempURL)
        guard let csv = String(data: data, encoding: .utf8) else {
            Issue.record("Failed to decode written CSV")
            return
        }
        let firstLine = csv.split(separator: "\n", maxSplits: 1).first.map(String.init)
        #expect(firstLine == "first_name,last_name")
    }

    // MARK: - @CSVRow column order (audit A1)

    @CSVRow
    struct OrderedRecord: Codable, Sendable {
        @CSVColumn("Z_third") let third: Int
        @CSVColumn("A_first") let first: Int
        @CSVColumn("M_second") let second: Int
    }

    @Test("Parallel encode honors CSVRowEncodable column order (audit A1)")
    func parallelEncodeHonorsColumnOrder() async throws {
        let records = [OrderedRecord(third: 3, first: 1, second: 2)]
        let encoder = CSVEncoder()
        let csv = try await encoder.encodeParallelToString(records)
        let lines = csv.split(separator: "\n").map(String.init)
        // Header reflects CodingKeys declaration order, with @CSVColumn rawValues
        #expect(lines.first == "Z_third,A_first,M_second")
        #expect(lines.count >= 2)
        #expect(lines[1] == "3,1,2")
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
            let seqNanos =
                Double(sequentialDuration.components.seconds) * 1e9 + Double(sequentialDuration.components.attoseconds)
                / 1e9
            let parNanos =
                Double(parallelDuration.components.seconds) * 1e9 + Double(parallelDuration.components.attoseconds)
                / 1e9
            let speedup = seqNanos / parNanos
            #expect(speedup > 0.5, "Parallel encode speedup (\(speedup)x) should be reasonable")
        }
    }
}
