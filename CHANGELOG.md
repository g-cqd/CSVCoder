# Changelog

All notable changes to CSVCoder will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Audit follow-up (2026-05-14)

#### Breaking changes
- `CSVDecoder.NestedTypeDecodingStrategy.json` and
  `CSVEncoder.NestedTypeEncodingStrategy.json` now take an associated
  `maxBytes: Int = 1 << 20` parameter and reject cells / payloads larger
  than the configured budget.  Existing `.json` call sites need to be
  written as `.json()` (default 1 MiB cap).
- `.codable` nested strategy is deprecated as a renamed alias for `.json`
  and will be removed in a future release.
- The acronym-aware `convertToSnakeCase` algorithm now matches
  `JSONEncoder._convertToSnakeCase`: `myURLProperty` becomes
  `my_url_property` instead of `my_u_r_l_property`.  The inverse
  `convertFromSnakeCase` mirrors `JSONDecoder` semantics.
- `expectedFieldCount` is now validated in both lenient and strict
  parsing modes (it expresses caller intent, not parser leniency).
- `NumberDecodingStrategy.parseStrategy` and `.currency` now default to
  `Locale.current` (snapshot) instead of `Locale.autoupdatingCurrent`.
- `CSVDecoder.NestedTypeDecodingStrategy.codable` deprecated; use `.json`.

#### Safety & correctness
- `CSVIndexedEncodable` is now honoured on every encode entry point
  (parallel, streaming, batched, single-row).  Headerless encode order
  matches the macro's `CodingKeys` declaration order.
- `BackpressureController.waitForSpace()` cooperates with task
  cancellation via `withTaskCancellationHandler`, closing the
  continuation-leak window.
- `URL` decoding uses the strict
  `URL(string:encodingInvalidCharacters: false)` overload, rejecting
  malformed URLs instead of silently percent-encoding.
- Strategy-aware integer parsing: every typed integer overload now
  routes through `CSVValueParser.parseInt64(_:strategy:)`, so
  `.flexible` correctly strips currency / grouping separators and
  rejects fractional values (`"1.5"` → error, not `1`).
- Strict mode now rejects invalid UTF-8 byte sequences instead of
  silently substituting U+FFFD.
- Macro emits diagnostics for duplicate `@CSVColumn` names and for
  orphan `@CSVColumn` usage on a struct without `@CSVIndexed`.  Property
  names that are Swift reserved keywords are backtick-escaped.

#### Performance
- Replaced the dual parser (`CSVParser` + `StreamingCSVParser`) with a
  single SIMD-accelerated path; the new `CSVRowStreamProducer` powers
  all async / backpressure / progress streams.
- Packed per-row metadata into a single `[CSVRowView.Field]` allocation
  instead of four parallel arrays.
- Fused parse + validate + decode in `CSVDecoder.decodeRowsFromBytes`,
  eliminating the `[CSVRowView]` materialisation pass.
- `LocaleUtilities.allCurrencySymbols` is now a hand-curated set of ~50
  symbols / ISO codes, saving 10–45 ms of cold-start ICU lookups.
- Number `.locale(_:)` formatting / parsing now uses `FormatStyle`
  (Sendable, no caching required); `NumberFormatter` cache removed.

### Renames

- `@CSVIndexed` macro renamed to `@CSVRow`. Old name kept as a
  `@available(*, deprecated)` alias for one release cycle.
- `CSVIndexedDecodable` → `CSVRowDecodable`
- `CSVIndexedEncodable` → `CSVRowEncodable`
- `CSVIndexedCodable` → `CSVRowCodable`
- `CSVIndexedBase` → `CSVRowConvertible`
- `_CSVIndexedMarker` → `_CSVRowMarker`
- All old spellings remain as deprecated `typealias` so existing code
  compiles with a single rename warning per declaration site.

### Follow-up (post-audit perf + safety)

#### Performance
- Reverted the audit's `OrderedDictionary` adoption in
  `CSVEncodingStorage` back to a `Dictionary + [String]` pair (still
  under `Mutex` for thread-safety). `OrderedDictionary` measured 3-6%
  slower for the storage's insert-once / read-once access pattern.
  `swift-collections` is no longer a dependency.

#### Notes
- A byte-level whitespace trim (`Span<UInt8>` based) was prototyped in
  `CSVRowView.string(at:encoding:trim:)` for a ~17% decoder speedup on
  simple-record benchmarks, then **reverted**. The custom trim set
  `0x09..=0x0D + 0x20` diverged from Foundation's
  `CharacterSet.whitespaces` (Zs + `0x09`) in two directions: it
  stripped legitimate LF/CR/VT/FF from quoted fields, and missed
  Unicode space separators. The behavioural divergence between this
  path (view source) and the existing dictionary-source path made the
  same input produce different trims depending on which decode entry
  point was called — a correctness bug outweighing the throughput win.
  The decoder again uses Foundation's `.trimmingCharacters(in: .whitespaces)`
  uniformly.

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
