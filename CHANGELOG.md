# Changelog

All notable changes to CSVCoder will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

#### Safety & Error Handling
- Replaced all 14 `fatalError()` calls with thrown `CSVEncodingError` using poison-pill containers
- Bounds check in `CSVRowView.getBytes(at:)` prevents array out-of-bounds crashes
- `BackpressureController.cancelAllWaiters()` properly resumes all pending continuations on stream termination
- `CSVEncodingStorage.snapshot()` provides atomic key+value reads under single lock
- `includesTrailingNewline` configuration option for consistent trailing newline behavior
- Delimiter validation: `precondition` enforces ASCII-only delimiters at configuration time

#### Correctness
- `encodeIfPresent(Bool?)` now respects `boolEncodingStrategy` (was hardcoded to `1`/`0`)
- `encodeIfPresent(Double?/Float?)` now respects `numberEncodingStrategy` (was using `String($0)`)
- `CSVSingleValueEncodingContainer.encode(Bool)` now respects `boolEncodingStrategy`

#### Performance
- Cached `ISO8601DateFormatter`, `DateFormatter`, and `NumberFormatter` via `FormatterCache`
- O(n) key strategy conversion using `[Character]` array (was O(n²) string concatenation)
- Batch byte appends in `AsyncCSVWriter` via `append(contentsOf:)` (was byte-by-byte)
- Centralized date decoding in `CSVValueParser.parseDate()` eliminates ~80 lines of duplication
- Removed dead `#available(iOS 15, ...)` checks (minimum target is iOS 18)

#### Test Coverage
- 22 new tests for code review fixes (`CSVCodeReviewFixTests`)
- 3 cancellation tests for streaming/backpressure (`CSVDecoderCancellationTests`)
- 3 concurrency stress tests (`CSVConcurrencyStressTests`)
- Strengthened parallel performance test assertions

### Changed
- Removed unused `encoding: String.Encoding` property from `CSVEncoder.Configuration` (always UTF-8)
- Key encoding strategies (`convertToSnakeCase`, `convertToKebabCase`, `convertToScreamingSnakeCase`) share a single `convertCamelCase(_:separator:uppercase:)` implementation

#### Streaming & Memory Efficiency
- `CSVDecoder.decode(_:from: URL)` - Stream decode from files with O(1) memory
- `CSVDecoder.decode(_:from: Data)` - Stream decode from Data
- `MemoryMappedReader` - Zero-copy file access via mmap
- `StreamingCSVParser` - AsyncSequence-based row parser with UTF-8 byte parsing
- Automatic UTF-8 BOM detection and handling

#### Parallel Decoding
- `decodeParallel(_:from:parallelConfig:)` - Multi-core CSV decoding
- `decodeParallelBatched(_:from:parallelConfig:)` - Streaming parallel batches
- `ParallelConfiguration` - Control parallelism, chunk size, ordering
- `SIMDScanner` - 64-byte SIMD vector scanning (~8x faster delimiter detection)

#### Backpressure & Progress
- `decodeWithBackpressure(_:from:memoryConfig:)` - Memory-limited streaming
- `decodeBatchedWithBackpressure(_:from:memoryConfig:)` - Batched output with limits
- `decodeWithProgress(_:from:progressHandler:)` - Progress reporting during decode
- `MemoryLimitConfiguration` - Configure memory budget and water marks

#### Key Decoding Strategies
- `KeyDecodingStrategy.convertFromSnakeCase` - `first_name` → `firstName`
- `KeyDecodingStrategy.convertFromKebabCase` - `first-name` → `firstName`
- `KeyDecodingStrategy.convertFromScreamingSnakeCase` - `FIRST_NAME` → `firstName`
- `KeyDecodingStrategy.convertFromPascalCase` - `FirstName` → `firstName`
- `KeyDecodingStrategy.custom` - Custom transformation closure

#### Column & Index Mapping
- `columnMapping: [String: String]` - Explicit header-to-property mapping
- `indexMapping: [Int: String]` - Decode headerless CSV by column index

#### Flexible Decoding Strategies
- `DateDecodingStrategy.flexible` - Auto-detect from 20+ date formats
- `DateDecodingStrategy.flexibleWithHint` - Try preferred format first
- `NumberDecodingStrategy.flexible` - Parse US/EU formats, strip currency
- `NumberDecodingStrategy.locale` - Use specific locale for parsing
- `BoolDecodingStrategy.flexible` - International boolean values (oui/non, ja/nein, etc.)
- `BoolDecodingStrategy.custom` - Custom true/false value sets

#### Error Diagnostics
- `CSVLocation` - Row, column, and coding path information
- Enhanced `CSVDecodingError` with location-aware variants
- Detailed error messages with row/column context

#### Documentation
- DocC documentation catalog with articles
- Getting Started guide
- Streaming Decoding article
- Parallel Decoding article

### Changed
- `CSVParser` rewritten for robust RFC 4180 compliance
- Improved CRLF handling with explicit Unicode scalar comparisons
- Parser now handles all line ending styles: LF, CRLF, lone CR

### Fixed
- Unterminated quote detection with line/column information
- Quoted fields containing CRLF now parse correctly
- Empty quoted fields handled properly
- `trimWhitespace` configuration now consistently applied to all field types
  - Previously, numeric fields (Int, Double, etc.) would fail parsing with whitespace
  - Boolean decoding now respects configuration instead of always trimming
  - Header extraction now applies trimWhitespace consistently across all decode paths

## [1.1.0] - 2025-12-27

### Added
- Flexible decoding strategies for dates, numbers, and booleans
- `nonisolated` annotations for Swift 6.2 Approachable Concurrency compatibility

## [1.0.0] - 2025-12-27

### Added
- Initial release
- `CSVEncoder` with configurable delimiters, date strategies, nil handling
- `CSVDecoder` with header parsing and type-safe decoding
- Support for `Decimal`, `UUID`, `URL` types
- RFC 4180-compliant field quoting and escaping
- Swift 6 strict concurrency with `Sendable` conformance
- Platform support: iOS 18+, macOS 15+, watchOS 11+, tvOS 18+, visionOS 2+
