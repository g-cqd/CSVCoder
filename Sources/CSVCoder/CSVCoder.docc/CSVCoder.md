# ``CSVCoder``

A Swift CSV encoder/decoder using the `Codable` protocol.

## Overview

CSVCoder provides type-safe CSV encoding and decoding via Swift's `Codable` protocol, similar to `JSONEncoder` and `JSONDecoder`. It supports streaming for gigabyte-scale files, flexible parsing strategies, parallel processing for multi-core performance, and Swift macros for zero-boilerplate headerless CSV.

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

## Features

- **Type-safe encoding/decoding** via Swift's `Codable` protocol
- **Zero-boilerplate macros** (`@CSVIndexed`, `@CSVColumn`) for headerless CSV
- **Streaming** for O(1) memory with gigabyte-scale files
- **Parallel processing** for multi-core performance
- **Flexible parsing** with automatic date, number, and boolean detection
- **SIMD-accelerated** parsing for maximum throughput
- **Swift 6.2 concurrency** compatible with `nonisolated` types

## Performance

CSVCoder uses **SIMD-accelerated parsing** with 64-byte vector operations and **SWAR (SIMD Within A Register)** 8-byte fallback for efficient field scanning. This optimization is particularly effective for:

- **Quoted fields** with long spans of non-structural bytes (~15% faster)
- **Large fields** (500+ bytes) where vectorized scanning excels
- **Unicode-heavy content** processed efficiently in bulk

For maximum throughput on large datasets, use ``CSVParser`` directly with the zero-copy API to bypass `Codable` overhead (~2x faster).

## Topics

### Essentials

- <doc:GettingStarted>
- ``CSVEncoder``
- ``CSVDecoder``

### Encoding

- ``CSVEncoder``
- ``CSVEncoder/Configuration-swift.struct``
- ``CSVEncoder/DateEncodingStrategy``
- ``CSVEncoder/KeyEncodingStrategy``
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
- ``CSVDecoder/NilDecodingStrategy``
- ``CSVDecoder/ParsingMode``

### Macros & Index-Based Decoding

- <doc:Macros>
- ``CSVIndexedDecodable``

### Streaming

- <doc:StreamingDecoding>
- <doc:StreamingEncoding>

### Parallel Processing

- <doc:ParallelDecoding>
- <doc:ParallelEncoding>
- ``CSVDecoder/ParallelConfiguration``
- ``CSVEncoder/ParallelEncodingConfiguration``
