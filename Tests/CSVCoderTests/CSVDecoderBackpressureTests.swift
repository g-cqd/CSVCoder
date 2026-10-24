//
//  CSVDecoderBackpressureTests.swift
//  CSVCoder
//
//  The backpressure streams must deliver every row to a consumer of any speed, and must not read
//  ahead of it. Formal model: formal/BackpressureOld.tla (deadlock) and BackpressureNew.tla.
//

import Foundation
import Testing

@testable import CSVCoder

@Suite("CSVDecoder backpressure delivery")
struct CSVDecoderBackpressureTests {
    struct NameAge: Codable, Equatable, Sendable {
        let name: String
        let age: Int
    }

    private static func makeFile(rows: Int, badRowAt: Int? = nil) throws -> URL {
        var csv = "name,age\n"
        for i in 0..<rows {
            csv += i == badRowAt ? "Person\(i),\(i),extra\n" : "Person\(i),\(i)\n"
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".csv")
        try Data(csv.utf8).write(to: url)
        return url
    }

    /// Synchronous work that the optimiser cannot remove: stands for a consumer slower than the parser.
    @inline(never)
    private static func slowWork(_ iterations: Int) -> Int {
        var acc = 0
        for i in 0..<iterations { acc = acc &+ (i ^ acc) }
        return acc
    }

    // One estimated row of 100 KB in a 1 MiB budget: the old controller parked its producer after the first
    // batch of 10 rows and never woke it. Small inputs keep the tests from competing for CPU with the
    // wall-clock tests that run beside them.
    private static let config = CSVDecoder.MemoryLimitConfiguration(
        memoryBudget: 1024 * 1024, estimatedRowSize: 100_000, batchSize: 10)

    @Test("A consumer that reads everything receives every row past the high-water mark", .timeLimit(.minutes(1)))
    func rowsPastHighWaterMarkAreDelivered() async throws {
        let url = try Self.makeFile(rows: 300)
        defer { try? FileManager.default.removeItem(at: url) }

        var received = 0
        for try await _ in CSVDecoder().decodeWithBackpressure(NameAge.self, from: url, memoryConfig: Self.config) {
            received += 1
        }
        #expect(received == 300)
    }

    @Test("A slow consumer of rows receives every row in order", .timeLimit(.minutes(1)))
    func slowRowConsumerLosesNothing() async throws {
        let url = try Self.makeFile(rows: 300)
        defer { try? FileManager.default.removeItem(at: url) }

        var next = 0
        var inOrder = true
        var sink = 0
        for try await row in CSVDecoder().decodeWithBackpressure(NameAge.self, from: url, memoryConfig: Self.config) {
            inOrder = inOrder && row.age == next
            next += 1
            sink &+= Self.slowWork(5_000)
        }
        #expect(inOrder)
        #expect(next == 300)
        #expect(sink != 1)
    }

    @Test("A slow consumer of batches receives every row in order", .timeLimit(.minutes(1)))
    func slowBatchConsumerLosesNothing() async throws {
        let url = try Self.makeFile(rows: 300)
        defer { try? FileManager.default.removeItem(at: url) }

        var next = 0
        var inOrder = true
        var largest = 0
        var sink = 0
        for try await batch in CSVDecoder().decodeBatchedWithBackpressure(
            NameAge.self, from: url, memoryConfig: Self.config)
        {
            largest = max(largest, batch.count)
            for row in batch {
                inOrder = inOrder && row.age == next
                next += 1
            }
            sink &+= Self.slowWork(300_000)
        }
        #expect(inOrder)
        #expect(largest == 10)
        #expect(next == 300)
        #expect(sink != 1)
    }

    @Test("A malformed row is reported after every row before it", .timeLimit(.minutes(1)))
    func errorArrivesAfterEarlierRows() async throws {
        let url = try Self.makeFile(rows: 500, badRowAt: 300)
        defer { try? FileManager.default.removeItem(at: url) }

        let decoder = CSVDecoder(configuration: .init(expectedFieldCount: 2))
        var received = 0
        await #expect(throws: CSVDecodingError.self) {
            for try await _ in decoder.decodeWithBackpressure(NameAge.self, from: url, memoryConfig: Self.config) {
                received += 1
            }
        }
        #expect(received == 300)
    }

    @Test("A malformed row inside a batch is reported after the rows that precede it", .timeLimit(.minutes(1)))
    func batchErrorArrivesAfterEarlierRows() async throws {
        let url = try Self.makeFile(rows: 500, badRowAt: 250)
        defer { try? FileManager.default.removeItem(at: url) }

        let decoder = CSVDecoder(configuration: .init(expectedFieldCount: 2))
        var received = 0
        await #expect(throws: CSVDecodingError.self) {
            for try await batch in decoder.decodeBatchedWithBackpressure(
                NameAge.self, from: url, memoryConfig: Self.config)
            {
                received += batch.count
            }
        }
        #expect(received == 250)
    }

    @Test("A missing file fails the stream instead of hanging", .timeLimit(.minutes(1)))
    func missingFileFails() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".csv")
        await #expect(throws: (any Error).self) {
            for try await _ in CSVDecoder().decodeBatchedWithBackpressure(NameAge.self, from: url) {}
        }
    }
}
