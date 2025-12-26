# CSVCoder

A Swift CSV encoder/decoder using the `Codable` protocol, similar to `JSONEncoder`/`JSONDecoder`.

## Features

- **Type-safe CSV encoding/decoding** via Swift's `Codable` protocol
- **Configurable delimiters** (comma, semicolon, tab, etc.)
- **Multiple date encoding strategies** (ISO 8601, Unix timestamp, custom format)
- **Optional value handling** with configurable nil encoding
- **Thread-safe** with `Sendable` conformance
- **Swift 6.2 Approachable Concurrency** compatible with `nonisolated` types

## Requirements

- iOS 18.0+ / macOS 15.0+
- Swift 6.0+

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

## Swift 6.2 Approachable Concurrency

CSVCoder is compatible with projects using `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. All encoding/decoding types are marked `nonisolated` to allow usage from any actor context.

## License

MIT License
