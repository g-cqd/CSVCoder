# Error Handling

Decoding errors carry row, column, and coding-path information so you can
surface actionable diagnostics to your users.

## Overview

``CSVDecodingError`` is the typed error thrown by every `CSVDecoder`
operation.  Each case includes a ``CSVLocation`` describing where in the
source the problem occurred, and most cases include an automatically
generated suggestion based on the closest matching column name.

## Cases

### `parsingError(_:line:column:)`

Low-level syntactic problem — invalid UTF-8 byte sequence, unterminated
quoted field, lone CR / CRLF inconsistency, mismatched
``CSVDecoder/Configuration-swift.struct/expectedFieldCount``, or a JSON
cell exceeding the configured byte budget.  Line and column reflect the
1-based location in the source, when known.

### `keyNotFound(_:location:)`

The decoder asked for a key the row does not contain.  Most often caused
by a typo in the model's property name or a header-conversion strategy
that didn't apply (`first_name` vs `firstName`).  The
``CSVLocation/availableKeys`` array carries the actual headers the
decoder saw, and ``CSVDecodingError/suggestion`` runs a Levenshtein
search over them.

### `typeMismatch(expected:actual:location:)`

The cell held a string value that couldn't be parsed as the expected
type.  Common culprits: a leading currency symbol with the default
``CSVDecoder/NumberDecodingStrategy/standard`` strategy, an ISO-8601
timestamp where the model expects a `Date` and the decoder has no date
strategy configured, or an empty cell decoded as a non-optional `Int`.

### `unsupportedType(_:)`

The model uses a feature CSV cannot represent: unkeyed containers
(arrays), nested types without
``CSVDecoder/Configuration-swift.struct/nestedTypeDecodingStrategy``, or
single-value root containers.  Either reshape the model or pick an
appropriate nested strategy.

## Surfacing helpful diagnostics

```swift
do {
    let people = try decoder.decode([Person].self, from: data)
} catch let error as CSVDecodingError {
    print(error.localizedDescription)
    if let suggestion = error.suggestion {
        print("Hint:", suggestion)
    }
    if let location = error.location {
        print("Row \(location.row ?? -1), column \(location.column ?? \"?\")")
    }
}
```

`suggestion` powers helpers like “Did you mean `firstName`?” for
`keyNotFound`, and “Did you mean to set
`numberDecodingStrategy: .flexible`?” for currency-laden `typeMismatch`
cases.

## Topics

### Error model

- ``CSVDecodingError``
- ``CSVLocation``

### Related configuration

- ``CSVDecoder/Configuration-swift.struct/parsingMode``
- ``CSVDecoder/Configuration-swift.struct/expectedFieldCount``
- ``CSVDecoder/NestedTypeDecodingStrategy``
