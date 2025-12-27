# ``CSVCoder``

A Swift CSV encoder/decoder using the `Codable` protocol.

## Overview

CSVCoder provides type-safe CSV encoding and decoding via Swift's `Codable` protocol, similar to `JSONEncoder` and `JSONDecoder`. It supports streaming for gigabyte-scale files, flexible parsing strategies, and parallel decoding for multi-core performance.

```swift
import CSVCoder

struct Person: Codable {
    let name: String
    let age: Int
    let email: String?
}

// Decode
let decoder = CSVDecoder()
let people = try decoder.decode([Person].self, from: csvData)

// Encode
let encoder = CSVEncoder()
let csv = try encoder.encodeToString(people)
```

## Topics

### Essentials

- <doc:GettingStarted>
- ``CSVEncoder``
- ``CSVDecoder``

### Encoding

- ``CSVEncoder``
- ``CSVEncoder/Configuration-swift.struct``
- ``CSVEncodingError``

### Decoding

- ``CSVDecoder``
- ``CSVDecoder/Configuration-swift.struct``
- ``CSVDecodingError``
- ``CSVLocation``

### Decoding Strategies

- ``CSVDecoder/DateDecodingStrategy``
- ``CSVDecoder/NumberDecodingStrategy``
- ``CSVDecoder/BoolDecodingStrategy``
- ``CSVDecoder/KeyDecodingStrategy``

### Streaming & Performance

- <doc:StreamingDecoding>
- <doc:ParallelDecoding>
