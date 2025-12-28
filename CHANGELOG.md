# Changelog

All notable changes to CSVCoder will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

#### Multi-Encoding Support
- Full support for ASCII-compatible encodings (ISO-8859-1, Windows-1252, macOS Roman)
- Automatic transcoding for non-ASCII encodings (UTF-16, UTF-16LE/BE, UTF-32)
- BOM (Byte Order Mark) detection for UTF-8, UTF-16, and UTF-32
- Zero-copy parsing preserved for ASCII-compatible encodings
- `CSVUtilities.isASCIICompatible(_:)` for encoding classification
- `CSVUtilities.transcodeToUTF8(_:from:)` for encoding conversion
- `CSVUtilities.detectBOM(in:)` for multi-format BOM detection

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
