# Using CSVCoder Macros

Eliminate boilerplate for headerless CSV with Swift macros.

## Overview

CSVCoder provides macros to automatically generate `CodingKeys` and protocol conformance for index-based CSV decoding.

## @CSVRow Macro

Apply `@CSVRow` to your type to enable automatic column mapping:

```swift
@CSVRow
struct Person: Codable {
    let name: String
    let age: Int
    let score: Double
}
```

The macro generates:
- `CodingKeys` enum based on property order
- `CSVCodingKeys` typealias
- `CSVRowDecodable` conformance

## Decode Headerless CSV

With `@CSVRow`, columns are mapped by position:

```swift
let csv = """
Alice,30,95.5
Bob,25,88.0
"""

let config = CSVDecoder.Configuration(hasHeaders: false)
let decoder = CSVDecoder(configuration: config)
let people = try decoder.decode([Person].self, from: csv)
// Column 0 → name, Column 1 → age, Column 2 → score
```

## @CSVColumn for Custom Names

Map properties to different header names:

```swift
@CSVRow
struct Product: Codable {
    let id: Int

    @CSVColumn("product_name")
    let name: String

    @CSVColumn("unit_price")
    let price: Double
}
```

## Manual CSVRowDecodable

For more control, conform manually:

```swift
struct Person: CSVRowDecodable {
    let name: String
    let age: Int
    let score: Double

    enum CodingKeys: String, CodingKey, CaseIterable {
        case name, age, score  // Order defines column mapping
    }

    typealias CSVCodingKeys = CodingKeys
}
```

## Topics

### Related

- ``CSVRowDecodable``
- ``CSVDecoder``
