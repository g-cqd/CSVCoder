//
//  CSVDecoderCancellationTests.swift
//  CSVCoder
//
//  Tests for cancellation safety in streaming and backpressure decoding.
//

@testable import CSVCoder
import Foundation
import Testing

@Suite("CSVDecoder Cancellation Tests")
struct CSVDecoderCancellationTests {
    struct NameAge: Codable, Equatable, Sendable {
        let name: String
        let age: Int
    }

    // Writes CSV rows to a temp file and returns the URL.
    // The caller is responsible for cleanup via defer.
    private func makeCSVFile(rowCount: Int) throws -> URL {
        var lines = ["name,age"]
        for i in 0..<rowCount {
            lines.append("Person\(i),\(i)")
        }
        let csv = lines.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".csv")
        try Data(csv.utf8).write(to: url)
        return url
    }

    // MARK: - Test 1: Cancelling a streaming decode mid-stream does not hang

    @Test("Cancelling a streaming decode task mid-stream completes without hanging")
    func cancelStreamingDecodeMidStream() async throws {
        // Build a large enough dataset so the stream is still producing when we cancel.
        let csv = (["name,age"] + (0..<500).map { "Person\($0),\($0)" }).joined(separator: "\n")
        let data = Data(csv.utf8)
        let decoder = CSVDecoder()

        // Confirm cancels promptly — if the stream hangs, the test will time out.
        // We use an actor to safely share state between the outer scope and the task.
        actor Counter {
            var value = 0
            func increment() { value += 1 }
        }
        let counter = Counter()

        // The task is stored so it can be cancelled from outside after we observe enough rows.
        let task: Task<Void, Error> = Task {
            for try await _ in decoder.decode(NameAge.self, from: data) {
                await counter.increment()
            }
        }

        // Poll until at least 5 rows have been decoded, then cancel.
        while await counter.value < 5 {
            await Task.yield()
        }
        task.cancel()

        // Awaiting the cancelled task must return; a hang here means the stream leaked.
        _ = try? await task.value

        #expect(await counter.value >= 5)
    }

    // MARK: - Test 3: Backpressure stream task cancellation triggers onTermination cleanup

    @Test("Cancelling a backpressure stream triggers cleanup and does not hang")
    func cancelBackpressureStreamDoesNotHang() async throws {
        // Use 200 rows and a tiny batch size to ensure the producer is still running
        // when we cancel after consuming the first batch.
        let url = try makeCSVFile(rowCount: 200)
        defer { try? FileManager.default.removeItem(at: url) }

        let decoder = CSVDecoder()
        let memoryConfig = CSVDecoder.MemoryLimitConfiguration(
            memoryBudget: 1024 * 1024,
            estimatedRowSize: 256,
            batchSize: 10,
        )

        actor Counter {
            var value = 0
            func increment() { value += 1 }
        }
        let counter = Counter()

        let task: Task<Void, Error> = Task {
            for try await _ in decoder.decodeWithBackpressure(
                NameAge.self,
                from: url,
                memoryConfig: memoryConfig,
            ) {
                await counter.increment()
            }
        }

        // Wait until the first batch has been consumed, then cancel.
        while await counter.value < 10 {
            await Task.yield()
        }
        task.cancel()

        // If onTermination does not call cancelAllWaiters, the producer parks
        // indefinitely and this await never returns.
        _ = try? await task.value

        // Confirm that records were decoded before cancellation.
        #expect(await counter.value >= 1)
    }
}
