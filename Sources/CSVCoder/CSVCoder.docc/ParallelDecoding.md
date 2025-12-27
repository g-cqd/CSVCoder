# Parallel Decoding

Leverage multiple CPU cores for faster CSV processing.

## Overview

For large CSV files where decoding is CPU-bound, CSVCoder can split the file into chunks and decode them in parallel using Swift's structured concurrency.

## Parallel Decode

Decode a file using all available cores:

```swift
let decoder = CSVDecoder()
let fileURL = URL(fileURLWithPath: "/path/to/large.csv")

let people = try await decoder.decodeParallel(
    [Person].self,
    from: fileURL
)
```

## Configure Parallelism

Fine-tune parallel execution:

```swift
let parallelConfig = CSVDecoder.ParallelConfiguration(
    parallelism: 8,              // Number of concurrent workers
    chunkSize: 1_000_000,        // Bytes per chunk (1 MB)
    preserveOrder: true          // Keep original row order
)

let people = try await decoder.decodeParallel(
    [Person].self,
    from: fileURL,
    parallelConfig: parallelConfig
)
```

## Parallel Batched Streaming

Process batches as they complete for memory efficiency:

```swift
for try await batch in decoder.decodeParallelBatched(
    Person.self,
    from: fileURL,
    parallelConfig: .init(parallelism: 4)
) {
    // batch: [Person] from one chunk
    processBatch(batch)
}
```

## Unordered for Maximum Throughput

When row order doesn't matter:

```swift
let parallelConfig = CSVDecoder.ParallelConfiguration(
    preserveOrder: false  // Maximum throughput
)

let people = try await decoder.decodeParallel(
    [Person].self,
    from: fileURL,
    parallelConfig: parallelConfig
)
```

## SIMD Acceleration

CSVCoder uses SIMD instructions for scanning structural characters (quotes, delimiters, newlines). This provides ~8x faster scanning compared to scalar processing.

The SIMD scanner is used automatically when:
- File is memory-mapped
- Platform supports SIMD64<UInt8>

## Performance Guidelines

| Scenario | Recommended Approach |
|----------|---------------------|
| Single-threaded sufficient | Standard streaming |
| CPU-bound decoding | Parallel with `preserveOrder: true` |
| Maximum throughput | Parallel with `preserveOrder: false` |
| Memory constrained | Streaming with backpressure |

## Topics

### Related

- <doc:StreamingDecoding>
- ``CSVDecoder``
