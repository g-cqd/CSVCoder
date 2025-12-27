# CSVEncoder Performance Strategy

## Current State Analysis

The current `CSVEncoder` implementation has similar memory and performance limitations as the original decoder:

### Memory Bottlenecks

```swift
// CSVEncoder.swift:111 - Stores all rows in memory
var rows: [[String: String]] = []

// CSVEncoder.swift:115-127 - Encodes all values before any output
for value in values {
    let storage = CSVEncodingStorage()
    let encoder = CSVRowEncoder(...)
    try value.encode(to: encoder)
    rows.append(storage.allValues())  // Accumulates all rows
}

// CSVEncoder.swift:141-146 - Builds all lines in memory
var lines: [String] = []
for row in rows {
    lines.append(...)  // Another full copy
}
return lines.joined(separator: lineEnding)
```

### Memory Usage for 2GB Output

```
[T] array → [[String: String]] → [String] → Final String → Data
   varies         2GB              2GB          2GB          2GB

Peak memory: ~8GB for 2GB output (unacceptable)
```

## Proposed Improvements

### Phase E1: Streaming Encoding

**Goal**: O(1) memory for writing to files/streams

#### E1.1 AsyncSequence Input

Accept `AsyncSequence` of encodable values:

```swift
extension CSVEncoder {
    /// Stream encode to a file URL
    func encode<S: AsyncSequence>(
        _ values: S,
        to url: URL
    ) async throws where S.Element: Encodable & Sendable

    /// Stream encode to a FileHandle
    func encode<S: AsyncSequence>(
        _ values: S,
        to handle: FileHandle
    ) async throws where S.Element: Encodable & Sendable
}
```

#### E1.2 Incremental Row Encoding

Encode and write rows one at a time:

```swift
struct StreamingCSVEncoder {
    private var headerWritten = false
    private var keys: [String]?

    mutating func writeRow<T: Encodable>(_ value: T, to handle: FileHandle) throws {
        let row = encodeRow(value)

        if !headerWritten {
            keys = row.keys
            writeHeaders(to: handle)
            headerWritten = true
        }

        let line = formatRow(row)
        handle.write(line.data(using: .utf8)!)
    }
}
```

#### E1.3 Direct Byte Writing

Avoid String intermediates by writing UTF-8 bytes directly:

```swift
func writeField(_ value: String, to buffer: inout [UInt8]) {
    let needsQuoting = value.utf8.contains(where: { $0 == 0x2C || $0 == 0x22 || $0 == 0x0A })

    if needsQuoting {
        buffer.append(0x22)  // Opening quote
        for byte in value.utf8 {
            if byte == 0x22 {
                buffer.append(0x22)  // Escape quote
            }
            buffer.append(byte)
        }
        buffer.append(0x22)  // Closing quote
    } else {
        buffer.append(contentsOf: value.utf8)
    }
}
```

### Phase E2: Parallel Encoding

**Goal**: Utilize multiple cores for encoding

#### E2.1 Parallel Row Encoding

Encode rows in parallel, then write sequentially:

```swift
func encodeParallel<T: Encodable & Sendable>(
    _ values: [T],
    to url: URL,
    parallelism: Int = ProcessInfo.processInfo.activeProcessorCount
) async throws {
    // 1. Encode rows in parallel using TaskGroup
    let encodedRows = try await withTaskGroup(of: (Int, String).self) { group in
        for (index, value) in values.enumerated() {
            group.addTask {
                let row = try encodeRow(value)
                return (index, row)
            }
        }

        var results = [(Int, String)]()
        for try await result in group {
            results.append(result)
        }
        return results.sorted { $0.0 < $1.0 }.map { $0.1 }
    }

    // 2. Write sequentially (I/O bound)
    let handle = try FileHandle(forWritingTo: url)
    for row in encodedRows {
        handle.write(row.data(using: .utf8)!)
    }
}
```

#### E2.2 Chunked Parallel Encoding

For very large datasets, process in chunks:

```swift
func encodeParallelChunked<T: Encodable & Sendable>(
    _ values: [T],
    to url: URL,
    chunkSize: Int = 10_000
) async throws {
    let chunks = stride(from: 0, to: values.count, by: chunkSize).map {
        Array(values[$0..<min($0 + chunkSize, values.count)])
    }

    // Process chunks in parallel
    for chunk in chunks {
        let encodedChunk = try await encodeChunkParallel(chunk)
        writeChunk(encodedChunk, to: handle)
    }
}
```

### Phase E3: Batched Streaming

**Goal**: Combine streaming with batching for optimal I/O

#### E3.1 Buffered Writing

Buffer output for efficient I/O:

```swift
struct BufferedCSVWriter {
    private var buffer: [UInt8] = []
    private let bufferSize: Int  // e.g., 64KB
    private let handle: FileHandle

    mutating func write(_ bytes: [UInt8]) throws {
        buffer.append(contentsOf: bytes)
        if buffer.count >= bufferSize {
            try flush()
        }
    }

    mutating func flush() throws {
        handle.write(Data(buffer))
        buffer.removeAll(keepingCapacity: true)
    }
}
```

#### E3.2 AsyncStream Output

Provide rows as an async stream for flexibility:

```swift
extension CSVEncoder {
    func encodeToStream<T: Encodable & Sendable>(
        _ values: some AsyncSequence<T, Error>
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var isFirst = true
                for try await value in values {
                    if isFirst {
                        continuation.yield(encodeHeaders(from: value))
                        isFirst = false
                    }
                    continuation.yield(encodeRow(value))
                }
                continuation.finish()
            }
        }
    }
}
```

### Phase E4: Advanced Optimizations

#### E4.1 Pre-computed Field Metadata

Cache encoding decisions per type:

```swift
struct EncodingMetadata {
    let fieldCount: Int
    let fieldNames: [String]
    let requiresQuoting: [Bool]  // Pre-computed for known safe fields
}

// Cache per type
private var metadataCache: [ObjectIdentifier: EncodingMetadata] = [:]
```

#### E4.2 SIMD Field Scanning

Use SIMD to check if fields need quoting:

```swift
func needsQuoting(_ string: String) -> Bool {
    string.utf8.withContiguousStorageIfAvailable { buffer in
        var i = 0
        while i + 64 <= buffer.count {
            let chunk = SIMD64<UInt8>(buffer[i..<i+64])
            let hasComma = chunk .== 0x2C
            let hasQuote = chunk .== 0x22
            let hasNewline = chunk .== 0x0A
            if (hasComma | hasQuote | hasNewline).any() {
                return true
            }
            i += 64
        }
        // Check remainder
        for j in i..<buffer.count {
            if buffer[j] == 0x2C || buffer[j] == 0x22 || buffer[j] == 0x0A {
                return true
            }
        }
        return false
    } ?? true  // Conservative fallback
}
```

## Proposed API

```swift
extension CSVEncoder {
    // MARK: - Streaming Encoding

    /// Stream encode to a file
    func encode<S: AsyncSequence>(
        _ values: S,
        to url: URL
    ) async throws where S.Element: Encodable & Sendable

    /// Stream encode to a FileHandle
    func encode<S: AsyncSequence>(
        _ values: S,
        to handle: FileHandle
    ) async throws where S.Element: Encodable & Sendable

    /// Encode to an async stream of rows
    func encodeToStream<T: Encodable & Sendable>(
        _ values: some AsyncSequence<T, Error>
    ) -> AsyncThrowingStream<String, Error>

    // MARK: - Parallel Encoding

    /// Parallel encode to a file
    func encodeParallel<T: Encodable & Sendable>(
        _ values: [T],
        to url: URL,
        parallelConfig: ParallelConfiguration
    ) async throws

    /// Parallel encode returning Data
    func encodeParallel<T: Encodable & Sendable>(
        _ values: [T],
        parallelConfig: ParallelConfiguration
    ) async throws -> Data
}

extension CSVEncoder {
    struct ParallelConfiguration: Sendable {
        var parallelism: Int
        var chunkSize: Int
        var bufferSize: Int

        static var `default`: Self {
            .init(
                parallelism: ProcessInfo.processInfo.activeProcessorCount,
                chunkSize: 10_000,
                bufferSize: 65_536
            )
        }
    }
}
```

## Performance Targets

| Operation | File Size | Target Time | Target Memory |
|-----------|-----------|-------------|---------------|
| Stream encode | 1 GB | < 10s | < 50 MB |
| Parallel encode | 1 GB | < 5s | < 200 MB |
| Buffered write | Any | N/A | buffer size |

## Implementation Order

1. **E1.2 Incremental Row Encoding** - Foundation for streaming
2. **E1.1 AsyncSequence Input** - Streaming API
3. **E3.1 Buffered Writing** - Efficient I/O
4. **E2.1 Parallel Row Encoding** - Multi-core utilization
5. **E4.1 Pre-computed Metadata** - Type-level optimization
6. **E4.2 SIMD Scanning** - Field-level optimization

## Files to Create

| File | Purpose |
|------|---------|
| `CSVEncoder+Streaming.swift` | Streaming encode extension |
| `CSVEncoder+Parallel.swift` | Parallel encode extension |
| `BufferedCSVWriter.swift` | Buffered file writing |
