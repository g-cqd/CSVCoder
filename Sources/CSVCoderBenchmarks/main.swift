import Benchmark
import CSVCoder
import Foundation

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

// MARK: - Benchmarks

// Small dataset (100 rows)
let small100 = generateSimpleCSV(rows: 100)
let small100Data = small100.data(using: .utf8)!

// Medium dataset (1,000 rows)
let medium1K = generateSimpleCSV(rows: 1_000)
let medium1KData = medium1K.data(using: .utf8)!

// Large dataset (10,000 rows)
let large10K = generateSimpleCSV(rows: 10_000)
let large10KData = large10K.data(using: .utf8)!

// Very large dataset (100,000 rows)
let huge100K = generateSimpleCSV(rows: 100_000)
let huge100KData = huge100K.data(using: .utf8)!

// Complex dataset (1,000 rows)
let complex1K = generateComplexCSV(rows: 1_000)
let complex1KData = complex1K.data(using: .utf8)!

// Quoted dataset (1,000 rows)
let quoted1K = generateQuotedCSV(rows: 1_000)

benchmark("Decode 100 rows (simple)") {
    let decoder = CSVDecoder()
    _ = try! decoder.decode([SimpleRecord].self, from: small100)
}

benchmark("Decode 1K rows (simple)") {
    let decoder = CSVDecoder()
    _ = try! decoder.decode([SimpleRecord].self, from: medium1K)
}

benchmark("Decode 10K rows (simple)") {
    let decoder = CSVDecoder()
    _ = try! decoder.decode([SimpleRecord].self, from: large10K)
}

benchmark("Decode 100K rows (simple)") {
    let decoder = CSVDecoder()
    _ = try! decoder.decode([SimpleRecord].self, from: huge100K)
}

benchmark("Decode 1K rows (complex)") {
    let decoder = CSVDecoder()
    _ = try! decoder.decode([ComplexRecord].self, from: complex1K)
}

struct QuotedRecord: Codable {
    let name: String
    let description: String
    let value: Int
}

benchmark("Decode 1K rows (quoted fields)") {
    let decoder = CSVDecoder()
    _ = try! decoder.decode([QuotedRecord].self, from: quoted1K)
}

benchmark("Encode 100 rows") {
    let records = (0..<100).map { SimpleRecord(name: "Person\($0)", age: 20 + $0 % 50, score: Double($0) * 0.1) }
    let encoder = CSVEncoder()
    _ = try! encoder.encodeToString(records)
}

benchmark("Encode 1K rows") {
    let records = (0..<1_000).map { SimpleRecord(name: "Person\($0)", age: 20 + $0 % 50, score: Double($0) * 0.1) }
    let encoder = CSVEncoder()
    _ = try! encoder.encodeToString(records)
}

benchmark("Encode 10K rows") {
    let records = (0..<10_000).map { SimpleRecord(name: "Person\($0)", age: 20 + $0 % 50, score: Double($0) * 0.1) }
    let encoder = CSVEncoder()
    _ = try! encoder.encodeToString(records)
}

benchmark("Encode 100K rows") {
    let records = (0..<100_000).map { SimpleRecord(name: "Person\($0)", age: 20 + $0 % 50, score: Double($0) * 0.1) }
    let encoder = CSVEncoder()
    _ = try! encoder.encodeToString(records)
}

// Key decoding strategy benchmarks
let snakeCaseCSV = """
first_name,last_name,email_address
John,Doe,john@example.com
Jane,Smith,jane@example.com
"""

struct CamelCaseRecord: Codable {
    let firstName: String
    let lastName: String
    let emailAddress: String
}

benchmark("Decode with snake_case conversion") {
    let config = CSVDecoder.Configuration(keyDecodingStrategy: .convertFromSnakeCase)
    let decoder = CSVDecoder(configuration: config)
    _ = try! decoder.decode([CamelCaseRecord].self, from: snakeCaseCSV)
}

benchmark("Decode with default keys") {
    let decoder = CSVDecoder()
    _ = try! decoder.decode([SimpleRecord].self, from: small100)
}

// MARK: - Zero-Copy / Byte-Based Benchmarks

benchmark("Decode 100K rows from Data (zero-copy)") {
    let decoder = CSVDecoder()
    let result: [SimpleRecord] = try! decoder.decode(from: huge100KData)
    precondition(result.count > 0)
}

benchmark("Decode 1K rows complex from Data (zero-copy)") {
    let decoder = CSVDecoder()
    let result: [ComplexRecord] = try! decoder.decode(from: complex1KData)
    precondition(result.count > 0)
}

// MARK: - Wide Row Benchmarks (SIMD benefits)

nonisolated func generateWideCSV(rows: Int, columns: Int) -> String {
    var csv = (0..<columns).map { "col\($0)" }.joined(separator: ",") + "\n"
    for i in 0..<rows {
        csv += (0..<columns).map { _ in "value\(i)" }.joined(separator: ",") + "\n"
    }
    return csv
}

let wide50Col1K = generateWideCSV(rows: 1_000, columns: 50)
let wide50Col1KData = wide50Col1K.data(using: .utf8)!

struct WideRecord: Codable {
    // We can't easily define 50 properties, so use subscript access for testing
    let col0: String
    let col1: String
    let col2: String
    let col3: String
    let col4: String
}

benchmark("Decode 1K rows (50 columns wide)") {
    let decoder = CSVDecoder()
    let result: [WideRecord] = try! decoder.decode(from: wide50Col1KData)
    precondition(result.count > 0)
}

// MARK: - Long Field Benchmarks (SIMD quote detection benefits)

nonisolated func generateLongFieldCSV(rows: Int, fieldLength: Int) -> String {
    let longValue = String(repeating: "x", count: fieldLength)
    var csv = "id,data\n"
    for i in 0..<rows {
        csv += "\(i),\(longValue)\n"
    }
    return csv
}

let longField1K = generateLongFieldCSV(rows: 1_000, fieldLength: 200)
let longField1KData = longField1K.data(using: .utf8)!

struct LongFieldRecord: Codable {
    let id: Int
    let data: String
}

benchmark("Decode 1K rows (200-byte fields)") {
    let decoder = CSVDecoder()
    let result: [LongFieldRecord] = try! decoder.decode(from: longField1KData)
    precondition(result.count > 0)
}

benchmark("Encode 1K rows (200-byte fields)") {
    let records = (0..<1_000).map { LongFieldRecord(id: $0, data: String(repeating: "x", count: 200)) }
    let encoder = CSVEncoder()
    _ = try! encoder.encodeToString(records)
}

// MARK: - Numeric Parsing Benchmarks

nonisolated func generateNumericCSV(rows: Int) -> String {
    var csv = "intVal,doubleVal,floatVal\n"
    for i in 0..<rows {
        csv += "\(i),\(Double(i) * 1.5),\(Float(i) * 0.5)\n"
    }
    return csv
}

let numeric10K = generateNumericCSV(rows: 10_000)
let numeric10KData = numeric10K.data(using: .utf8)!

struct NumericRecord: Codable {
    let intVal: Int
    let doubleVal: Double
    let floatVal: Float
}

benchmark("Decode 10K rows (numeric fields)") {
    let decoder = CSVDecoder()
    let result: [NumericRecord] = try! decoder.decode(from: numeric10KData)
    precondition(result.count > 0)
}

// MARK: - Encoding to Bytes vs String

benchmark("Encode 10K rows to Data") {
    let records = (0..<10_000).map { SimpleRecord(name: "Person\($0)", age: 20 + $0 % 50, score: Double($0) * 0.1) }
    let encoder = CSVEncoder()
    _ = try! encoder.encode(records)
}

benchmark("Encode 10K rows to String") {
    let records = (0..<10_000).map { SimpleRecord(name: "Person\($0)", age: 20 + $0 % 50, score: Double($0) * 0.1) }
    let encoder = CSVEncoder()
    _ = try! encoder.encodeToString(records)
}

// MARK: - Quoted Field Encoding

benchmark("Encode 1K rows (quoted fields)") {
    let records = (0..<1_000).map { i in
        QuotedRecord(name: "Item \(i)", description: "A \"description\" with, commas", value: i * 10)
    }
    let encoder = CSVEncoder()
    _ = try! encoder.encodeToString(records)
}

// MARK: - Flexible Decoding Strategies

let flexibleDateCSV = """
id,date
1,2024-01-15
2,15/01/2024
3,01-15-2024
4,2024-01-15T10:30:00Z
"""

struct DateRecord: Codable {
    let id: Int
    let date: Date
}

benchmark("Decode with flexible date parsing") {
    let config = CSVDecoder.Configuration(dateDecodingStrategy: .flexible)
    let decoder = CSVDecoder(configuration: config)
    _ = try! decoder.decode([DateRecord].self, from: flexibleDateCSV)
}

let flexibleNumberCSV = """
id,value
1,"1,234.56"
2,"1.234,56"
3,"$1,234.56"
4,"€1.234,56"
"""

struct FlexibleNumberRecord: Codable {
    let id: Int
    let value: Double
}

benchmark("Decode with flexible number parsing") {
    let config = CSVDecoder.Configuration(numberDecodingStrategy: .flexible)
    let decoder = CSVDecoder(configuration: config)
    _ = try! decoder.decode([FlexibleNumberRecord].self, from: flexibleNumberCSV)
}

Benchmark.main()
