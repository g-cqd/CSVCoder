# CSVCoder

A Swift CSV encoder/decoder using the `Codable` protocol, similar to `JSONEncoder`/`JSONDecoder`.

## Features

- **Type-safe CSV encoding/decoding** via Swift's `Codable` protocol
- **Zero-boilerplate macros** (`@CSVIndexed`, `@CSVColumn`) for headerless CSV
- **Streaming encoding/decoding** for O(1) memory with large files
- **Parallel encoding/decoding** for multi-core performance
- **Smart error suggestions** with typo detection and strategy hints
- **Configurable delimiters** (comma, semicolon, tab, etc.)
- **Multiple date encoding strategies** (ISO 8601, Unix timestamp, custom format)
- **Flexible decoding strategies** for dates, numbers, and booleans with auto-detection
- **Key decoding strategies** (snake_case, kebab-case, PascalCase conversion)
- **Index-based decoding** for headerless CSV files
- **CSVIndexedDecodable** for automatic column ordering via CodingKeys
- **Rich error diagnostics** with row/column location information
- **Optional value handling** with configurable nil encoding
- **SIMD-accelerated** parsing and field scanning
- **Thread-safe** with `Sendable` conformance
- **Swift 6.2 Approachable Concurrency** compatible with `nonisolated` types

## Requirements

- iOS 18.0+ / macOS 15.0+
- Swift 6.2+

## Installation

### Swift Package Manager

Add CSVCoder to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/g-cqd/CSVCoder.git", from: "1.0.0")
]
```

Or in Xcode: File → Add Package Dependencies → Enter the repository URL.

## Usage

### Encoding

```swift
import CSVCoder

struct Person: Codable {
    let name: String
    let age: Int
    let email: String?
}

let people = [
    Person(name: "Alice", age: 30, email: "alice@example.com"),
    Person(name: "Bob", age: 25, email: nil)
]

let encoder = CSVEncoder()
let csvString = try encoder.encodeToString(people)
// Output:
// name,age,email
// Alice,30,alice@example.com
// Bob,25,
```

### Decoding

```swift
import CSVCoder

let csvData = """
name,age,email
Alice,30,alice@example.com
Bob,25,
""".data(using: .utf8)!

let decoder = CSVDecoder()
let people = try decoder.decode([Person].self, from: csvData)
```

### Configuration

```swift
let config = CSVEncoder.Configuration(
    delimiter: ";",                           // Use semicolon
    includeHeaders: true,                     // Include header row
    dateEncodingStrategy: .iso8601,           // ISO 8601 dates
    nilEncodingStrategy: .emptyString,        // Empty string for nil
    lineEnding: .crlf                         // Windows line endings
)

let encoder = CSVEncoder(configuration: config)
```

### Date Encoding Strategies

- `.iso8601` - ISO 8601 format (default)
- `.secondsSince1970` - Unix timestamp in seconds
- `.millisecondsSince1970` - Unix timestamp in milliseconds
- `.formatted(String)` - Custom date format string
- `.custom((Date) throws -> String)` - Custom closure

### Single Row Encoding

```swift
let person = Person(name: "Alice", age: 30, email: "alice@example.com")
let row = try encoder.encodeRow(person)
// Output: Alice,30,alice@example.com
```

### Streaming Encoding

Encode large datasets with O(1) memory usage:

```swift
// Stream encode to file
try await encoder.encode(asyncSequence, to: fileURL)

// Stream encode array to file
try await encoder.encode(largeArray, to: fileURL)

// Encode to async stream of rows
for try await row in encoder.encodeToStream(asyncSequence) {
    sendToNetwork(row)
}
```

### Parallel Encoding

Utilize multiple cores for faster encoding:

```swift
// Parallel encode to file
try await encoder.encodeParallel(records, to: fileURL,
    parallelConfig: .init(parallelism: 8))

// Parallel encode to Data
let data = try await encoder.encodeParallel(records)

// Batched parallel for progress reporting
for try await batch in encoder.encodeParallelBatched(records,
    parallelConfig: .init(chunkSize: 10_000)) {
    print("Encoded \(batch.count) rows")
}
```

## Advanced Decoding

### Key Decoding Strategies

Automatically convert CSV header names to Swift property names:

```swift
struct User: Codable {
    let firstName: String
    let lastName: String
    let emailAddress: String
}

let csv = """
first_name,last_name,email_address
John,Doe,john@example.com
"""

// snake_case headers → camelCase properties
let config = CSVDecoder.Configuration(
    keyDecodingStrategy: .convertFromSnakeCase
)
let decoder = CSVDecoder(configuration: config)
let users = try decoder.decode([User].self, from: csv)
```

Available strategies:
- `.useDefaultKeys` - Use headers as-is (default)
- `.convertFromSnakeCase` - `first_name` → `firstName`
- `.convertFromKebabCase` - `first-name` → `firstName`
- `.convertFromScreamingSnakeCase` - `FIRST_NAME` → `firstName`
- `.convertFromPascalCase` - `FirstName` → `firstName`
- `.custom((String) -> String)` - Custom transformation

### Column Mapping

Map specific CSV headers to property names:

```swift
struct Product: Codable {
    let id: Int
    let name: String
    let price: Double
}

let csv = """
product_id,product_name,unit_price
1,Widget,9.99
"""

let config = CSVDecoder.Configuration(
    columnMapping: [
        "product_id": "id",
        "product_name": "name",
        "unit_price": "price"
    ]
)
```

### Index-Based Decoding

Decode headerless CSV files by column index:

```swift
let csv = """
Alice,30,95.5
Bob,25,88.0
"""

let config = CSVDecoder.Configuration(
    hasHeaders: false,
    indexMapping: [0: "name", 1: "age", 2: "score"]
)
let decoder = CSVDecoder(configuration: config)
let records = try decoder.decode([Person].self, from: csv)
```

### @CSVIndexed Macro (Zero Boilerplate)

Eliminate all boilerplate for headerless CSV with the `@CSVIndexed` macro:

```swift
@CSVIndexed
struct Person: Codable {
    let name: String
    let age: Int
    let score: Double
}

// No manual CodingKeys or typealias needed
let config = CSVDecoder.Configuration(hasHeaders: false)
let decoder = CSVDecoder(configuration: config)
let people = try decoder.decode([Person].self, from: csv)
```

The macro generates `CodingKeys`, `CSVCodingKeys`, and protocol conformance automatically.

#### Custom Column Names with @CSVColumn

Map properties to different CSV column names:

```swift
@CSVIndexed
struct Product: Codable {
    let id: Int

    @CSVColumn("product_name")
    let name: String

    @CSVColumn("unit_price")
    let price: Double
}
```

### CSVIndexedDecodable (Manual Protocol)

For more control, conform to `CSVIndexedDecodable` manually:

```swift
struct Person: CSVIndexedDecodable {
    let name: String
    let age: Int
    let score: Double

    // CodingKeys order defines column order
    enum CodingKeys: String, CodingKey, CaseIterable {
        case name, age, score  // Column 0, 1, 2
    }

    typealias CSVCodingKeys = CodingKeys
}

// No indexMapping needed - decoder auto-detects CSVIndexedDecodable conformance
let config = CSVDecoder.Configuration(hasHeaders: false)
let decoder = CSVDecoder(configuration: config)
let people = try decoder.decode([Person].self, from: csv)
```

The order of cases in `CodingKeys` determines the column mapping automatically. The decoder detects `CSVIndexedDecodable` conformance at runtime, so you use the same `decode()` method as regular `Codable` types.

### Flexible Decoding Strategies

#### Date Decoding

Auto-detect dates from 20+ common formats:

```swift
let config = CSVDecoder.Configuration(
    dateDecodingStrategy: .flexible  // Auto-detect ISO, US, EU formats
)
```

Or provide a hint for better performance:

```swift
let config = CSVDecoder.Configuration(
    dateDecodingStrategy: .flexibleWithHint(preferred: "yyyy-MM-dd")
)
```

Available strategies:
- `.deferredToDate` - Use Date's Decodable implementation (default)
- `.iso8601` - ISO 8601 format
- `.secondsSince1970` / `.millisecondsSince1970` - Unix timestamps
- `.formatted(String)` - Custom date format
- `.flexible` - Auto-detect from common patterns
- `.flexibleWithHint(preferred:)` - Try preferred format first, then auto-detect
- `.custom((String) throws -> Date)` - Custom closure

#### Number Decoding

Handle international number formats:

```swift
let config = CSVDecoder.Configuration(
    numberDecodingStrategy: .flexible  // Auto-detect US/EU formats, strip currency
)
```

Available strategies:
- `.standard` - Swift's standard number parsing (default)
- `.flexible` - Auto-detect `1,234.56` (US) and `1.234,56` (EU), strip currency symbols
- `.locale(Locale)` - Use specific locale for parsing

#### Boolean Decoding

Support international boolean values:

```swift
let config = CSVDecoder.Configuration(
    boolDecodingStrategy: .flexible  // Recognize oui/non, ja/nein, да/нет, etc.
)
```

Available strategies:
- `.standard` - Recognize true/yes/1, false/no/0 (default)
- `.flexible` - Extended i18n values (oui/non, ja/nein, да/нет, 是/否, etc.)
- `.custom(trueValues:falseValues:)` - Custom value sets

### Error Diagnostics

Decoding errors include precise location information:

```swift
do {
    let records = try decoder.decode([Person].self, from: csv)
} catch let error as CSVDecodingError {
    print(error.errorDescription!)
    // "Type mismatch: expected Int, found 'invalid' at row 3, column 'age'"

    if let location = error.location {
        print("Row: \(location.row ?? 0)")      // 3
        print("Column: \(location.column ?? "")")  // "age"
    }
}
```

## Swift 6.2 Approachable Concurrency

CSVCoder is compatible with projects using `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. All encoding/decoding types are marked `nonisolated` to allow usage from any actor context.

## Performance

Benchmark results on Apple Silicon (M-series):

### Decoding

| Benchmark | Time | Throughput |
|-----------|------|------------|
| 1K rows (simple) | 2.3 ms | ~435K rows/s |
| 10K rows (simple) | 23.7 ms | ~422K rows/s |
| 100K rows (simple) | 239 ms | ~418K rows/s |
| 1M rows (simple) | 2.41 s | ~415K rows/s |
| 10K rows (complex, 8 fields) | 59 ms | ~169K rows/s |
| 10K rows (quoted fields) | 26 ms | ~385K rows/s |
| 10K rows (50 columns wide) | 236 ms | ~42K rows/s |
| 10K rows (500-byte fields) | 88 ms | ~114K rows/s |
| 100K rows (numeric fields) | 238 ms | ~420K rows/s |

### Encoding

| Benchmark | Time | Throughput |
|-----------|------|------------|
| 1K rows | 1.7 ms | ~588K rows/s |
| 10K rows | 17.3 ms | ~578K rows/s |
| 100K rows | 172 ms | ~581K rows/s |
| 1M rows | 1.73 s | ~578K rows/s |
| 10K rows (quoted fields) | 17.1 ms | ~585K rows/s |
| 10K rows (500-byte fields) | 62 ms | ~161K rows/s |
| 100K rows to Data | 171 ms | ~585K rows/s |
| 100K rows to String | 174 ms | ~575K rows/s |

### Parallel Processing (100K rows)

| Benchmark | Sequential | Parallel | Speedup |
|-----------|------------|----------|---------|
| Encode to Data | 170 ms | 83 ms | **2.05x** |
| Encode to File | - | 88 ms | - |
| Decode from Data | 668 ms | 859 ms | 0.78x* |
| Decode from File | - | 911 ms | - |

*Parallel decoding has overhead for smaller files. Benefits appear with larger datasets (1M+ rows) or complex parsing.

### Raw High-Performance API (Codable Bypass)

For performance-critical tasks (pre-processing, filtering, or massive datasets), you can bypass `Codable` overhead entirely using the zero-copy `CSVParser` API. This achieves **2.5x to 3x higher throughput** (~670K rows/s).

**Safe Usage:**
Use the `CSVParser.parse(data:)` wrapper to ensure memory safety.

```swift
let data = Data(contentsOf: bigFile)

// Count rows where age > 18
let count = try CSVParser.parse(data: data) { parser in
    var validCount = 0
    for row in parser {
        // 'row' is a zero-allocation View
        // Access fields by index (0-based)
        if let ageStr = row.string(at: 1), let age = Int(ageStr), age > 18 {
            validCount += 1
        }
    }
    return validCount
}
```

This approach avoids allocating `struct` or `class` instances for every row, drastically reducing ARC traffic.

#### Raw API Benchmarks (1M Rows)

| Benchmark | Time | Throughput | Speedup vs Codable |
|-----------|------|------------|-------------------|
| Raw Parse (Iterate Only) | 1.49 s | **~670K rows/s** | **2.6x** |
| Raw Parse (Iterate + String) | 1.54 s | **~650K rows/s** | **2.5x** |
| Raw Parse (Quoted Fields) | - | **~885K rows/s** | **2.8x** |

### Special Strategies (1K rows)

| Benchmark | Time | Throughput |
|-----------|------|------------|
| snake_case key conversion | 2.4 ms | ~417K rows/s |
| Flexible date parsing | 139 ms | ~7.2K rows/s |
| Flexible number parsing | 16 ms | ~63K rows/s |

Run benchmarks locally:
```bash
swift run -c release CSVCoderBenchmarks
```

## License

MIT License
