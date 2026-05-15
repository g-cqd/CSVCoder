# Changelog

All notable changes to CSVCoder will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-05-15

First stable release.

### Encoding

- `CSVEncoder` with configurable delimiter, quoting, header emission,
  nil handling, date strategy, number strategy, bool strategy, key
  encoding strategy, and nested-type encoding strategy.
- Sync entry points: `encode(_:)`, `encodeToString(_:)`, `encode(_:to:URL)`.
- Streaming: `encodeToStream(_:)`, `encodeAsync(_:to:bufferSize:)`,
  `encodeBatched(_:to:batchSize:bufferSize:)`.
- Parallel: `encodeParallel(_:)`, `encodeParallelBatched(_:to:batchSize:)`.
- Helpers: `headers(for:sample:)`, `encodeRow(_:)`, `encodeToDictionary(_:)`.

### Decoding

- `CSVDecoder` with configurable parsing mode (strict / lenient),
  trimming, expected field count, has-headers, key decoding strategy,
  column / index mapping, date strategy, number strategy, bool strategy,
  and nested-type decoding strategy.
- Sync entry points: `decode([T].self, from: String / Data / URL)`.
- Streaming: `decodeStream(_:from:)`, `decodeBatched(_:from:batchSize:)`.
- Backpressure: `decodeWithBackpressure(_:from:memoryConfig:)`,
  `decodeBatchedWithBackpressure(_:from:memoryConfig:)`,
  `decodeWithProgress(_:from:progressHandler:)`.
- Parallel: `decodeParallel(_:from:parallelConfig:)`,
  `decodeParallelBatched(_:from:parallelConfig:)`.

### Macros

- `@CSVRow` generates `CodingKeys` (with `CaseIterable`),
  `typealias CSVCodingKeys = CodingKeys`, and conformances to
  `CSVRowDecodable`, `CSVRowEncodable`, and (when every stored property
  has a directly-supported type) `CSVDirectDecodable`.
- `@CSVColumn("name")` maps a property to a custom CSV header.
- Diagnostics for duplicate `@CSVColumn` names and orphan `@CSVColumn`
  on a struct without `@CSVRow`. Swift reserved-keyword property names
  are backtick-escaped automatically.

### Direct-decode fast path

`CSVDirectDecodable` bypasses `Codable`'s keyed-container indirection.
On `Decode 1M rows (simple)` (Apple M2 Pro, 5 iterations + 3 warmups)
the fast path measures 802 ms / ~1.25M rows/s versus 1638 ms /
~611K rows/s for the standard `Codable` path (≈2.04× speedup). Every
configuration option (trim, encoding, date/number strategies, nil
strategy, error locations) is honoured identically.

### Strategies & locale support

- Key encoding / decoding strategies: snake_case, kebab-case,
  SCREAMING_SNAKE_CASE, PascalCase, and `custom`.
  `convertToSnakeCase` follows `JSONEncoder._convertToSnakeCase` —
  `myURLProperty` → `my_url_property`.
- Number decoding: `standard`, `flexible` (strips currency / unit
  suffixes, accepts US/EU formats, rejects fractional values for
  integer types), `locale`, `parseStrategy`, `currency`, `localeAware`.
- Date decoding: `iso8601`, `formatted`, `flexible` (~20 common formats),
  `flexibleWithHint`, `localeAware`, `custom`.
- Bool decoding: `standard`, `flexible` (oui/non, ja/nein, …), `custom`.
- Nested types: `flatten(separator:)`, `json(maxBytes: Int = 1 << 20)`,
  `error`.

### Parsing

- RFC 4180-compliant parser with SIMD-accelerated structural scanning
  (64-byte vectors).
- Single `CSVRowStreamProducer` powers async, backpressure, and
  progress-reporting decode paths.
- Per-row metadata packed into one `[CSVRowView.Field]` allocation.
- Fused parse + validate + decode loop avoids materialising the full
  row list.
- Strict mode rejects unterminated quotes, quotes in unquoted fields,
  field-count mismatches, and invalid UTF-8.
- Lenient mode substitutes U+FFFD for invalid UTF-8 and still enforces
  `expectedFieldCount` when configured.

### Errors

- `CSVDecodingError` and `CSVEncodingError` carry `CSVLocation`
  (row / column / coding path) with intelligent suggestions for
  typical mistakes.

### Concurrency

- Swift 6.2 strict-concurrency clean; all public types are `Sendable`.
- `BackpressureController` cooperates with task cancellation via
  `withTaskCancellationHandler`.

### Platforms

- iOS 18+, macOS 15+, watchOS 11+, tvOS 18+, visionOS 2+.
- Swift 6.2 toolchain.
