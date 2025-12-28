# Parallel Encoding

Encode large datasets faster using multiple CPU cores.

## Overview

CSVCoder can encode records in parallel when dealing with large datasets, then write them sequentially to maintain correct row order.

## Parallel Encode to Data

Encode records using all available cores:

```swift
let encoder = CSVEncoder()
let records: [Person] = ... // Large array

let data = try await encoder.encodeParallel(records)
```

## Parallel Encode to File

Write directly to a file for memory efficiency:

```swift
let encoder = CSVEncoder()
let records: [Person] = ...

try await encoder.encodeParallel(
    records,
    to: fileURL,
    parallelConfig: .init(parallelism: 8)
)
```

## Configure Parallelism

Fine-tune parallel execution:

```swift
let config = CSVEncoder.ParallelEncodingConfiguration(
    parallelism: 8,        // Number of concurrent workers
    chunkSize: 10_000,     // Records per chunk
    bufferSize: 65_536     // Write buffer size
)

let data = try await encoder.encodeParallel(records, parallelConfig: config)
```

## Batched Encoding with Progress

Process chunks incrementally for progress reporting:

```swift
var totalRows = 0
for try await batch in encoder.encodeParallelBatched(
    records,
    parallelConfig: .init(chunkSize: 5_000)
) {
    totalRows += batch.count
    print("Encoded \(totalRows) rows")
}
```

## Performance Characteristics

| Dataset Size | Sequential | Parallel (8 cores) | Speedup |
|--------------|------------|-------------------|---------|
| 10K rows     | 17 ms      | 17 ms             | ~1.0x   |
| 100K rows    | 170 ms     | 83 ms             | ~2.0x   |
| 1M rows      | 1.7 s      | 0.4 s             | ~4.0x   |

Parallel encoding benefits increase with dataset size due to reduced per-chunk overhead.

## Topics

### Related

- <doc:StreamingEncoding>
- ``CSVEncoder``
