# Streaming Encoding

Encode large datasets with O(1) memory overhead.

## Overview

When encoding millions of records, loading everything into memory is impractical. CSVCoder provides streaming APIs that write records directly to files or network streams.

## Stream to File

Write records incrementally to a file:

```swift
let encoder = CSVEncoder()
let records: [Person] = ... // Or any Sequence/AsyncSequence

try await encoder.encode(records, to: fileURL)
```

Memory usage remains constant regardless of dataset size.

## Stream from AsyncSequence

Encode an async sequence as records become available:

```swift
let asyncRecords = AsyncStream<Person> { ... }

try await encoder.encode(asyncRecords, to: fileURL)
```

## Stream to AsyncSequence

Get encoded rows as they're produced:

```swift
for try await row in encoder.encodeToStream(records) {
    sendToNetwork(row)
}
```

## Streaming with Headers

Headers are written once when the first record is encoded:

```swift
let config = CSVEncoder.Configuration(hasHeaders: true)
let encoder = CSVEncoder(configuration: config)

try await encoder.encode(records, to: fileURL)
// First line: name,age,email
// Subsequent lines: record data
```

## Single Row Encoding

Encode individual records without creating a file:

```swift
let row = try encoder.encodeRow(person)
// "Alice,30,alice@example.com"
```

## Topics

### Related

- ``CSVEncoder``
