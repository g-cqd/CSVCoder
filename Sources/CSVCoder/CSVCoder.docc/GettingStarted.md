# Getting Started with CSVCoder

Learn how to encode and decode CSV data using Swift's Codable protocol.

## Overview

CSVCoder provides a familiar API pattern for working with CSV data. If you've used `JSONEncoder` or `JSONDecoder`, you'll feel right at home.

## Define Your Model

Create a Swift struct or class conforming to `Codable`:

```swift
struct Person: Codable {
    let name: String
    let age: Int
    let email: String?
}
```

## Decode CSV Data

Use ``CSVDecoder`` to parse CSV into your model:

```swift
let csvData = """
name,age,email
Alice,30,alice@example.com
Bob,25,
""".data(using: .utf8)!

let decoder = CSVDecoder()
let people = try decoder.decode([Person].self, from: csvData)
// [Person(name: "Alice", age: 30, email: "alice@example.com"),
//  Person(name: "Bob", age: 25, email: nil)]
```

## Encode to CSV

Use ``CSVEncoder`` to generate CSV from your models:

```swift
let people = [
    Person(name: "Alice", age: 30, email: "alice@example.com"),
    Person(name: "Bob", age: 25, email: nil)
]

let encoder = CSVEncoder()
let csv = try encoder.encodeToString(people)
// name,age,email
// Alice,30,alice@example.com
// Bob,25,
```

## Configure Parsing

Customize behavior with ``CSVDecoder/Configuration-swift.struct``:

```swift
let config = CSVDecoder.Configuration(
    delimiter: ";",                              // Semicolon-delimited
    dateDecodingStrategy: .iso8601,              // ISO 8601 dates
    keyDecodingStrategy: .convertFromSnakeCase   // snake_case → camelCase
)
let decoder = CSVDecoder(configuration: config)
```

## Handle Messy Data

CSVCoder includes flexible strategies for real-world data:

### Automatic Header Conversion

```swift
// CSV: first_name,last_name,email_address
// Swift: firstName, lastName, emailAddress
let config = CSVDecoder.Configuration(
    keyDecodingStrategy: .convertFromSnakeCase
)
```

### Flexible Date Parsing

```swift
// Auto-detect from 20+ date formats
let config = CSVDecoder.Configuration(
    dateDecodingStrategy: .flexible
)
```

### International Numbers

```swift
// Parse both "1,234.56" and "1.234,56"
let config = CSVDecoder.Configuration(
    numberDecodingStrategy: .flexible
)
```

## Topics

### Next Steps

- <doc:StreamingDecoding>
- <doc:ParallelDecoding>
