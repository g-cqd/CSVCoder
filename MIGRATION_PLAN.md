# CSV Parsing Locale-Aware Migration Plan

## Status: Phase 1 Complete, Phase 2 In Progress

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

### 2.1 CSVDataNormalizer Simplification
- [ ] Remove `parseDouble()` - delegate to CSVCoder
- [ ] Remove `parseDate()` - delegate to CSVCoder
- [ ] Keep `parseBool()` only if domain-specific values needed
- [ ] Keep unit conversion methods (domain logic)

### 2.2 FuelioCSVReader Update
- [ ] Use new `.parseStrategy` or `.currency` strategy
- [ ] Use new `.localeAware` date strategy

---

## Phase 3: CSVCoder File Organization

### 3.1 Source File Splitting
Split large files into focused, single-responsibility modules:

| Current File | Split Into |
|--------------|------------|
| `CSVDecoder.swift` (500+ lines) | `CSVDecoder.swift` (core), `CSVDecoderConfiguration.swift`, `CSVDecodingStrategies.swift` |
| `CSVSingleValueDecoder.swift` (450+ lines) | `CSVSingleValueDecoder.swift`, `NumberParsing.swift`, `DateParsing.swift` |
| `CSVRowDecoder.swift` (700+ lines) | `CSVRowDecoder.swift`, `CSVKeyedDecodingContainer.swift` |

### 3.2 Test File Splitting
| Current File | Split Into |
|--------------|------------|
| `CSVDecoderTests.swift` (2000+ lines) | `CSVDecoderBasicTests.swift`, `CSVDecoderStrategyTests.swift`, `CSVDecoderEdgeCaseTests.swift`, `CSVDecoderStreamingTests.swift` |
| `CSVEncoderTests.swift` | Similar split by functionality |

### 3.3 Naming Conventions
- Source: `CSV<Component>.swift` or `<Component>+CSV.swift` for extensions
- Tests: `<Component>Tests.swift` matching source file names

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
- Phase 1 complete, starting Phase 2

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
