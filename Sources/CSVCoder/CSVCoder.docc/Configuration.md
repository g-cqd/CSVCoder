# Configuration Cookbook

Combine column resolution strategies to handle the CSV files you actually
have, not the ones you wish you had.

## Overview

`CSVDecoder` resolves the column-to-property mapping using four overlapping
mechanisms: ``CSVDecoder/Configuration-swift.struct/indexMapping``,
``CSVDecoder/Configuration-swift.struct/hasHeaders`` combined with
``CSVDecoder/Configuration-swift.struct/keyDecodingStrategy``,
``CSVDecoder/Configuration-swift.struct/columnMapping``, and runtime
detection of ``CSVIndexedDecodable``.

Understanding the precedence order lets you mix-and-match without surprises.

## Precedence

The decoder picks the first rule that applies:

1. ``CSVDecoder/Configuration-swift.struct/indexMapping`` — explicit
   `[Int: String]` overrides everything.
2. ``CSVDecoder/Configuration-swift.struct/hasHeaders`` is `true` — read the
   first row as headers and run them through
   ``CSVDecoder/Configuration-swift.struct/keyDecodingStrategy`` (and any
   ``CSVDecoder/Configuration-swift.struct/columnMapping`` overrides).
3. The decoded type conforms to ``CSVIndexedDecodable`` (typically via
   ``CSVIndexed()``) — use the type's declared `CodingKeys` order.
4. Generate `column0`, `column1`, … as last-resort names.

## Worked examples

### Headers with snake_case input

```swift
struct Person: Codable {
    let firstName: String
    let lastName: String
}

let config = CSVDecoder.Configuration(
    keyDecodingStrategy: .convertFromSnakeCase
)
let decoder = CSVDecoder(configuration: config)
let csv = "first_name,last_name\nAlice,Smith"
let people = try decoder.decode([Person].self, from: csv)
```

### Headers with a custom rename

```swift
let config = CSVDecoder.Configuration(
    columnMapping: ["First Name": "firstName", "Last Name": "lastName"]
)
```

`columnMapping` takes precedence per-column over `keyDecodingStrategy`, so you
can keep snake-case conversion for the rest of the file while overriding
the handful of awkward headers.

### Headerless input with `@CSVIndexed`

```swift
@CSVIndexed
struct Record: Codable {
    let id: Int
    @CSVColumn("price_usd") let priceUSD: Double
    let qty: Int
}

let config = CSVDecoder.Configuration(hasHeaders: false)
let decoder = CSVDecoder(configuration: config)
let csv = "1,9.99,2\n2,4.50,7"
let records = try decoder.decode([Record].self, from: csv)
```

The macro auto-generates `CodingKeys` from declaration order so column 0
binds to `id`, column 1 to `priceUSD`, column 2 to `qty`.

### Explicit index mapping (highest priority)

```swift
let config = CSVDecoder.Configuration(
    hasHeaders: false,
    indexMapping: [0: "name", 2: "score"] // column 1 ignored
)
```

`indexMapping` overrides everything else — useful when the upstream system
emits columns in a stable but arbitrary order and you only need a subset.

## Topics

### Related strategies

- ``CSVDecoder/KeyDecodingStrategy``
- ``CSVDecoder/Configuration-swift.struct/columnMapping``
- ``CSVDecoder/Configuration-swift.struct/indexMapping``
- ``CSVIndexedDecodable``
