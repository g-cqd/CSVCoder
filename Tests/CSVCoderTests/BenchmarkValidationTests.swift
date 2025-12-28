import Testing
import CSVCoder
import Foundation

/// Validation tests for benchmark code.
/// Ensures benchmark data generators and models work correctly.
@Suite("Benchmark Validation")
struct BenchmarkValidationTests {

    // MARK: - Test Data Models

    struct SimpleRecord: Codable, Sendable, Equatable {
        let name: String
        let age: Int
        let score: Double
    }

    struct ComplexRecord: Codable, Sendable, Equatable {
        let id: Int
        let firstName: String
        let lastName: String
        let email: String
        let age: Int
        let salary: Double
        let isActive: Bool
        let notes: String
    }

    struct QuotedRecord: Codable, Sendable, Equatable {
        let name: String
        let description: String
        let value: Int
    }

    struct Order: Codable, Sendable {
        let orderId: String
        let customerId: Int
        let customerName: String
        let email: String
        let productId: Int
        let productName: String
        let quantity: Int
        let unitPrice: Double
        let discount: Double?
        let taxRate: Double
        let shippingCost: Double
        let totalAmount: Double
        let currency: String
        let paymentMethod: String
        let orderDate: String
        let shipDate: String?
        let status: String
        let notes: String?
    }

    struct Transaction: Codable, Sendable {
        let transactionId: String
        let accountFrom: String
        let accountTo: String
        let amount: Double
        let currency: String
        let exchangeRate: Double?
        let fee: Double
        let timestamp: String
        let category: String
        let description: String
        let reference: String?
        let status: String
        let processedBy: String?
    }

    struct LogEntry: Codable, Sendable {
        let timestamp: String
        let level: String
        let service: String
        let host: String
        let requestId: String?
        let userId: String?
        let action: String
        let resource: String
        let duration: Int?
        let statusCode: Int?
        let message: String
        let metadata: String?
    }

    // MARK: - Generator Functions

    func generateSimpleCSV(rows: Int) -> String {
        var csv = "name,age,score\n"
        for i in 0..<rows {
            csv += "Person\(i),\(20 + i % 50),\(Double(i) * 0.1)\n"
        }
        return csv
    }

    func generateComplexCSV(rows: Int) -> String {
        var csv = "id,firstName,lastName,email,age,salary,isActive,notes\n"
        for i in 0..<rows {
            csv += "\(i),John,Doe\(i),john\(i)@example.com,\(25 + i % 40),\(50000.0 + Double(i) * 100),\(i % 2 == 0),\"Some notes here with text\"\n"
        }
        return csv
    }

    func generateQuotedCSV(rows: Int) -> String {
        var csv = "name,description,value\n"
        for i in 0..<rows {
            csv += "\"Item \(i)\",\"A description with, commas and \"\"quotes\"\"\",\(i * 10)\n"
        }
        return csv
    }

    // MARK: - Tests

    @Test("Simple CSV generation and parsing")
    func simpleCSVRoundtrip() throws {
        let csv = generateSimpleCSV(rows: 100)
        let data = Data(csv.utf8)

        let decoder = CSVDecoder()
        let records: [SimpleRecord] = try decoder.decode(from: data)

        #expect(records.count == 100)
        #expect(records[0].name == "Person0")
        #expect(records[0].age == 20)
        #expect(records[99].name == "Person99")
    }

    @Test("Complex CSV generation and parsing")
    func complexCSVRoundtrip() throws {
        let csv = generateComplexCSV(rows: 100)
        let data = Data(csv.utf8)

        let decoder = CSVDecoder()
        let records: [ComplexRecord] = try decoder.decode(from: data)

        #expect(records.count == 100)
        #expect(records[0].id == 0)
        #expect(records[0].firstName == "John")
        #expect(records[0].lastName == "Doe0")
        #expect(records[0].isActive == true)
        #expect(records[1].isActive == false)
    }

    @Test("Quoted CSV generation and parsing")
    func quotedCSVRoundtrip() throws {
        let csv = generateQuotedCSV(rows: 100)
        let data = Data(csv.utf8)

        let decoder = CSVDecoder()
        let records: [QuotedRecord] = try decoder.decode(from: data)

        #expect(records.count == 100)
        #expect(records[0].name == "Item 0")
        #expect(records[0].description.contains("commas"))
        #expect(records[0].description.contains("\"quotes\""))
    }

    @Test("Encoding roundtrip")
    func encodingRoundtrip() throws {
        let records = (0..<100).map { SimpleRecord(name: "Person\($0)", age: 20 + $0 % 50, score: Double($0) * 0.1) }

        let encoder = CSVEncoder()
        let data = try encoder.encode(records)

        let decoder = CSVDecoder()
        let decoded: [SimpleRecord] = try decoder.decode(from: data)

        #expect(decoded.count == records.count)
        for (original, roundtripped) in zip(records, decoded) {
            #expect(original == roundtripped)
        }
    }

    @Test("Raw parser validation")
    func rawParserValidation() throws {
        let csv = generateSimpleCSV(rows: 1000)
        let data = Data(csv.utf8)

        var rowCount = 0
        data.withUnsafeBytes { buffer in
            let parser = CSVParser(buffer: buffer.bindMemory(to: UInt8.self), delimiter: 0x2C)
            for row in parser {
                rowCount += 1
                // Verify we can extract strings
                if rowCount > 1 { // Skip header
                    let name = row.string(at: 0)
                    #expect(name != nil)
                    #expect(name?.hasPrefix("Person") == true)
                }
            }
        }

        #expect(rowCount == 1001) // 1000 data rows + 1 header
    }

    @Test("Parallel decoding validation")
    func parallelDecodingValidation() async throws {
        let csv = generateSimpleCSV(rows: 1000)
        let data = Data(csv.utf8)

        let decoder = CSVDecoder()
        let config = CSVDecoder.ParallelConfiguration(chunkSize: 1024)
        let records = try await decoder.decodeParallel([SimpleRecord].self, from: data, parallelConfig: config)

        #expect(records.count == 1000)
    }

    @Test("Parallel encoding validation")
    func parallelEncodingValidation() async throws {
        let records = (0..<1000).map { SimpleRecord(name: "Person\($0)", age: 20 + $0 % 50, score: Double($0) * 0.1) }

        let encoder = CSVEncoder()
        let config = CSVEncoder.ParallelEncodingConfiguration(chunkSize: 100)
        let data = try await encoder.encodeParallel(records, parallelConfig: config)

        #expect(data.count > 0)

        // Verify the output is valid CSV
        let decoder = CSVDecoder()
        let decoded: [SimpleRecord] = try decoder.decode(from: data)
        #expect(decoded.count == 1000)
    }

    @Test("Large dataset validation (10K rows)")
    func largeDatasetValidation() throws {
        let csv = generateSimpleCSV(rows: 10_000)
        let data = Data(csv.utf8)

        let decoder = CSVDecoder()
        let records: [SimpleRecord] = try decoder.decode(from: data)

        #expect(records.count == 10_000)
    }

    @Test("Wide CSV validation (50 columns)")
    func wideCSVValidation() throws {
        var csv = (0..<50).map { "col\($0)" }.joined(separator: ",") + "\n"
        for i in 0..<100 {
            csv += (0..<50).map { _ in "value\(i)" }.joined(separator: ",") + "\n"
        }
        let data = Data(csv.utf8)

        struct WideRecord: Codable {
            let col0: String
            let col1: String
            let col2: String
            let col3: String
            let col4: String
        }

        let decoder = CSVDecoder()
        let records: [WideRecord] = try decoder.decode(from: data)

        #expect(records.count == 100)
        #expect(records[0].col0 == "value0")
    }

    @Test("Long field validation (500 bytes)")
    func longFieldValidation() throws {
        let longValue = String(repeating: "x", count: 500)
        var csv = "id,data\n"
        for i in 0..<100 {
            csv += "\(i),\(longValue)\n"
        }
        let data = Data(csv.utf8)

        struct LongFieldRecord: Codable {
            let id: Int
            let data: String
        }

        let decoder = CSVDecoder()
        let records: [LongFieldRecord] = try decoder.decode(from: data)

        #expect(records.count == 100)
        #expect(records[0].data.count == 500)
    }

    @Test("Unicode content validation")
    func unicodeContentValidation() throws {
        let unicodeStrings = [
            "日本語テスト",
            "Ελληνικά",
            "한국어",
            "中文测试",
            "Émojis: 🚀🎉"
        ]

        var csv = "id,text\n"
        for (i, str) in unicodeStrings.enumerated() {
            csv += "\(i),\"\(str)\"\n"
        }
        let data = Data(csv.utf8)

        struct UnicodeRecord: Codable {
            let id: Int
            let text: String
        }

        let decoder = CSVDecoder()
        let records: [UnicodeRecord] = try decoder.decode(from: data)

        #expect(records.count == unicodeStrings.count)
        for (record, expected) in zip(records, unicodeStrings) {
            #expect(record.text == expected)
        }
    }

    @Test("Stress quoted content validation")
    func stressQuotedContentValidation() throws {
        var csv = "id,content\n"
        for i in 0..<10 {
            let content = "\"Field with \"\"nested quotes\"\", commas, and\nnewlines at row \(i)\""
            csv += "\(i),\(content)\n"
        }
        let data = Data(csv.utf8)

        struct StressQuotedRecord: Codable {
            let id: Int
            let content: String
        }

        let decoder = CSVDecoder()
        let records: [StressQuotedRecord] = try decoder.decode(from: data)

        #expect(records.count == 10)
        #expect(records[0].content.contains("nested quotes"))
        #expect(records[0].content.contains(","))
        #expect(records[0].content.contains("\n"))
    }
}
