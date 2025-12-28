import Benchmark
import CSVCoder
import Foundation

print("Starting Benchmark Registration...")

// MARK: - Raw CSVParser Benchmarks (No Codable Overhead)
// Defined early to ensure registration

benchmark("Raw Parse 1M rows (Iterate Only)") {
    simple1MData.withUnsafeBytes { buffer in
        let parser = CSVParser(buffer: buffer.bindMemory(to: UInt8.self), delimiter: 0x2C)
        var count = 0
        for _ in parser {
            count += 1
        }
        precondition(count == 1_000_001)
    }
}

benchmark("Raw Parse 1M rows (Iterate + String)") {
    simple1MData.withUnsafeBytes { buffer in
        let parser = CSVParser(buffer: buffer.bindMemory(to: UInt8.self), delimiter: 0x2C)
        for row in parser {
            _ = row.string(at: 0)
            _ = row.string(at: 1)
            _ = row.string(at: 2)
        }
    }
}

benchmark("Raw Parse 100K Quoted Rows (Iterate Only)") {
    quoted100KData.withUnsafeBytes { buffer in
        let parser = CSVParser(buffer: buffer.bindMemory(to: UInt8.self), delimiter: 0x2C)
        var count = 0
        for _ in parser {
            count += 1
        }
        precondition(count == 100_001)
    }
}

benchmark("Raw Parse 100K Quoted Rows (Iterate + String)") {
    quoted100KData.withUnsafeBytes { buffer in
        let parser = CSVParser(buffer: buffer.bindMemory(to: UInt8.self), delimiter: 0x2C)
        for row in parser {
            _ = row.string(at: 0)
            _ = row.string(at: 1) // "Item X" (quoted)
            _ = row.string(at: 2) // Description (quoted with internal quotes)
            _ = row.string(at: 3) // Int
        }
    }
}

// MARK: - Test Data

struct SimpleRecord: Codable, Sendable {
    let name: String
    let age: Int
    let score: Double
}

struct ComplexRecord: Codable, Sendable {
    let id: Int
    let firstName: String
    let lastName: String
    let email: String
    let age: Int
    let salary: Double
    let isActive: Bool
    let notes: String
}

struct QuotedRecord: Codable, Sendable {
    let name: String
    let description: String
    let value: Int
}

// MARK: - Generators

nonisolated func generateSimpleCSV(rows: Int) -> String {
    var csv = "name,age,score\n"
    for i in 0..<rows {
        csv += "Person\(i),\(20 + i % 50),\(Double(i) * 0.1)\n"
    }
    return csv
}

nonisolated func generateComplexCSV(rows: Int) -> String {
    var csv = "id,firstName,lastName,email,age,salary,isActive,notes\n"
    for i in 0..<rows {
        csv += "\(i),John,Doe\(i),john\(i)@example.com,\(25 + i % 40),\(50000.0 + Double(i) * 100),\(i % 2 == 0),\"Some notes here with text\"\n"
    }
    return csv
}

nonisolated func generateQuotedCSV(rows: Int) -> String {
    var csv = "name,description,value\n"
    for i in 0..<rows {
        csv += "\"Item \(i)\",\"A description with, commas and \"\"quotes\"\"\",\(i * 10)\n"
    }
    return csv
}

nonisolated func generateWideCSV(rows: Int, columns: Int) -> String {
    var csv = (0..<columns).map { "col\($0)" }.joined(separator: ",") + "\n"
    for i in 0..<rows {
        csv += (0..<columns).map { _ in "value\(i)" }.joined(separator: ",") + "\n"
    }
    return csv
}

nonisolated func generateLongFieldCSV(rows: Int, fieldLength: Int) -> String {
    let longValue = String(repeating: "x", count: fieldLength)
    var csv = "id,data\n"
    for i in 0..<rows {
        csv += "\(i),\(longValue)\n"
    }
    return csv
}

nonisolated func generateNumericCSV(rows: Int) -> String {
    var csv = "intVal,doubleVal,floatVal\n"
    for i in 0..<rows {
        csv += "\(i),\(Double(i) * 1.5),\(Float(i) * 0.5)\n"
    }
    return csv
}

// MARK: - Pre-generated Datasets (scaled up 10-100x)

// Simple datasets
let simple1K = generateSimpleCSV(rows: 1_000)
let simple1KData = Data(simple1K.utf8)

let simple10K = generateSimpleCSV(rows: 10_000)
let simple10KData = Data(simple10K.utf8)

let simple100K = generateSimpleCSV(rows: 100_000)
let simple100KData = Data(simple100K.utf8)

let simple1M = generateSimpleCSV(rows: 1_000_000)
let simple1MData = Data(simple1M.utf8)

// Complex dataset (10K rows, 8 fields each)
let complex10K = generateComplexCSV(rows: 10_000)
let complex10KData = Data(complex10K.utf8)

// Quoted dataset (10K rows)
let quoted10K = generateQuotedCSV(rows: 10_000)
let quoted10KData = Data(quoted10K.utf8)

let quoted100K = generateQuotedCSV(rows: 100_000)
let quoted100KData = Data(quoted100K.utf8)

// Wide dataset (10K rows, 50 columns)
let wide50Col10K = generateWideCSV(rows: 10_000, columns: 50)
let wide50Col10KData = Data(wide50Col10K.utf8)

// Long field dataset (10K rows, 500-byte fields)
let longField10K = generateLongFieldCSV(rows: 10_000, fieldLength: 500)
let longField10KData = Data(longField10K.utf8)

// Numeric dataset (100K rows)
let numeric100K = generateNumericCSV(rows: 100_000)
let numeric100KData = Data(numeric100K.utf8)

// Pre-generated records for encoding benchmarks
let simpleRecords1K = (0..<1_000).map { SimpleRecord(name: "Person\($0)", age: 20 + $0 % 50, score: Double($0) * 0.1) }
let simpleRecords10K = (0..<10_000).map { SimpleRecord(name: "Person\($0)", age: 20 + $0 % 50, score: Double($0) * 0.1) }
let simpleRecords100K = (0..<100_000).map { SimpleRecord(name: "Person\($0)", age: 20 + $0 % 50, score: Double($0) * 0.1) }
let simpleRecords1M = (0..<1_000_000).map { SimpleRecord(name: "Person\($0)", age: 20 + $0 % 50, score: Double($0) * 0.1) }

let quotedRecords10K = (0..<10_000).map { i in
    QuotedRecord(name: "Item \(i)", description: "A \"description\" with, commas", value: i * 10)
}

struct LongFieldRecord: Codable, Sendable {
    let id: Int
    let data: String
}

let longFieldRecords10K = (0..<10_000).map { LongFieldRecord(id: $0, data: String(repeating: "x", count: 500)) }

// MARK: - Decoding Benchmarks

benchmark("Decode 1K rows (simple)") {
    let decoder = CSVDecoder()
    let result: [SimpleRecord] = try decoder.decode(from: simple1KData)
    precondition(result.count == 1_000)
}

benchmark("Decode 10K rows (simple)") {
    let decoder = CSVDecoder()
    let result: [SimpleRecord] = try decoder.decode(from: simple10KData)
    precondition(result.count == 10_000)
}

benchmark("Decode 100K rows (simple)") {
    let decoder = CSVDecoder()
    let result: [SimpleRecord] = try decoder.decode(from: simple100KData)
    precondition(result.count == 100_000)
}

benchmark("Decode 1M rows (simple)") {
    let decoder = CSVDecoder()
    let result: [SimpleRecord] = try decoder.decode(from: simple1MData)
    precondition(result.count == 1_000_000)
}

benchmark("Decode 10K rows (complex, 8 fields)") {
    let decoder = CSVDecoder()
    let result: [ComplexRecord] = try decoder.decode(from: complex10KData)
    precondition(result.count == 10_000)
}

benchmark("Decode 10K rows (quoted fields)") {
    let decoder = CSVDecoder()
    let result: [QuotedRecord] = try decoder.decode(from: quoted10KData)
    precondition(result.count == 10_000)
}

struct WideRecord: Codable, Sendable {
    let col0: String
    let col1: String
    let col2: String
    let col3: String
    let col4: String
}

benchmark("Decode 10K rows (50 columns wide)") {
    let decoder = CSVDecoder()
    let result: [WideRecord] = try decoder.decode(from: wide50Col10KData)
    precondition(result.count == 10_000)
}

benchmark("Decode 10K rows (500-byte fields)") {
    let decoder = CSVDecoder()
    let result: [LongFieldRecord] = try decoder.decode(from: longField10KData)
    precondition(result.count == 10_000)
}

struct NumericRecord: Codable, Sendable {
    let intVal: Int
    let doubleVal: Double
    let floatVal: Float
}

benchmark("Decode 100K rows (numeric fields)") {
    let decoder = CSVDecoder()
    let result: [NumericRecord] = try decoder.decode(from: numeric100KData)
    precondition(result.count == 100_000)
}

// MARK: - Encoding Benchmarks

benchmark("Encode 1K rows") {
    let encoder = CSVEncoder()
    let result = try encoder.encode(simpleRecords1K)
    precondition(result.count > 0)
}

benchmark("Encode 10K rows") {
    let encoder = CSVEncoder()
    let result = try encoder.encode(simpleRecords10K)
    precondition(result.count > 0)
}

benchmark("Encode 100K rows") {
    let encoder = CSVEncoder()
    let result = try encoder.encode(simpleRecords100K)
    precondition(result.count > 0)
}

benchmark("Encode 1M rows") {
    let encoder = CSVEncoder()
    let result = try encoder.encode(simpleRecords1M)
    precondition(result.count > 0)
}

benchmark("Encode 10K rows (quoted fields)") {
    let encoder = CSVEncoder()
    let result = try encoder.encode(quotedRecords10K)
    precondition(result.count > 0)
}

benchmark("Encode 10K rows (500-byte fields)") {
    let encoder = CSVEncoder()
    let result = try encoder.encode(longFieldRecords10K)
    precondition(result.count > 0)
}

// MARK: - Key Strategy Benchmarks

let snakeCaseCSV1K: String = {
    var csv = "first_name,last_name,email_address\n"
    for i in 0..<1_000 {
        csv += "John\(i),Doe\(i),john\(i)@example.com\n"
    }
    return csv
}()
let snakeCaseCSV1KData = Data(snakeCaseCSV1K.utf8)

struct CamelCaseRecord: Codable, Sendable {
    let firstName: String
    let lastName: String
    let emailAddress: String
}

benchmark("Decode 1K rows with snake_case conversion") {
    let config = CSVDecoder.Configuration(keyDecodingStrategy: .convertFromSnakeCase)
    let decoder = CSVDecoder(configuration: config)
    let result: [CamelCaseRecord] = try decoder.decode(from: snakeCaseCSV1KData)
    precondition(result.count == 1_000)
}

// MARK: - Flexible Decoding Strategies

let flexibleDateCSV1K: String = {
    var csv = "id,date\n"
    let formats = ["2024-01-15", "15/01/2024", "01-15-2024", "2024-01-15T10:30:00Z"]
    for i in 0..<1_000 {
        csv += "\(i),\(formats[i % formats.count])\n"
    }
    return csv
}()
let flexibleDateCSV1KData = Data(flexibleDateCSV1K.utf8)

struct DateRecord: Codable, Sendable {
    let id: Int
    let date: Date
}

benchmark("Decode 1K rows with flexible date parsing") {
    let config = CSVDecoder.Configuration(dateDecodingStrategy: .flexible)
    let decoder = CSVDecoder(configuration: config)
    let result: [DateRecord] = try decoder.decode(from: flexibleDateCSV1KData)
    precondition(result.count == 1_000)
}

let flexibleNumberCSV1K: String = {
    var csv = "id,value\n"
    let formats = ["1,234.56", "1.234,56", "$1,234.56", "€1.234,56"]
    for i in 0..<1_000 {
        csv += "\(i),\"\(formats[i % formats.count])\"\n"
    }
    return csv
}()
let flexibleNumberCSV1KData = Data(flexibleNumberCSV1K.utf8)

struct FlexibleNumberRecord: Codable, Sendable {
    let id: Int
    let value: Double
}

benchmark("Decode 1K rows with flexible number parsing") {
    let config = CSVDecoder.Configuration(numberDecodingStrategy: .flexible)
    let decoder = CSVDecoder(configuration: config)
    let result: [FlexibleNumberRecord] = try decoder.decode(from: flexibleNumberCSV1KData)
    precondition(result.count == 1_000)
}

// MARK: - Encoding Output Format Comparison

benchmark("Encode 100K rows to Data") {
    let encoder = CSVEncoder()
    let result = try encoder.encode(simpleRecords100K)
    precondition(result.count > 0)
}

benchmark("Encode 100K rows to String") {
    let encoder = CSVEncoder()
    let result = try encoder.encodeToString(simpleRecords100K)
    precondition(result.count > 0)
}

// MARK: - Parallel vs Sequential Benchmarks

// Thread-safe box for storing async results
private final class ResultBox<T>: @unchecked Sendable {
    var value: Result<T, Error>?
}

// Helper to run async code synchronously for benchmarks
@inline(never)
nonisolated func runAsync<T: Sendable>(_ operation: @Sendable @escaping () async throws -> T) throws -> T {
    let box = ResultBox<T>()
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        do {
            let result = try await operation()
            box.value = .success(result)
        } catch {
            box.value = .failure(error)
        }
        semaphore.signal()
    }
    semaphore.wait()
    return try box.value!.get()
}

// Pre-generate temp file for parallel benchmarks
let parallelTempURL: URL = {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("parallel_benchmark.csv")
    try? Data(simple100K.utf8).write(to: url)
    return url
}()

// Sequential decode (parallelism: 1)
benchmark("Decode 100K rows (sequential, p=1)") {
    let count = try runAsync {
        let decoder = CSVDecoder()
        let config = CSVDecoder.ParallelConfiguration(parallelism: 1, chunkSize: 64 * 1024)
        let result = try await decoder.decodeParallel([SimpleRecord].self, from: simple100KData, parallelConfig: config)
        return result.count
    }
    precondition(count == 100_000)
}

// Parallel decode (all cores)
benchmark("Decode 100K rows (parallel, p=all)") {
    let count = try runAsync {
        let decoder = CSVDecoder()
        let config = CSVDecoder.ParallelConfiguration(chunkSize: 64 * 1024)
        let result = try await decoder.decodeParallel([SimpleRecord].self, from: simple100KData, parallelConfig: config)
        return result.count
    }
    precondition(count == 100_000)
}

// Sequential encode (parallelism: 1)
benchmark("Encode 100K rows (sequential, p=1)") {
    let count = try runAsync {
        let encoder = CSVEncoder()
        let config = CSVEncoder.ParallelEncodingConfiguration(parallelism: 1, chunkSize: 10_000)
        let result = try await encoder.encodeParallel(simpleRecords100K, parallelConfig: config)
        return result.count
    }
    precondition(count > 0)
}

// Parallel encode (all cores)
benchmark("Encode 100K rows (parallel, p=all)") {
    let count = try runAsync {
        let encoder = CSVEncoder()
        let config = CSVEncoder.ParallelEncodingConfiguration(chunkSize: 10_000)
        let result = try await encoder.encodeParallel(simpleRecords100K, parallelConfig: config)
        return result.count
    }
    precondition(count > 0)
}

// Parallel decode from file (memory-mapped)
benchmark("Decode 100K from file (parallel)") {
    let count = try runAsync {
        let decoder = CSVDecoder()
        let config = CSVDecoder.ParallelConfiguration(chunkSize: 64 * 1024)
        let result = try await decoder.decodeParallel([SimpleRecord].self, from: parallelTempURL, parallelConfig: config)
        return result.count
    }
    precondition(count == 100_000)
}

// Parallel encode to file
benchmark("Encode 100K to file (parallel)") {
    _ = try runAsync {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".csv")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let encoder = CSVEncoder()
        let config = CSVEncoder.ParallelEncodingConfiguration(chunkSize: 10_000)
        try await encoder.encodeParallel(simpleRecords100K, to: tempURL, parallelConfig: config)
        return true
    }
}

// MARK: - Raw CSVParser Benchmarks (No Codable Overhead)

benchmark("Raw Parse 1M rows (Iterate Only)") {
    simple1MData.withUnsafeBytes { buffer in
        let parser = CSVParser(buffer: buffer.bindMemory(to: UInt8.self), delimiter: 0x2C)
        var count = 0
        for _ in parser {
            count += 1
        }
        precondition(count == 1_000_001)
    }
}

benchmark("Raw Parse 1M rows (Iterate + String)") {
    simple1MData.withUnsafeBytes { buffer in
        let parser = CSVParser(buffer: buffer.bindMemory(to: UInt8.self), delimiter: 0x2C)
        for row in parser {
            _ = row.string(at: 0)
            _ = row.string(at: 1)
            _ = row.string(at: 2)
        }
    }
}

benchmark("Raw Parse 100K Quoted Rows (Iterate Only)") {
    quoted100KData.withUnsafeBytes { buffer in
        let parser = CSVParser(buffer: buffer.bindMemory(to: UInt8.self), delimiter: 0x2C)
        var count = 0
        for _ in parser {
            count += 1
        }
        precondition(count == 100_001)
    }
}

benchmark("Raw Parse 100K Quoted Rows (Iterate + String)") {
    quoted100KData.withUnsafeBytes { buffer in
        let parser = CSVParser(buffer: buffer.bindMemory(to: UInt8.self), delimiter: 0x2C)
        for row in parser {
            _ = row.string(at: 0)
            _ = row.string(at: 1) // "Item X" (quoted)
            _ = row.string(at: 2) // Description (quoted with internal quotes)
            _ = row.string(at: 3) // Int
        }
    }
}

print("Registering Raw Benchmarks completed.")

Benchmark.main()
