# CSV Parsing Locale-Aware Migration Plan

## Status: Phase 1-3 Complete

## Overview

Migrate from hardcoded parsing logic to Foundation's locale-aware FormatStyle/ParseStrategy APIs, eliminating ~240 lines of duplicated code between CSVCoder and LotoFuel.

---

## Phase 1: CSVCoder Locale Enhancement

### 1.1 NumberDecodingStrategy Extensions
- [x] Add `.parseStrategy(locale:)` - Uses Foundation FormatStyle.ParseStrategy
- [x] Add `.currency(code:)` - Currency-aware with automatic symbol stripping
- [x] Replace hardcoded currency list with `Locale.allCurrencySymbols`

### 1.2 DateDecodingStrategy Extensions
- [x] Add `.localeAware(locale:style:)` - Uses Date.ParseStrategy
- [x] Keep `.flexible` for backwards compat (format chain still useful for ISO formats)

### 1.3 Tests
- [x] Test parseStrategy with various locales (US, DE)
- [x] Test currency parsing with symbol stripping
- [x] Test localeAware date parsing (US, UK formats)

---

## Phase 2: LotoFuel Migration

### 2.1 CSVDataNormalizer Assessment
- [x] Analyzed usage: CSVParser uses it for pre-decode validation (odometer sequence, duplicates)
- [x] Decision: Keep CSVDataNormalizer for direct string parsing use cases
- [x] Rationale: CSVCoder strategies work at decode time; normalizer works pre-decode
- [ ] Future: Consider exposing LocaleUtilities for direct use (lower priority)

### 2.2 FuelioCSVReader Assessment
- [x] Analyzed: Fuelio has well-defined format (yyyy-MM-dd dates, standard numbers)
- [x] Decision: Keep current `.flexible`/`.formatted` strategies - appropriate for fixed format
- [x] Rationale: New locale-aware strategies benefit unknown/varying formats, not fixed ones

---

## Phase 3: CSVCoder File Organization

### 3.1 Current File Analysis

| File | Lines | Bytes | Notes |
|------|-------|-------|-------|
| `CSVRowDecoder.swift` | 875 | 35KB | Largest source file |
| `CSVDecoder+Parallel.swift` | 559 | 20KB | Well-scoped extension |
| `CSVDecoder.swift` | 504 | 20KB | Config + strategies + decoder |
| `CSVSingleValueDecoder.swift` | 464 | 17KB | Moderate complexity |
| `CSVDecoderTests.swift` | 2079 | 67KB | **Priority: split tests** |
| `CSVEncoderTests.swift` | 957 | 32KB | Lower priority |

### 3.2 Source File Strategy

**Recommended: Minimal restructuring**

After analysis, the existing source structure is already well-organized:
- Extensions (`+Parallel`, `+Streaming`, `+Backpressure`) are properly split
- `LocaleUtilities.swift` was added in Phase 1 for parsing utilities
- `CSVRowDecoder.swift` has tightly coupled parsing logic (not worth splitting)

**Optional future refinements:**
- [ ] Extract `CSVDecoderConfiguration.swift` (lines 14-93 of CSVDecoder.swift) - ~80 lines
- [ ] Extract `CSVDecodingStrategies.swift` (strategy enums) - ~115 lines
- [ ] Consider making `LocaleUtilities` public for external consumption

### 3.3 Test File Splitting (Recommended)

Split `CSVDecoderTests.swift` (2079 lines, 100+ tests) into focused suites:

| New File | Test Groups | Lines |
|----------|-------------|-------|
| `CSVDecoderBasicTests.swift` | Simple decode, delimiters, types (UUID, URL, Decimal) | ~200 |
| `CSVDecoderStrategyTests.swift` | Date/number/boolean strategies | ~230 |
| `CSVDecoderRFC4180Tests.swift` | Quoted fields, line endings, strict/lenient mode | ~350 |
| `CSVDecoderStreamingTests.swift` | Stream decode, async collect | ~160 |
| `CSVDecoderParallelTests.swift` | SIMD scanner, parallel decode, batched | ~250 |
| `CSVDecoderKeyMappingTests.swift` | Key strategies, column mapping, index mapping | ~200 |
| `CSVDecoderErrorTests.swift` | Error locations, suggestions, diagnostics | ~150 |
| `CSVDecoderNestedTests.swift` | Nested decoding strategies | ~100 |
| `LocaleAwareDecodingTests.swift` | Already separate (Phase 1) | 295 |

**Benefits:**
- Faster test runs when working on specific features
- Clearer ownership and maintenance
- Easier CI parallelization

### 3.4 Implementation Priority

1. **High**: Test file splitting (CSVDecoderTests.swift → 8 files)
2. **Medium**: Extract configuration/strategies from CSVDecoder.swift
3. **Low**: Make LocaleUtilities public API

---

## Implementation Log

### Entry 1: 2024-12-28
- Created migration plan
- Starting Phase 1.1: NumberDecodingStrategy extensions

### Entry 2: 2024-12-28
- ✅ Added `NumberDecodingStrategy.parseStrategy(locale:)`
- ✅ Added `NumberDecodingStrategy.currency(code:locale:)`
- ✅ Added `DateDecodingStrategy.localeAware(locale:style:)`
- ✅ Created `LocaleUtilities.swift` with:
  - `allCurrencySymbols` from system locales (180+ symbols)
  - `stripCurrencyAndUnits()` for preprocessing
  - `parseDouble()`, `parseDecimal()`, `parseDate()` using FormatStyle.ParseStrategy
- ✅ Updated `CSVSingleValueDecoder.swift` and `CSVRowDecoder.swift` to use new strategies
- ✅ Added 13 new tests in `LocaleAwareDecodingTests.swift`
- ✅ All 181 tests passing
- Phase 1 complete

### Entry 3: 2024-12-28
- ✅ Phase 2 complete: LotoFuel assessment done
  - CSVDataNormalizer kept for pre-decode validation
  - FuelioCSVReader kept with current strategies (fixed Fuelio format)
  - LotoFuel updated to CSVCoder revision 9fc5ff7
  - All 24 LotoFuelServices tests passing
- ✅ Phase 3 planning complete:
  - Analyzed all source files (6.9K lines total)
  - Analyzed test files (3.3K lines, CSVDecoderTests.swift = 2K lines)
  - Recommended test file splitting over source splitting
  - Source structure already well-organized with +Parallel, +Streaming extensions

### Entry 4: 2024-12-28
- ✅ Phase 3 test file splitting implemented:
  - Split CSVDecoderTests.swift (2079 lines) into 8 focused test files:
    - CSVDecoderBasicTests.swift (~200 lines) - Simple decoding, types
    - CSVDecoderStrategyTests.swift (~200 lines) - Date/number/boolean strategies
    - CSVDecoderRFC4180Tests.swift (~320 lines) - Quoted fields, strict/lenient mode
    - CSVDecoderStreamingTests.swift (~230 lines) - Async/stream decoding
    - CSVDecoderParallelTests.swift (~340 lines) - SIMD, parallel decode
    - CSVDecoderKeyMappingTests.swift (~330 lines) - Key strategies, index mapping
    - CSVDecoderErrorTests.swift (~170 lines) - Error diagnostics
    - CSVDecoderNestedTests.swift (~160 lines) - Nested decoding strategies
  - All 181 tests pass
  - Total test files: 10 (8 decoder + 1 encoder + 1 locale-aware)

### Entry 5: 2024-12-28
- ✅ Phase 3 source file organization implemented:
  - Reorganized flat source layout into logical directories:
    ```
    Sources/CSVCoder/
    ├── Core/          - CSVDecoder, CSVEncoder, errors (4 files)
    ├── Decoder/       - Row/SingleValue decoders (2 files)
    ├── Encoder/       - Row/SingleValue encoders, writers (4 files)
    ├── Parsing/       - Parser, SIMD scanner, streaming (5 files)
    ├── Extensions/    - Parallel, streaming, backpressure (5 files)
    ├── Utilities/     - Locale, macros, indexed codable (4 files)
    └── CSVCoder.docc/ - Documentation
    ```
  - All 181 CSVCoder tests pass
  - LotoFuel build succeeds
  - 24 LotoFuelServices tests pass
  - 794/795 LotoFuel tests pass (1 pre-existing failure unrelated to reorganization)

---

## Code Locations

| File | Purpose |
|------|---------|
| `/tmp/CSVCoder/Sources/CSVCoder/CSVDecoder.swift` | Strategy enums |
| `/tmp/CSVCoder/Sources/CSVCoder/CSVSingleValueDecoder.swift` | Parsing implementation |
| `LotoFuel/.../CSVDataNormalizer.swift` | To be simplified |
| `LotoFuel/.../FuelioCSVReader.swift` | To use new strategies |

---

## API Changes

### New NumberDecodingStrategy Cases
```swift
case parseStrategy(locale: Locale = .autoupdatingCurrent)
case currency(code: String? = nil, locale: Locale = .autoupdatingCurrent)
```

### New DateDecodingStrategy Cases
```swift
case localeAware(locale: Locale = .autoupdatingCurrent, style: Date.FormatStyle.DateStyle = .numeric)
```

---

## Metrics

| Metric | Before | Target |
|--------|--------|--------|
| Hardcoded currency symbols | 15 | 0 (Locale API) |
| Hardcoded date formats | 26 | 0 (ParseStrategy) |
| Duplicated lines | ~240 | 0 |
| Locale coverage | ~10 | 300+ |
