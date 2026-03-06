//
//  CSVConcurrencyStressTests.swift
//  CSVCoder
//
//  Stress-tests concurrent encode/decode from multiple tasks, verifying data integrity
//  and that CSVEncodingStorage snapshot() returns consistent state under concurrent writes.
//

import Foundation
import Testing

@testable import CSVCoder

@Suite("CSVConcurrency Stress Tests")
struct CSVConcurrencyStressTests {
    struct SimpleRecord: Codable, Equatable, Sendable {
        let id: Int
        let name: String
    }

    // MARK: - Concurrent Encoding

    /// Launches 10 concurrent tasks each encoding a distinct batch through the same
    /// CSVEncoder instance, then verifies every result contains valid CSV with the
    /// expected header and exactly the right number of data rows.
    @Test("Shared encoder produces valid CSV from 10 concurrent tasks")
    func sharedEncoderConcurrentEncoding() async throws {
        let encoder = CSVEncoder()
        let taskCount = 10
        let recordsPerTask = 20

        // Each task encodes a uniquely-identified batch and returns the CSV string.
        let results: [String] = try await withThrowingTaskGroup(of: String.self) { group in
            for taskIndex in 0 ..< taskCount {
                group.addTask {
                    let records = (0 ..< recordsPerTask).map { i in
                        SimpleRecord(id: taskIndex * recordsPerTask + i, name: "Task\(taskIndex)_Record\(i)")
                    }
                    return try encoder.encodeToString(records)
                }
            }

            var collected: [String] = []
            collected.reserveCapacity(taskCount)
            for try await csv in group {
                collected.append(csv)
            }
            return collected
        }

        #expect(results.count == taskCount)

        for csv in results {
            let lines = csv
                .components(separatedBy: "\n")
                .filter { !$0.isEmpty }

            // First line must be the header.
            #expect(lines.first == "id,name")

            // Each batch must have exactly recordsPerTask data rows.
            let dataLines = lines.dropFirst()
            #expect(dataLines.count == recordsPerTask)

            // Every data row must have exactly two comma-separated fields.
            for line in dataLines {
                let fields = line.components(separatedBy: ",")
                #expect(fields.count == 2, "Malformed CSV row: \(line)")
            }
        }
    }

    // MARK: - Concurrent Decoding

    /// Builds 10 distinct CSV payloads, decodes them concurrently through the same
    /// CSVDecoder instance, and verifies each result matches the original records.
    @Test("Shared decoder produces correct results from 10 concurrent tasks")
    func sharedDecoderConcurrentDecoding() async throws {
        let decoder = CSVDecoder()
        let taskCount = 10
        let recordsPerTask = 15

        // Pre-build all CSV strings up front so tasks are purely decode work.
        let encoder = CSVEncoder()
        let payloads: [(expected: [SimpleRecord], csv: String)] = try (0 ..< taskCount).map { taskIndex in
            let records = (0 ..< recordsPerTask).map { i in
                SimpleRecord(id: taskIndex * recordsPerTask + i, name: "Batch\(taskIndex)_Item\(i)")
            }
            let csv = try encoder.encodeToString(records)
            return (expected: records, csv: csv)
        }

        // Decode all payloads concurrently.
        let results: [(index: Int, decoded: [SimpleRecord])] = try await withThrowingTaskGroup(
            of: (Int, [SimpleRecord]).self
        ) { group in
            for (index, payload) in payloads.enumerated() {
                let csv = payload.csv
                group.addTask {
                    let decoded: [SimpleRecord] = try decoder.decode(from: csv)
                    return (index, decoded)
                }
            }

            var collected: [(index: Int, decoded: [SimpleRecord])] = []
            collected.reserveCapacity(taskCount)
            for try await pair in group {
                collected.append((index: pair.0, decoded: pair.1))
            }
            return collected
        }

        #expect(results.count == taskCount)

        for result in results {
            let expected = payloads[result.index].expected
            #expect(result.decoded == expected, "Mismatch for task \(result.index)")
        }
    }

    // MARK: - CSVEncodingStorage Snapshot Consistency

    /// Writes to a single CSVEncodingStorage from multiple concurrent tasks and
    /// verifies that snapshot() always returns a consistent state: every key in
    /// `keys` has a corresponding entry in `values`, and the counts match.
    @Test("CSVEncodingStorage snapshot is consistent under concurrent writes")
    func encodingStorageSnapshotConsistency() async throws {
        let storage = CSVEncodingStorage()
        let taskCount = 10
        let keysPerTask = 50

        // Flood the storage with concurrent writes from multiple tasks.
        await withTaskGroup(of: Void.self) { group in
            for taskIndex in 0 ..< taskCount {
                group.addTask {
                    for keyIndex in 0 ..< keysPerTask {
                        let key = "task\(taskIndex)_key\(keyIndex)"
                        let value = "value_\(taskIndex)_\(keyIndex)"
                        storage.setValue(value, forKey: key)
                    }
                }
            }
        }

        // After all writes have completed, take a snapshot and verify consistency.
        let snap = storage.snapshot()

        // Every key recorded in `keys` must map to a value in `values`.
        #expect(snap.keys.count == snap.values.count)

        for key in snap.keys {
            let value = snap.values[key]
            #expect(value != nil, "Key '\(key)' present in ordered keys but missing from values dictionary")
        }

        // All written keys must be present (taskCount * keysPerTask unique keys).
        let expectedKeyCount = taskCount * keysPerTask
        #expect(snap.keys.count == expectedKeyCount)

        // Spot-check: every expected key exists and has the correct value.
        for taskIndex in 0 ..< taskCount {
            for keyIndex in 0 ..< keysPerTask {
                let key = "task\(taskIndex)_key\(keyIndex)"
                let expectedValue = "value_\(taskIndex)_\(keyIndex)"
                #expect(snap.values[key] == expectedValue, "Wrong value for key '\(key)'")
            }
        }
    }
}
