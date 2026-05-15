# Locale-Aware Parsing

Pick the right number / date strategy for the CSV your users actually
hand you.

## Overview

CSVCoder ships four progressively more powerful number-decoding strategies
and three date strategies for non-standard input.  Use this article as a
cookbook to choose between them.

## Number strategies

| Strategy | Use when | Cost |
|----------|----------|------|
| ``CSVDecoder/NumberDecodingStrategy/standard`` | Input is well-formed Swift-style numbers. | Cheapest — direct `Double(value)` / `Int64(value)`. |
| ``CSVDecoder/NumberDecodingStrategy/flexible`` | Input mixes US `1,234.56` and EU `1.234,56`, may carry currency. | One heuristic pass over the string + currency strip. |
| ``CSVDecoder/NumberDecodingStrategy/parseStrategy(locale:)`` | Input always uses a specific locale's separators. | Foundation `FormatStyle.ParseStrategy` (ICU). |
| ``CSVDecoder/NumberDecodingStrategy/currency(code:locale:)`` | Each cell is a monetary value with a leading or trailing symbol. | Symbol strip + locale parse. |

### Choosing between `.flexible` and `.parseStrategy`

Pick ``CSVDecoder/NumberDecodingStrategy/flexible`` when the file mixes
multiple regional formats (e.g. exported by Excel on different machines).
Pick ``CSVDecoder/NumberDecodingStrategy/parseStrategy(locale:)`` when the
locale is fixed and you want strict validation — `parseStrategy` rejects
mismatched separators outright.

### Choosing between `.flexible` and `.currency`

Both strip a currency symbol before parsing.  Use
``CSVDecoder/NumberDecodingStrategy/currency(code:locale:)`` when each cell
*must* carry a currency marker — it expresses intent, and you can pin the
expected currency code for downstream validation.  Use
``CSVDecoder/NumberDecodingStrategy/flexible`` when the symbol is
opportunistic ("sometimes the user pastes a `€`, sometimes they don't").

```swift
// Flexible — accepts "$1,234.56", "1.234,56", "1234"
let flexConfig = CSVDecoder.Configuration(numberDecodingStrategy: .flexible)

// Currency-strict — must be a USD value
let usdConfig = CSVDecoder.Configuration(
    numberDecodingStrategy: .currency(code: "USD", locale: Locale(identifier: "en_US"))
)
```

## Date strategies

| Strategy | Use when |
|----------|----------|
| ``CSVDecoder/DateDecodingStrategy/iso8601`` | All dates are ISO-8601. |
| ``CSVDecoder/DateDecodingStrategy/formatted(_:)`` | Single deterministic format string (POSIX locale). |
| ``CSVDecoder/DateDecodingStrategy/flexible`` | Mix of 20+ common patterns. |
| ``CSVDecoder/DateDecodingStrategy/flexibleWithHint(preferred:)`` | One format dominates; others are fallback. |
| ``CSVDecoder/DateDecodingStrategy/localeAware(locale:style:)`` | Date format depends on user locale (12/31 vs 31/12). |

## Integer parsing under flexible strategies

Every integer overload (`Int`, `Int8`, ..., `UInt64`) routes through
the same strategy as floating-point decoding.  `Int(value)` with
``CSVDecoder/NumberDecodingStrategy/flexible`` strips currency symbols
and grouping separators, and rejects fractional values (`"1.5"` does
not silently become `1`).

```swift
struct Row: Codable { let count: Int }
let config = CSVDecoder.Configuration(numberDecodingStrategy: .flexible)
let decoder = CSVDecoder(configuration: config)
let rows = try decoder.decode([Row].self, from: "count\n\"1,234\"")
// rows[0].count == 1234
```

## Topics

### Strategies

- ``CSVDecoder/NumberDecodingStrategy``
- ``CSVDecoder/DateDecodingStrategy``
- ``CSVDecoder/BoolDecodingStrategy``
- ``CSVDecoder/NilDecodingStrategy``
