# CSVCoder Performance Optimization Strategy

**Target**: Handle CSV files up to several gigabytes
**Constraint**: Constant memory usage regardless of file size
**Approach**: Streaming/lazy evaluation with memory-mapped I/O

---

## Current Implementation Analysis

### Memory Bottlenecks (Critical Path)

```
File (2GB) → String (2GB) → [Character] (4GB) → [[String]] (2GB) → [T] (varies)
                            ↑                    ↑
                        CSVParser:32          CSVParser:23
                        Array(string)         rows: [[String]]
```

**Total peak memory for 2GB file**: ~8GB+

### Specific Bottleneck Locations

| File:Line | Code | Problem |
|-----------|------|---------|
| `CSVParser.swift:32` | `let chars = Array(string)` | Copies entire string to Character array (~2x memory) |
| `CSVParser.swift:23` | `var rows: [[String]] = []` | Stores all parsed rows before returning |
| `CSVDecoder.swift:110` | `String(data:encoding:)` | Loads entire file as String |
| `CSVDecoder.swift:123` | `let rows = try parser.parse()` | Synchronous, blocking parse |
| `CSVDecoder.swift:139` | `var dictionary: [String: String]` | Dictionary allocation per row |

---

## Optimization Strategy

### Tier 1: Streaming Core (Essential for GB files)

**Goal**: O(1) memory usage regardless of file size

#### 1.1 AsyncSequence-based Decoder

```swift
// New API
public func decode<T: Decodable>(
    _ type: T.Type,
    from url: URL
) -> AsyncThrowingStream<T, Error>

// Usage
for try await record in decoder.decode(Record.self, from: fileURL) {
    process(record)
}
```

#### 1.2 Streaming Parser

Replace batch parsing with row-by-row yielding:

```swift
struct StreamingCSVParser: AsyncSequence {
    typealias Element = [String]

    let fileHandle: FileHandle
    let configuration: CSVDecoder.Configuration
    let chunkSize: Int = 64 * 1024  // 64KB chunks

    struct AsyncIterator: AsyncIteratorProtocol {
        // State machine for incremental parsing
        // Yields one row at a time
        mutating func next() async throws -> [String]?
    }
}
```

#### 1.3 Memory-Mapped File Access

Use `mmap` for efficient random access without loading file:

```swift
final class MemoryMappedCSVReader {
    private let data: Data  // Memory-mapped, not loaded
    private var offset: Int = 0

    init(url: URL) throws {
        // NSDataReadingOptions.mappedIfSafe
        self.data = try Data(contentsOf: url, options: .mappedIfSafe)
    }

    func nextChunk(size: Int) -> Data.SubSequence? {
        guard offset < data.count else { return nil }
        let end = min(offset + size, data.count)
        defer { offset = end }
        return data[offset..<end]
    }
}
```

### Tier 2: UTF-8 Direct Parsing (2-4x speedup)

**Goal**: Avoid Character overhead, parse UTF-8 bytes directly

#### 2.1 Byte-Level Parsing

```swift
// Current (slow): Character comparison with Unicode scalar lookup
let isCR = char.unicodeScalars.first?.value == 0x0D

// Optimized: Direct byte comparison
let byte = bytes[i]
let isCR = byte == 0x0D  // ASCII CR
let isLF = byte == 0x0A  // ASCII LF
let isQuote = byte == 0x22  // ASCII "
let isComma = byte == 0x2C  // ASCII ,
```

#### 2.2 SIMD-Accelerated Scanning

For finding delimiters in large chunks:

```swift
import Accelerate

func findDelimiters(in buffer: UnsafeBufferPointer<UInt8>) -> [Int] {
    // Use vDSP or manual SIMD to scan for delimiter bytes
    // ~8x faster than character-by-character for large buffers
}
```

### Tier 3: Allocation Optimization (30-50% improvement)

#### 3.1 Pre-allocated Buffers

```swift
final class ReusableRowBuffer {
    private var fields: [String]
    private var fieldBuffer: String

    init(estimatedColumns: Int = 32) {
        fields = []
        fields.reserveCapacity(estimatedColumns)
        fieldBuffer = ""
        fieldBuffer.reserveCapacity(1024)
    }

    func reset() {
        fields.removeAll(keepingCapacity: true)
        fieldBuffer.removeAll(keepingCapacity: true)
    }
}
```

#### 3.2 Substring Retention

Avoid copying strings when possible:

```swift
// Instead of: currentField.append(char)
// Use: Track start/end indices, create Substring at field boundary

struct FieldRange {
    let start: Int
    let end: Int
}

// Create String only when needed for decoding
func field(at range: FieldRange, in buffer: Data) -> String {
    String(decoding: buffer[range.start..<range.end], as: UTF8.self)
}
```

### Tier 4: Parallel Processing (For multi-core utilization)

#### 4.1 Chunked Parallel Decoding

```swift
// Split file into chunks at row boundaries
// Decode chunks in parallel using TaskGroup
func parallelDecode<T: Decodable & Sendable>(
    _ type: T.Type,
    from url: URL,
    parallelism: Int = ProcessInfo.processInfo.activeProcessorCount
) async throws -> [T]
```

#### 4.2 Concurrent Row Decoding

```swift
// After streaming parse, decode rows concurrently
await withTaskGroup(of: T?.self) { group in
    for row in rowBatch {
        group.addTask { try? decode(row) }
    }
    // Collect results maintaining order
}
```

---

## Implementation Priority

### Phase A: Streaming Foundation (Highest Priority)

**Must have for GB files**

1. **A.1** `StreamingCSVParser` with `AsyncSequence` conformance
2. **A.2** Memory-mapped file reader
3. **A.3** `CSVDecoder.decode(_:from: URL) -> AsyncThrowingStream`
4. **A.4** Incremental row decoding (no intermediate `[[String]]`)

**Memory target**: <50MB regardless of file size
**Expected effort**: Medium-High

### Phase B: Performance Optimization

**Improves throughput significantly**

1. **B.1** UTF-8 byte-level parsing (replace Character iteration)
2. **B.2** Reusable buffer pools
3. **B.3** Substring retention for field extraction

**Speed target**: 2-4x improvement over naive implementation
**Expected effort**: Medium

### Phase C: Advanced Features

**For specialized use cases**

1. **C.1** Parallel chunk decoding
2. **C.2** SIMD delimiter scanning
3. **C.3** Configurable memory limits and backpressure

**Expected effort**: High

---

## Revised Phase Order

Given gigabyte-scale requirements, recommended phase order:

```
Original:  Phase 1 → Phase 2 → Phase 3 → Phase 4
                     (flexibility) (polish)  (streaming)

Revised:   Phase 1 → Phase 2A → Phase 2B → Phase 3
                     (streaming) (flexibility) (polish)
```

### Rationale

1. **Streaming is foundational** - Without it, the library is unusable for large files
2. **Flexibility features can build on streaming** - Custom keys, headerless modes work with streaming
3. **Polish comes last** - DocC, CI, releases make sense after core features stabilize

---

## API Design for Streaming

### New Public API

```swift
extension CSVDecoder {
    // Streaming decode from URL (primary API for large files)
    public func decode<T: Decodable>(
        _ type: T.Type,
        from url: URL
    ) -> AsyncThrowingStream<T, Error>

    // Streaming decode from AsyncSequence of Data chunks
    public func decode<T: Decodable, S: AsyncSequence>(
        _ type: T.Type,
        from chunks: S
    ) -> AsyncThrowingStream<T, Error> where S.Element == Data

    // Batch decode with memory limit (loads up to N rows)
    public func decode<T: Decodable>(
        _ type: [T].Type,
        from url: URL,
        batchSize: Int
    ) async throws -> [[T]]
}
```

### Backward Compatibility

Existing synchronous APIs remain unchanged:

```swift
// Still works for small files
let records = try decoder.decode([Record].self, from: csvString)
let records = try decoder.decode([Record].self, from: csvData)
```

---

## Benchmarking Targets

| File Size | Current (est.) | Target | Memory |
|-----------|---------------|--------|--------|
| 10 MB | ~200ms | <100ms | <20MB |
| 100 MB | ~2s | <500ms | <30MB |
| 1 GB | OOM or ~30s | <5s | <50MB |
| 10 GB | OOM | <50s | <50MB |

---

## Testing Strategy

### Performance Tests

```swift
@Test("Stream 1GB file with constant memory")
func streamLargeFile() async throws {
    let url = generateLargeCSV(rows: 10_000_000, columns: 10)  // ~1GB

    var count = 0
    let startMemory = currentMemoryUsage()

    for try await _ in decoder.decode(Record.self, from: url) {
        count += 1

        // Periodic memory check
        if count % 100_000 == 0 {
            let currentMemory = currentMemoryUsage()
            #expect(currentMemory - startMemory < 50_000_000)  // <50MB growth
        }
    }

    #expect(count == 10_000_000)
}
```

### Throughput Tests

```swift
@Test("Parse at >100MB/s")
func parseThroughput() async throws {
    let url = generateLargeCSV(rows: 1_000_000, columns: 10)
    let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as! Int

    let start = ContinuousClock.now
    var count = 0
    for try await _ in decoder.decode(Record.self, from: url) {
        count += 1
    }
    let elapsed = ContinuousClock.now - start

    let throughput = Double(fileSize) / elapsed.components.seconds
    #expect(throughput > 100_000_000)  // >100 MB/s
}
```

---

## Files to Create/Modify

### New Files

| File | Purpose |
|------|---------|
| `StreamingCSVParser.swift` | AsyncSequence-based row parser |
| `MemoryMappedReader.swift` | Memory-mapped file access |
| `CSVDecoder+Streaming.swift` | Streaming decode extension |
| `UTF8Parser.swift` | Byte-level parsing (optional, Tier 2) |

### Modified Files

| File | Changes |
|------|---------|
| `CSVDecoder.swift` | Add URL-based streaming methods |
| `CSVParser.swift` | Refactor core logic for reuse |

---

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Quoted fields spanning chunks | Buffer incomplete rows across chunks |
| BOM in first chunk | Detect and skip UTF-8 BOM (EF BB BF) |
| Encoding detection | Default UTF-8, allow configuration |
| Backpressure handling | AsyncStream with buffering policy |
| Memory-mapped file limits | Fall back to chunked reading for network/pipes |
