import Benchmark
import CSVCoder
import CSVCoderTestFixtures
import Foundation

// MARK: - Print Hardware Info

HardwareInfo.current.printHeader()

// MARK: - SimpleRecord

struct SimpleRecord: Codable, Sendable {
    let name: String
    let age: Int
    let score: Double
}

// MARK: - ComplexRecord

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

// MARK: - QuotedRecord

struct QuotedRecord: Codable, Sendable {
    let name: String
    let description: String
    let value: Int
}

// MARK: - WideRecord

struct WideRecord: Codable, Sendable {
    let col0: String
    let col1: String
    let col2: String
    let col3: String
    let col4: String
}

// MARK: - LongFieldRecord

struct LongFieldRecord: Codable, Sendable {
    let id: Int
    let data: String
}

// MARK: - NumericRecord

struct NumericRecord: Codable, Sendable {
    let intVal: Int
    let doubleVal: Double
    let floatVal: Float
}

// MARK: - CamelCaseRecord

struct CamelCaseRecord: Codable, Sendable {
    let firstName: String
    let lastName: String
    let emailAddress: String
}

// MARK: - DateRecord

struct DateRecord: Codable, Sendable {
    let id: Int
    let date: Date
}

// MARK: - FlexibleNumberRecord

struct FlexibleNumberRecord: Codable, Sendable {
    let id: Int
    let value: Double
}

// Order, Transaction, and LogEntry are imported from CSVCoderTestFixtures

// MARK: - CSV Generators

nonisolated func generateSimpleCSV(rows: Int) -> String {
    var csv = "name,age,score\n"
    for i in 0 ..< rows {
        csv += "Person\(i),\(20 + i % 50),\(Double(i) * 0.1)\n"
    }
    return csv
}

nonisolated func generateComplexCSV(rows: Int) -> String {
    var csv = "id,firstName,lastName,email,age,salary,isActive,notes\n"
    for i in 0 ..< rows {
        csv +=
            "\(i),John,Doe\(i),john\(i)@example.com,\(25 + i % 40),\(50000.0 + Double(i) * 100),\(i % 2 == 0),\"Some notes here with text\"\n"
    }
    return csv
}

nonisolated func generateQuotedCSV(rows: Int) -> String {
    var csv = "name,description,value\n"
    for i in 0 ..< rows {
        csv += "\"Item \(i)\",\"A description with, commas and \"\"quotes\"\"\",\(i * 10)\n"
    }
    return csv
}

nonisolated func generateWideCSV(rows: Int, columns: Int) -> String {
    var csv = (0 ..< columns).map { "col\($0)" }.joined(separator: ",") + "\n"
    for i in 0 ..< rows {
        csv += (0 ..< columns).map { _ in "value\(i)" }.joined(separator: ",") + "\n"
    }
    return csv
}

nonisolated func generateLongFieldCSV(rows: Int, fieldLength: Int) -> String {
    let longValue = String(repeating: "x", count: fieldLength)
    var csv = "id,data\n"
    for i in 0 ..< rows {
        csv += "\(i),\(longValue)\n"
    }
    return csv
}

nonisolated func generateNumericCSV(rows: Int) -> String {
    var csv = "intVal,doubleVal,floatVal\n"
    for i in 0 ..< rows {
        csv += "\(i),\(Double(i) * 1.5),\(Float(i) * 0.5)\n"
    }
    return csv
}

nonisolated func generateOrderCSV(rows: Int) -> String {
    var csv =
        "orderId,customerId,customerName,email,productId,productName,quantity,unitPrice,discount,taxRate,shippingCost,totalAmount,currency,paymentMethod,orderDate,shipDate,status,notes\n"
    let statuses = ["pending", "processing", "shipped", "delivered", "cancelled"]
    let payments = ["credit_card", "paypal", "bank_transfer", "crypto"]
    for i in 0 ..< rows {
        let hasDiscount = i % 3 == 0
        let hasNotes = i % 5 == 0
        let hasShipDate = i % 2 == 0
        let orderId = "ORD-\(String(format: "%08d", i))"
        let customerId = "\(1000 + i % 500)"
        let customerName = "\"Customer \(i)\""
        let email = "customer\(i)@example.com"
        let productId = "\(i % 1000)"
        let productName = "\"Product \(i % 100)\""
        let quantity = "\(1 + i % 10)"
        let unitPrice = "\(Double(10 + i % 100))"
        let discount = hasDiscount ? "0.1" : ""
        let totalAmount = "\(Double(10 + i % 100) * Double(1 + i % 10))"
        let payment = payments[i % payments.count]
        let orderDate = "2024-\(String(format: "%02d", 1 + i % 12))-\(String(format: "%02d", 1 + i % 28))"
        let shipDate =
            hasShipDate
            ? "2024-\(String(format: "%02d", 1 + (i + 3) % 12))-\(String(format: "%02d", 1 + (i + 3) % 28))"
            : ""
        let status = statuses[i % statuses.count]
        let notes = hasNotes ? "\"Rush order, handle with care\"" : ""
        csv += "\(orderId),\(customerId),\(customerName),\(email),\(productId),\(productName),"
        csv += "\(quantity),\(unitPrice),\(discount),0.08,5.99,\(totalAmount),USD,\(payment),"
        csv += "\(orderDate),\(shipDate),\(status),\(notes)\n"
    }
    return csv
}

nonisolated func generateTransactionCSV(rows: Int) -> String {
    var csv =
        "transactionId,accountFrom,accountTo,amount,currency,exchangeRate,fee,timestamp,category,description,reference,status,processedBy\n"
    let categories = ["transfer", "payment", "refund", "withdrawal", "deposit"]
    let currencies = ["USD", "EUR", "GBP", "JPY", "CHF"]
    for i in 0 ..< rows {
        let hasExchange = i % 4 == 0
        let hasRef = i % 3 == 0
        let hasProcessor = i % 2 == 0
        let txnId = "TXN\(String(format: "%012d", i))"
        let accountFrom = "ACC\(String(format: "%08d", i % 10000))"
        let accountTo = "ACC\(String(format: "%08d", (i + 5000) % 10000))"
        let amount = "\(Double(100 + i % 10000))"
        let currency = currencies[i % currencies.count]
        let exchangeRate = hasExchange ? "1.12" : ""
        let fee = "\(Double(i % 50) * 0.01)"
        let month = String(format: "%02d", 1 + i % 12)
        let day = String(format: "%02d", 1 + i % 28)
        let hour = String(format: "%02d", i % 24)
        let minute = String(format: "%02d", i % 60)
        let timestamp = "2024-\(month)-\(day)T\(hour):\(minute):00Z"
        let category = categories[i % categories.count]
        let description = "\"Transaction \(i) description\""
        let reference = hasRef ? "REF\(i)" : ""
        let processor = hasProcessor ? "PROC\(i % 100)" : ""
        csv += "\(txnId),\(accountFrom),\(accountTo),\(amount),\(currency),\(exchangeRate),\(fee),"
        csv += "\(timestamp),\(category),\(description),\(reference),completed,\(processor)\n"
    }
    return csv
}

nonisolated func generateLogCSV(rows: Int) -> String {
    var csv = "timestamp,level,service,host,requestId,userId,action,resource,duration,statusCode,message,metadata\n"
    let levels = ["DEBUG", "INFO", "WARN", "ERROR"]
    let services = ["api-gateway", "auth-service", "user-service", "order-service", "payment-service"]
    let actions = ["GET", "POST", "PUT", "DELETE", "PATCH"]
    for i in 0 ..< rows {
        let hasRequestId = i % 2 == 0
        let hasUserId = i % 3 == 0
        let hasDuration = i % 2 == 0
        let hasMetadata = i % 5 == 0
        let month = String(format: "%02d", 1 + i % 12)
        let day = String(format: "%02d", 1 + i % 28)
        let hour = String(format: "%02d", i % 24)
        let minute = String(format: "%02d", i % 60)
        let second = String(format: "%02d", i % 60)
        let millis = String(format: "%03d", i % 1000)
        let timestamp = "2024-\(month)-\(day)T\(hour):\(minute):\(second).\(millis)Z"
        let level = levels[i % levels.count]
        let service = services[i % services.count]
        let host = "host-\(i % 10).cluster.local"
        let requestId = hasRequestId ? "req-\(UUID().uuidString.prefix(8))" : ""
        let userId = hasUserId ? "user-\(i % 1000)" : ""
        let action = actions[i % actions.count]
        let resource = "/api/v1/resource/\(i % 100)"
        let duration = hasDuration ? "\(50 + i % 500)" : ""
        let statusCode = "\(200 + (i % 5) * 100)"
        let message = "\"Request processed successfully for item \(i)\""
        let metadata = hasMetadata ? "\"{\"\"key\"\":\"\"value\"\"}\"" : ""
        csv += "\(timestamp),\(level),\(service),\(host),\(requestId),\(userId),"
        csv += "\(action),\(resource),\(duration),\(statusCode),\(message),\(metadata)\n"
    }
    return csv
}

// Stress test: deeply quoted and escaped content
nonisolated func generateStressQuotedCSV(rows: Int) -> String {
    var csv = "id,content\n"
    for i in 0 ..< rows {
        // Create content with multiple levels of quotes, commas, and newlines
        let content = "\"Field with \"\"nested quotes\"\", commas, and\nnewlines at row \(i)\""
        csv += "\(i),\(content)\n"
    }
    return csv
}

// Stress test: Unicode-heavy content
nonisolated func generateUnicodeCSV(rows: Int) -> String {
    let unicodeStrings = [
        "日本語テスト",
        "Ελληνικά",
        "العربية",
        "עברית",
        "한국어",
        "中文测试",
        "Émojis: 🚀🎉💻🔥",
        "Ñoño español",
    ]
    var csv = "id,text,category\n"
    for i in 0 ..< rows {
        csv += "\(i),\"\(unicodeStrings[i % unicodeStrings.count]) - item \(i)\",cat\(i % 10)\n"
    }
    return csv
}

// MARK: - Pre-generated Datasets

// Simple datasets
let simple1K = generateSimpleCSV(rows: 1000)
let simple1KData = Data(simple1K.utf8)

let simple10K = generateSimpleCSV(rows: 10000)
let simple10KData = Data(simple10K.utf8)

let simple100K = generateSimpleCSV(rows: 100_000)
let simple100KData = Data(simple100K.utf8)

let simple1M = generateSimpleCSV(rows: 1_000_000)
let simple1MData = Data(simple1M.utf8)

// Complex dataset (10K rows, 8 fields each)
let complex10K = generateComplexCSV(rows: 10000)
let complex10KData = Data(complex10K.utf8)

let complex100K = generateComplexCSV(rows: 100_000)
let complex100KData = Data(complex100K.utf8)

// Quoted datasets
let quoted10K = generateQuotedCSV(rows: 10000)
let quoted10KData = Data(quoted10K.utf8)

let quoted100K = generateQuotedCSV(rows: 100_000)
let quoted100KData = Data(quoted100K.utf8)

// Wide dataset (10K rows, 50 columns)
let wide50Col10K = generateWideCSV(rows: 10000, columns: 50)
let wide50Col10KData = Data(wide50Col10K.utf8)

// Long field dataset (10K rows, 500-byte fields)
let longField10K = generateLongFieldCSV(rows: 10000, fieldLength: 500)
let longField10KData = Data(longField10K.utf8)

// Numeric dataset
let numeric100K = generateNumericCSV(rows: 100_000)
let numeric100KData = Data(numeric100K.utf8)

// Real-world datasets
let orders50K = generateOrderCSV(rows: 50000)
let orders50KData = Data(orders50K.utf8)

let transactions100K = generateTransactionCSV(rows: 100_000)
let transactions100KData = Data(transactions100K.utf8)

let logs100K = generateLogCSV(rows: 100_000)
let logs100KData = Data(logs100K.utf8)

// Stress test datasets
let stressQuoted10K = generateStressQuotedCSV(rows: 10000)
let stressQuoted10KData = Data(stressQuoted10K.utf8)

let unicode50K = generateUnicodeCSV(rows: 50000)
let unicode50KData = Data(unicode50K.utf8)

// Very large field dataset (1K rows, 10KB fields)
let veryLongField1K = generateLongFieldCSV(rows: 1000, fieldLength: 10000)
let veryLongField1KData = Data(veryLongField1K.utf8)

// Very wide dataset (1K rows, 200 columns)
let veryWide200Col1K = generateWideCSV(rows: 1000, columns: 200)
let veryWide200Col1KData = Data(veryWide200Col1K.utf8)

// Pre-generated records for encoding benchmarks
let simpleRecords1K = (0 ..< 1000).map { SimpleRecord(name: "Person\($0)", age: 20 + $0 % 50, score: Double($0) * 0.1) }
let simpleRecords10K = (0 ..< 10000)
    .map { SimpleRecord(name: "Person\($0)", age: 20 + $0 % 50, score: Double($0) * 0.1) }
let simpleRecords100K = (0 ..< 100_000).map {
    SimpleRecord(
        name: "Person\($0)",
        age: 20 + $0 % 50,
        score: Double($0) * 0.1,
    )
}

let simpleRecords1M = (0 ..< 1_000_000).map {
    SimpleRecord(
        name: "Person\($0)",
        age: 20 + $0 % 50,
        score: Double($0) * 0.1,
    )
}

let quotedRecords10K = (0 ..< 10000).map { i in
    QuotedRecord(name: "Item \(i)", description: "A \"description\" with, commas", value: i * 10)
}

let longFieldRecords10K = (0 ..< 10000).map { LongFieldRecord(id: $0, data: String(repeating: "x", count: 500)) }

let orderRecords50K = (0 ..< 50000).map { i in
    Order(
        orderId: "ORD-\(String(format: "%08d", i))",
        customerId: 1000 + i % 500,
        customerName: "Customer \(i)",
        email: "customer\(i)@example.com",
        productId: i % 1000,
        productName: "Product \(i % 100)",
        quantity: 1 + i % 10,
        unitPrice: Double(10 + i % 100),
        discount: i % 3 == 0 ? 0.1 : nil,
        taxRate: 0.08,
        shippingCost: 5.99,
        totalAmount: Double(10 + i % 100) * Double(1 + i % 10),
        currency: "USD",
        paymentMethod: ["credit_card", "paypal", "bank_transfer", "crypto"][i % 4],
        orderDate: "2024-01-15",
        shipDate: i % 2 == 0 ? "2024-01-18" : nil,
        status: ["pending", "processing", "shipped", "delivered", "cancelled"][i % 5],
        notes: i % 5 == 0 ? "Rush order" : nil,
    )
}

// Strategy test datasets
let snakeCaseCSV1K: String = {
    var csv = "first_name,last_name,email_address\n"
    for i in 0 ..< 1000 {
        csv += "John\(i),Doe\(i),john\(i)@example.com\n"
    }
    return csv
}()

let snakeCaseCSV1KData = Data(snakeCaseCSV1K.utf8)

let flexibleDateCSV1K: String = {
    var csv = "id,date\n"
    let formats = ["2024-01-15", "15/01/2024", "01-15-2024", "2024-01-15T10:30:00Z"]
    for i in 0 ..< 1000 {
        csv += "\(i),\(formats[i % formats.count])\n"
    }
    return csv
}()

let flexibleDateCSV1KData = Data(flexibleDateCSV1K.utf8)

let flexibleNumberCSV1K: String = {
    var csv = "id,value\n"
    let formats = ["1,234.56", "1.234,56", "$1,234.56", "€1.234,56"]
    for i in 0 ..< 1000 {
        csv += "\(i),\"\(formats[i % formats.count])\"\n"
    }
    return csv
}()

let flexibleNumberCSV1KData = Data(flexibleNumberCSV1K.utf8)

// Pre-generate temp file for parallel benchmarks
let parallelTempURL: URL = {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("parallel_benchmark.csv")
    try? simple100KData.write(to: url)
    return url
}()

// MARK: - ResultBox

private final class ResultBox<T>: @unchecked Sendable {
    var value: Result<T, Error>?
}

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
    guard let result = box.value else {
        fatalError("Async operation completed without setting result")
    }
    return try result.get()
}

// MARK: - Raw Parser Benchmarks

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
            _ = row.string(at: 1)
            _ = row.string(at: 2)
            _ = row.string(at: 3)
        }
    }
}

// MARK: - Basic Decoding Benchmarks

benchmark("Decode 1K rows (simple)") {
    let decoder = CSVDecoder()
    let result: [SimpleRecord] = try decoder.decode(from: simple1KData)
    precondition(result.count == 1000)
}

benchmark("Decode 10K rows (simple)") {
    let decoder = CSVDecoder()
    let result: [SimpleRecord] = try decoder.decode(from: simple10KData)
    precondition(result.count == 10000)
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
    precondition(result.count == 10000)
}

benchmark("Decode 100K rows (complex, 8 fields)") {
    let decoder = CSVDecoder()
    let result: [ComplexRecord] = try decoder.decode(from: complex100KData)
    precondition(result.count == 100_000)
}

benchmark("Decode 10K rows (quoted fields)") {
    let decoder = CSVDecoder()
    let result: [QuotedRecord] = try decoder.decode(from: quoted10KData)
    precondition(result.count == 10000)
}

benchmark("Decode 10K rows (50 columns wide)") {
    let decoder = CSVDecoder()
    let result: [WideRecord] = try decoder.decode(from: wide50Col10KData)
    precondition(result.count == 10000)
}

benchmark("Decode 10K rows (500-byte fields)") {
    let decoder = CSVDecoder()
    let result: [LongFieldRecord] = try decoder.decode(from: longField10KData)
    precondition(result.count == 10000)
}

benchmark("Decode 100K rows (numeric fields)") {
    let decoder = CSVDecoder()
    let result: [NumericRecord] = try decoder.decode(from: numeric100KData)
    precondition(result.count == 100_000)
}

// MARK: - Real-World Decoding Benchmarks

benchmark("Decode 50K orders (18 fields, optionals)") {
    let decoder = CSVDecoder()
    let result: [Order] = try decoder.decode(from: orders50KData)
    precondition(result.count == 50000)
}

benchmark("Decode 100K transactions (13 fields)") {
    let decoder = CSVDecoder()
    let result: [Transaction] = try decoder.decode(from: transactions100KData)
    precondition(result.count == 100_000)
}

benchmark("Decode 100K log entries (12 fields)") {
    let decoder = CSVDecoder()
    let result: [LogEntry] = try decoder.decode(from: logs100KData)
    precondition(result.count == 100_000)
}

// MARK: - StressQuotedRecord

struct StressQuotedRecord: Codable, Sendable {
    let id: Int
    let content: String
}

// MARK: - UnicodeRecord

struct UnicodeRecord: Codable, Sendable {
    let id: Int
    let text: String
    let category: String
}

benchmark("Decode 10K stress-quoted (nested quotes, newlines)") {
    let decoder = CSVDecoder()
    let result: [StressQuotedRecord] = try decoder.decode(from: stressQuoted10KData)
    precondition(result.count == 10000)
}

benchmark("Decode 50K Unicode-heavy rows") {
    let decoder = CSVDecoder()
    let result: [UnicodeRecord] = try decoder.decode(from: unicode50KData)
    precondition(result.count == 50000)
}

benchmark("Decode 1K rows (10KB fields)") {
    let decoder = CSVDecoder()
    let result: [LongFieldRecord] = try decoder.decode(from: veryLongField1KData)
    precondition(result.count == 1000)
}

// MARK: - VeryWideRecord

struct VeryWideRecord: Codable, Sendable {
    let col0: String, col1: String, col2: String, col3: String, col4: String
}

benchmark("Decode 1K rows (200 columns wide)") {
    let decoder = CSVDecoder()
    let result: [VeryWideRecord] = try decoder.decode(from: veryWide200Col1KData)
    precondition(result.count == 1000)
}

// MARK: - Basic Encoding Benchmarks

benchmark("Encode 1K rows") {
    let encoder = CSVEncoder()
    let result = try encoder.encode(simpleRecords1K)
    precondition(!result.isEmpty)
}

benchmark("Encode 10K rows") {
    let encoder = CSVEncoder()
    let result = try encoder.encode(simpleRecords10K)
    precondition(!result.isEmpty)
}

benchmark("Encode 100K rows") {
    let encoder = CSVEncoder()
    let result = try encoder.encode(simpleRecords100K)
    precondition(!result.isEmpty)
}

benchmark("Encode 1M rows") {
    let encoder = CSVEncoder()
    let result = try encoder.encode(simpleRecords1M)
    precondition(!result.isEmpty)
}

benchmark("Encode 10K rows (quoted fields)") {
    let encoder = CSVEncoder()
    let result = try encoder.encode(quotedRecords10K)
    precondition(!result.isEmpty)
}

benchmark("Encode 10K rows (500-byte fields)") {
    let encoder = CSVEncoder()
    let result = try encoder.encode(longFieldRecords10K)
    precondition(!result.isEmpty)
}

// MARK: - Real-World Encoding Benchmarks

benchmark("Encode 50K orders (18 fields, optionals)") {
    let encoder = CSVEncoder()
    let result = try encoder.encode(orderRecords50K)
    precondition(!result.isEmpty)
}

// MARK: - Encoding Output Format Comparison

benchmark("Encode 100K rows to Data") {
    let encoder = CSVEncoder()
    let result = try encoder.encode(simpleRecords100K)
    precondition(!result.isEmpty)
}

benchmark("Encode 100K rows to String") {
    let encoder = CSVEncoder()
    let result = try encoder.encodeToString(simpleRecords100K)
    precondition(!result.isEmpty)
}

// MARK: - Strategy Benchmarks

benchmark("Decode 1K rows with snake_case conversion") {
    let config = CSVDecoder.Configuration(keyDecodingStrategy: .convertFromSnakeCase)
    let decoder = CSVDecoder(configuration: config)
    let result: [CamelCaseRecord] = try decoder.decode(from: snakeCaseCSV1KData)
    precondition(result.count == 1000)
}

benchmark("Decode 1K rows with flexible date parsing") {
    let config = CSVDecoder.Configuration(dateDecodingStrategy: .flexible)
    let decoder = CSVDecoder(configuration: config)
    let result: [DateRecord] = try decoder.decode(from: flexibleDateCSV1KData)
    precondition(result.count == 1000)
}

benchmark("Decode 1K rows with flexible number parsing") {
    let config = CSVDecoder.Configuration(numberDecodingStrategy: .flexible)
    let decoder = CSVDecoder(configuration: config)
    let result: [FlexibleNumberRecord] = try decoder.decode(from: flexibleNumberCSV1KData)
    precondition(result.count == 1000)
}

// MARK: - Parallel Processing Benchmarks

benchmark("Decode 100K rows (sequential, p=1)") {
    let count = try runAsync {
        let decoder = CSVDecoder()
        let config = CSVDecoder.ParallelConfiguration(parallelism: 1, chunkSize: 64 * 1024)
        let result = try await decoder.decodeParallel([SimpleRecord].self, from: simple100KData, parallelConfig: config)
        return result.count
    }
    precondition(count == 100_000)
}

benchmark("Decode 100K rows (parallel, p=all)") {
    let count = try runAsync {
        let decoder = CSVDecoder()
        let config = CSVDecoder.ParallelConfiguration(chunkSize: 64 * 1024)
        let result = try await decoder.decodeParallel([SimpleRecord].self, from: simple100KData, parallelConfig: config)
        return result.count
    }
    precondition(count == 100_000)
}

benchmark("Decode 1M rows (parallel, p=all)") {
    let count = try runAsync {
        let decoder = CSVDecoder()
        let config = CSVDecoder.ParallelConfiguration(chunkSize: 256 * 1024)
        let result = try await decoder.decodeParallel([SimpleRecord].self, from: simple1MData, parallelConfig: config)
        return result.count
    }
    precondition(count == 1_000_000)
}

benchmark("Encode 100K rows (sequential, p=1)") {
    let count = try runAsync {
        let encoder = CSVEncoder()
        let config = CSVEncoder.ParallelEncodingConfiguration(parallelism: 1, chunkSize: 10000)
        let result = try await encoder.encodeParallel(simpleRecords100K, parallelConfig: config)
        return result.count
    }
    precondition(count > 0)
}

benchmark("Encode 100K rows (parallel, p=all)") {
    let count = try runAsync {
        let encoder = CSVEncoder()
        let config = CSVEncoder.ParallelEncodingConfiguration(chunkSize: 10000)
        let result = try await encoder.encodeParallel(simpleRecords100K, parallelConfig: config)
        return result.count
    }
    precondition(count > 0)
}

benchmark("Encode 1M rows (parallel, p=all)") {
    let count = try runAsync {
        let encoder = CSVEncoder()
        let config = CSVEncoder.ParallelEncodingConfiguration(chunkSize: 50000)
        let result = try await encoder.encodeParallel(simpleRecords1M, parallelConfig: config)
        return result.count
    }
    precondition(count > 0)
}

benchmark("Decode 100K from file (parallel)") {
    let count = try runAsync {
        let decoder = CSVDecoder()
        let config = CSVDecoder.ParallelConfiguration(chunkSize: 64 * 1024)
        let result = try await decoder.decodeParallel(
            [SimpleRecord].self,
            from: parallelTempURL,
            parallelConfig: config,
        )
        return result.count
    }
    precondition(count == 100_000)
}

benchmark("Encode 100K to file (parallel)") {
    _ = try runAsync {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".csv")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let encoder = CSVEncoder()
        let config = CSVEncoder.ParallelEncodingConfiguration(chunkSize: 10000)
        try await encoder.encodeParallel(simpleRecords100K, to: tempURL, parallelConfig: config)
        return true
    }
}

// MARK: - Mixed Workload Benchmarks (Real-World Simulation)

benchmark("Mixed: Decode + Transform + Encode 10K") {
    let decoder = CSVDecoder()
    let encoder = CSVEncoder()
    let records: [SimpleRecord] = try decoder.decode(from: simple10KData)
    let transformed = records.map { SimpleRecord(name: $0.name.uppercased(), age: $0.age + 1, score: $0.score * 1.1) }
    let result = try encoder.encode(transformed)
    precondition(!result.isEmpty)
}

benchmark("Mixed: Filter + Aggregate 100K orders") {
    let decoder = CSVDecoder()
    let orders: [Order] = try decoder.decode(from: orders50KData)
    let filteredOrders = orders.filter { $0.status == "delivered" }
    let totalRevenue = filteredOrders.reduce(0.0) { $0 + $1.totalAmount }
    precondition(totalRevenue > 0)
}

// MARK: - Entry Point

Benchmark.main()
