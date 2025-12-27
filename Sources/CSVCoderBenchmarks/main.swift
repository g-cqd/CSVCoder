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

Benchmark.main()
