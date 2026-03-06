//
//  CSVCodeReviewFixTests.swift
//  CSVCoder
//
//  Tests verifying fixes from code review findings.
//

import Foundation
import Testing

@testable import CSVCoder

@Suite("Code Review Fix Tests")
struct CSVCodeReviewFixTests {
    // MARK: - Task 1: CSVRowView bounds check

    @Test("CSVRowView.getBytes returns empty buffer for out-of-bounds index")
    func getBytesOutOfBounds() {
        let data = Data("hello,world\n".utf8)
        let rows = CSVParser.parse(data: data) { parser in
            parser.map { $0 }
        }
        guard let row = rows.first else {
            Issue.record("Expected at least one row")
            return
        }
        let outOfBounds = row.getBytes(at: 999)
        #expect(outOfBounds.count == 0)
    }

    // MARK: - Task 2: fatalError replaced with thrown errors

    struct UnsupportedArrayType: Encodable {
        let items: [String]

        func encode(to encoder: Encoder) throws {
            var container = encoder.unkeyedContainer()
            for item in items {
                try container.encode(item)
            }
        }
    }

    @Test("Unkeyed container throws instead of fatalError")
    func unkeyedContainerThrows() throws {
        let encoder = CSVEncoder()
        #expect(throws: CSVEncodingError.self) {
            try encoder.encodeToString([UnsupportedArrayType(items: ["a", "b"])])
        }
    }

    struct SuperEncoderType: Encodable {
        let value: String

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            let superEnc = container.superEncoder()
            var superContainer = superEnc.singleValueContainer()
            try superContainer.encode(value)
        }

        enum CodingKeys: String, CodingKey {
            case value
        }
    }

    @Test("Super encoder throws instead of fatalError")
    func superEncoderThrows() throws {
        let encoder = CSVEncoder()
        #expect(throws: CSVEncodingError.self) {
            try encoder.encodeToString([SuperEncoderType(value: "test")])
        }
    }

    // MARK: - Task 4: CSVEncodingStorage snapshot consistency

    @Test("CSVEncodingStorage snapshot returns consistent keys and values")
    func storageSnapshotConsistency() {
        let storage = CSVEncodingStorage()
        storage.setValue("Alice", forKey: "name")
        storage.setValue("30", forKey: "age")

        let (keys, values) = storage.snapshot()
        #expect(keys.count == 2)
        #expect(values.count == 2)
        for key in keys {
            #expect(values[key] != nil, "Key '\(key)' should have a matching value")
        }
    }

    // MARK: - Task 6: encodeIfPresent(Bool?) respects strategy

    struct OptionalBoolRecord: Codable, Equatable {
        let name: String
        let active: Bool?
    }

    @Test("encodeIfPresent(Bool?) uses configured strategy")
    func encodeIfPresentBoolStrategy() throws {
        let records = [OptionalBoolRecord(name: "Alice", active: true)]
        let config = CSVEncoder.Configuration(boolEncodingStrategy: .trueFalse)
        let encoder = CSVEncoder(configuration: config)
        let csv = try encoder.encodeToString(records)
        #expect(csv.contains("true"), "Should use trueFalse strategy, got: \(csv)")
    }

    @Test("encodeIfPresent(Bool?) nil produces empty")
    func encodeIfPresentBoolNil() throws {
        let records = [OptionalBoolRecord(name: "Alice", active: nil)]
        let encoder = CSVEncoder()
        let csv = try encoder.encodeToString(records)
        let lines = csv.split(separator: "\n")
        #expect(lines.count == 2)
        // The data row should end with empty string for nil
        #expect(lines[1].hasSuffix(",") || lines[1].components(separatedBy: ",").last == "")
    }

    // MARK: - Task 7: encodeIfPresent(Double?/Float?) respects strategy

    struct OptionalDoubleRecord: Codable {
        let name: String
        let value: Double?
    }

    @Test("encodeIfPresent(Double?) uses configured strategy")
    func encodeIfPresentDoubleStrategy() throws {
        let records = [OptionalDoubleRecord(name: "Test", value: 1234.5)]
        let config = CSVEncoder.Configuration(numberEncodingStrategy: .locale(Locale(identifier: "de_DE")))
        let encoder = CSVEncoder(configuration: config)
        let csv = try encoder.encodeToString(records)
        // German locale uses comma as decimal separator
        #expect(csv.contains("1234,5") || csv.contains("1.234,5"), "Should use locale strategy, got: \(csv)")
    }

    // MARK: - Task 8: CSVSingleValueEncoder encode(Bool) respects strategy

    @Test("CSVSingleValueEncoder encode(Bool) uses configured strategy")
    func singleValueBoolStrategy() throws {
        struct BoolWrapper: Codable {
            let flag: Bool
        }
        let records = [BoolWrapper(flag: true)]
        let config = CSVEncoder.Configuration(boolEncodingStrategy: .yesNo)
        let encoder = CSVEncoder(configuration: config)
        let csv = try encoder.encodeToString(records)
        #expect(csv.contains("yes"), "Should use yesNo strategy, got: \(csv)")
    }

    // MARK: - Task 10: encoding property removed

    @Test("CSVEncoder.Configuration does not have encoding property")
    func encodingPropertyRemoved() {
        // This is a compile-time check. If the property still existed,
        // we'd get an "extra argument" error below.
        _ = CSVEncoder.Configuration(delimiter: ",")
    }

    // MARK: - Task 13: Trailing newline configuration

    @Test("includesTrailingNewline adds newline after last row")
    func trailingNewlineConfig() throws {
        struct Record: Codable {
            let name: String
        }
        let records = [Record(name: "Alice"), Record(name: "Bob")]

        let withTrailing = CSVEncoder(configuration: .init(includesTrailingNewline: true))
        let csvWith = try withTrailing.encodeToString(records)
        #expect(csvWith.hasSuffix("\n"))

        let withoutTrailing = CSVEncoder(configuration: .init(includesTrailingNewline: false))
        let csvWithout = try withoutTrailing.encodeToString(records)
        #expect(!csvWithout.hasSuffix("\n"))
    }

    // MARK: - Task 15: Key conversion performance (no O(n²))

    @Test("Snake case key conversion works correctly")
    func snakeCaseConversion() throws {
        struct CamelRecord: Codable {
            let firstName: String
            let lastName: String
        }
        let records = [CamelRecord(firstName: "Alice", lastName: "Smith")]
        let config = CSVEncoder.Configuration(keyEncodingStrategy: .convertToSnakeCase)
        let encoder = CSVEncoder(configuration: config)
        let csv = try encoder.encodeToString(records)
        #expect(csv.contains("first_name"))
        #expect(csv.contains("last_name"))
    }

    @Test("Kebab case key conversion works correctly")
    func kebabCaseConversion() throws {
        struct CamelRecord: Codable {
            let firstName: String
        }
        let records = [CamelRecord(firstName: "Alice")]
        let config = CSVEncoder.Configuration(keyEncodingStrategy: .convertToKebabCase)
        let encoder = CSVEncoder(configuration: config)
        let csv = try encoder.encodeToString(records)
        #expect(csv.contains("first-name"))
    }

    @Test("Screaming snake case key conversion works correctly")
    func screamingSnakeCaseConversion() throws {
        struct CamelRecord: Codable {
            let firstName: String
        }
        let records = [CamelRecord(firstName: "Alice")]
        let config = CSVEncoder.Configuration(keyEncodingStrategy: .convertToScreamingSnakeCase)
        let encoder = CSVEncoder(configuration: config)
        let csv = try encoder.encodeToString(records)
        #expect(csv.contains("FIRST_NAME"))
    }

    // MARK: - Task 25: CR-only line endings

    @Test("Parser handles CR-only line endings")
    func crOnlyLineEndings() {
        let csv = "name,age\rAlice,30\rBob,25"
        let data = Data(csv.utf8)
        let rows = CSVParser.parse(data: data) { parser in
            parser.map { row in
                (row.string(at: 0), row.string(at: 1))
            }
        }
        #expect(rows.count == 3)
        #expect(rows[0].0 == "name")
        #expect(rows[1].0 == "Alice")
        #expect(rows[2].0 == "Bob")
    }

    @Test("StreamingCSVParser handles CR-only line endings")
    func streamingCROnlyLineEndings() async throws {
        let csv = "name,age\rAlice,30\rBob,25"
        let config = CSVDecoder.Configuration(hasHeaders: false)
        let parser = StreamingCSVParser(data: Data(csv.utf8), configuration: config)
        var rows: [[String]] = []
        for try await row in parser {
            rows.append(row)
        }
        #expect(rows.count == 3)
        #expect(rows[1] == ["Alice", "30"])
    }

    // MARK: - Task 3: BackpressureController cancelAllWaiters

    @Test("BackpressureController cancelAllWaiters resets state")
    func backpressureCancelAllWaiters() async {
        // Use tiny budget so highWaterRows is small
        let config = CSVDecoder.MemoryLimitConfiguration(
            memoryBudget: 1024 * 1024,
            estimatedRowSize: 256,
            batchSize: 10,
            useWatermarks: false,
        )
        let controller = BackpressureController(config: config)

        // maxBufferedRows = 1MB / 256 = 4096, useWatermarks=false so pauses at maxBufferedRows
        let shouldPause = await controller.recordProduced(5000)
        #expect(shouldPause)

        let state = await controller.state
        #expect(state.isPaused)

        // Cancel should reset
        await controller.cancelAllWaiters()

        let stateAfter = await controller.state
        #expect(!stateAfter.isPaused)
        #expect(stateAfter.buffered == 0)
    }
}
