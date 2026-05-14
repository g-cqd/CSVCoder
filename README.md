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
- **Safe error handling** — no `fatalError()` calls; all unsupported operations throw
- **Swift 6.2 Approachable Concurrency** compatible with `nonisolated` types

## Requirements

- iOS 18.0+ / macOS 15.0+
- Swift 6.2+

## Breaking changes since 0.0.4

The audit follow-up landed on `main` 2026-05-14 and introduces three
source-breaking changes worth highlighting:

- **`convertToSnakeCase` is now acronym-aware.**  The algorithm matches
  `JSONEncoder._convertToSnakeCase` from swift-foundation:
  `myURLProperty` produces `my_url_property` instead of the previous
  `my_u_r_l_property`.  The inverse `convertFromSnakeCase` mirrors
  `JSONDecoder` (`my_url` → `myUrl`).  Migrate by either changing
  fixture data or accepting the new headers.
- **`.json` nested strategy now carries an `Int = 1 << 20` byte budget.**
  `CSVEncoder.Configuration(nestedTypeEncodingStrategy: .json)` and the
  decoder equivalent now have to be written as `.json()` (default 1 MiB
  cap) or `.json(maxBytes: <number>)`.  `.codable` is deprecated as a
  renamed alias and will be removed in a future minor release.
- **`expectedFieldCount` is enforced in both lenient and strict modes.**
  Previously a `expectedFieldCount: 5` setting silently no-op'd outside
  strict mode.  Mixed-width CSV will now surface a parsing error.

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
    delimiter: ";",                           // Use semicolon (must be ASCII)
    hasHeaders: true,                         // Include header row
    dateEncodingStrategy: .iso8601,           // ISO 8601 dates
    nilEncodingStrategy: .emptyString,        // Empty string for nil
    lineEnding: .crlf,                        // Windows line endings
    includesTrailingNewline: true             // Add newline after last row
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

The macro generates `CodingKeys`, `CSVCodingKeys`, and protocol conformance
automatically.  Both `CSVDecoder` and `CSVEncoder` honour the macro's
declared column order — the encoder writes the header and data rows in
`CodingKeys` order regardless of property declaration order, and works
identically across the sync, streaming, parallel, and batched encode
entry points.

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

The macro emits a compile-time error for duplicate `@CSVColumn` names on
the same struct, and a warning when `@CSVColumn` is applied to a property
whose parent struct lacks `@CSVIndexed` (the rename would silently do
nothing without the macro to read it).

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
- `.localeAware(locale:style:)` - Region-aware parsing via `Date.FormatStyle.parseStrategy`
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
- `.locale(Locale)` - Use specific locale for parsing via `FloatingPointFormatStyle`
- `.parseStrategy(locale:)` - Region-aware parsing via `FloatingPointFormatStyle.ParseStrategy`
- `.currency(code:locale:)` - Currency-aware parsing that strips known currency symbols

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

> Numbers below were measured on Apple M2 Pro (10 cores: 6P + 4E), 16 GB RAM,
> macOS 26.4.1, Swift 6.2, release build, 3 iterations with one warm-up. Hardware
> and toolchain differences will shift absolute timings — run
> `swift run -c release CSVCoderBenchmarks` locally for numbers you can
> compare against. The table is a representative subset; the full benchmark
> harness exposes 40+ cases.

### Architecture

- **Zero-copy parser.** Field offsets/lengths are stored in a packed
  struct-of-arrays; rows borrow into the source `Data` buffer with no
  per-row allocation.
- **SIMD scanning.** 64-byte vector compares find structural bytes (`"`,
  delimiter, `\r`, `\n`); SWAR (8-byte register operations) covers the
  tail. Falls back to scalar for the last 0–7 bytes.
- **Byte-level trim.** `trimWhitespace` runs over a `Span<UInt8>` view
  with bounds-checked-at-compile-time semantics; no second `String`
  allocation per field.
- **Mutex-serialized encoder storage.** Encoder cells are deposited
  through `Synchronization.Mutex` so the same `CSVEncoder` can drive
  multiple concurrent encodes without coordination from the caller.

### Decoding

| Benchmark | Time | Throughput |
|-----------|------|------------|
| 1K rows (simple) | 1.3 ms | ~770K rows/s |
| 10K rows (simple) | 13 ms | ~750K rows/s |
| 100K rows (simple) | 132 ms | ~760K rows/s |
| 1M rows (simple) | 1.33 s | ~754K rows/s |
| 10K rows (complex, 8 fields) | 29 ms | ~344K rows/s |
| 10K rows (quoted fields) | 15 ms | ~660K rows/s |
| 100K rows (numeric fields) | 138 ms | ~725K rows/s |

### Real-World Scenarios

| Benchmark | Time | Throughput |
|-----------|------|------------|
| 50K orders (18 fields, optionals) | 283 ms | ~177K rows/s |
| 100K transactions (13 fields) | 447 ms | ~224K rows/s |

### Encoding

| Benchmark | Time | Throughput |
|-----------|------|------------|
| 1K rows | 1.3 ms | ~770K rows/s |
| 10K rows | 13 ms | ~770K rows/s |
| 100K rows | 146 ms | ~685K rows/s |
| 1M rows | 1.28 s | ~779K rows/s |
| 50K orders (18 fields, optionals) | 220 ms | ~227K rows/s |
| 100K rows to Data | 145 ms | ~690K rows/s |
| 100K rows to String | 132 ms | ~758K rows/s |

### Parallel Processing

| Benchmark | Sequential | Parallel | Speedup |
|-----------|-----------:|---------:|--------:|
| Decode 100K rows | 132 ms | 97 ms | **1.36×** |
| Decode 1M rows | 1.33 s | 919 ms | **1.44×** |
| Encode 100K rows | 146 ms | 41 ms | **3.54×** |
| Encode 1M rows | 1.28 s | 423 ms | **3.04×** |

### Mixed Workloads

| Benchmark | Time |
|-----------|------|
| Decode + Transform + Encode 10K | 27 ms |
| Filter + Aggregate 100K orders | 290 ms |

### Raw High-Performance API (Codable Bypass)

For performance-critical pipelines (pre-processing, filtering, or massive
datasets), bypass `Codable` overhead entirely using the zero-copy
`CSVParser` API. The parser yields ``CSVRowView`` instances that reference
the source buffer with no per-row allocation.

```swift
let data = try Data(contentsOf: bigFile)

let count = try CSVParser.parse(data: data) { parser in
    var validCount = 0
    for row in parser {
        if let ageStr = row.string(at: 1), let age = Int(ageStr), age > 18 {
            validCount += 1
        }
    }
    return validCount
}
```

#### Raw API Benchmarks

| Benchmark | Time | Throughput |
|-----------|------|------------|
| Raw Parse 1M rows (Iterate Only) | 85 ms | **~11.78M rows/s** |
| Raw Parse 1M rows (Iterate + String) | 214 ms | **~4.69M rows/s** |
| Raw Parse 100K Quoted (Iterate Only) | 9 ms | **~11.24M rows/s** |
| Raw Parse 100K Quoted (Iterate + String) | 37 ms | **~2.70M rows/s** |

Run benchmarks locally:

```bash
swift run -c release CSVCoderBenchmarks
```

## License

MIT License
