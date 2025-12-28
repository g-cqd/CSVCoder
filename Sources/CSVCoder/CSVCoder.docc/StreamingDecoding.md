# Streaming Decoding

Process gigabyte-scale CSV files with constant memory usage.

## Overview

For large CSV files, loading everything into memory is impractical. CSVCoder provides streaming APIs that process files row-by-row with O(1) memory overhead.

## Stream from Files

Use `AsyncThrowingStream` to process files without loading them entirely:

```swift
let decoder = CSVDecoder()
let fileURL = URL(fileURLWithPath: "/path/to/large.csv")

for try await person in decoder.decode(Person.self, from: fileURL) {
    process(person)
}
```

Memory usage remains constant regardless of file size.

## Stream from Data

For in-memory data that's still too large to decode at once:

```swift
let largeData: Data = ...

for try await person in decoder.decode(Person.self, from: largeData) {
    process(person)
}
```

## Collect All Results

When you do want all records in memory:

```swift
// Async convenience method
let people = try await decoder.decode([Person].self, from: fileURL)
```

## Memory-Aware Streaming

Configure backpressure to limit memory consumption:

```swift
let memoryConfig = CSVDecoder.MemoryLimitConfiguration(
    memoryBudget: 50_000_000,    // 50 MB max
    highWaterMark: 0.8,          // Pause at 80%
    lowWaterMark: 0.4            // Resume at 40%
)

for try await person in decoder.decodeWithBackpressure(
    Person.self,
    from: fileURL,
    memoryConfig: memoryConfig
) {
    // Processing automatically paused if memory limit approached
    process(person)
}
```

## Progress Reporting

Track decoding progress for user feedback:

```swift
for try await person in decoder.decodeWithProgress(
    Person.self,
    from: fileURL,
    progressHandler: { progress in
        print("\(Int(progress.fraction * 100))% complete")
    }
) {
    process(person)
}
```

## Performance Characteristics

| File Size | Memory Usage | Approach |
|-----------|--------------|----------|
| < 100 MB  | ~File size   | Sync decode |
| 100 MB - 1 GB | < 50 MB | Streaming |
| > 1 GB | < 50 MB | Streaming + backpressure |

## Topics

### Related

- ``CSVDecoder``
