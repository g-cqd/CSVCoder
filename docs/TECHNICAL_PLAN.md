# CSVCoder Technical Implementation Plan

## Phase 1: Core Reliability

### 1.1 RFC 4180-Compliant Quoting/Escaping (Encoding)

**RFC 4180 Rules**:
1. Fields containing line breaks, double quotes, or commas must be enclosed in double quotes
2. Double quotes within a field must be escaped by preceding with another double quote (`""`)
3. Spaces are significant and should not be trimmed
4. Each record should be on a separate line, ending with CRLF (though LF is commonly accepted)

**Files to Modify**:
- `CSVEncoder.swift` - Add quoting configuration
- `CSVRowEncoder.swift` - Implement field escaping logic
- `CSVSingleValueEncoder.swift` - Handle special characters in values

**Implementation**:
```swift
// Quoting strategy options
enum QuotingStrategy {
    case automatic      // Quote only when necessary (default)
    case always         // Always quote all fields
    case never          // Never quote (user responsibility)
}

// Field escaping function
func escapeField(_ value: String, delimiter: Character) -> String {
    let needsQuoting = value.contains("\"") ||
                       value.contains(delimiter) ||
                       value.contains("\n") ||
                       value.contains("\r")

    if needsQuoting {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
    return value
}
```

### 1.2 Robust Parsing/Unquoting (Decoding)

**Files to Modify**:
- `CSVParser.swift` - Core parsing logic
- `CSVDecoder.swift` - Configuration for parsing behavior

**Implementation Considerations**:
- State machine for parsing quoted fields
- Handle escaped quotes (`""` → `"`)
- Handle newlines within quoted fields
- Graceful handling of malformed CSV (missing closing quotes)

**Parsing States**:
```
START → UNQUOTED_FIELD | QUOTED_FIELD
UNQUOTED_FIELD → read until delimiter/newline
QUOTED_FIELD → read until closing quote (handle "" escapes)
```

### 1.3 Edge Case Tests

**Test Categories**:
- Fields with embedded delimiters
- Fields with embedded newlines
- Fields with embedded quotes
- Mixed quoting scenarios
- Empty fields
- Single field rows
- Whitespace handling
- Malformed CSV error handling

---

## Phase 2: Flexibility & Real-World Usability

### 2.1 Custom Coding Keys & Column Mapping

**Goal**: Allow header names that differ from property names

**Approach**:
- Leverage existing `CodingKey` string values
- Add optional `headerMapping: [String: String]` configuration

### 2.2 Header-less & Index-Based Decoding

**Options to Add**:
```swift
enum HeaderMode {
    case firstRow           // Default: first row is header
    case none               // No header, use property order
    case explicit([String]) // Provide headers externally
}
```

### 2.3 Boolean/Number Strategies

**Boolean Strategies**:
```swift
enum BoolDecodingStrategy {
    case numeric           // 0/1
    case textual           // true/false
    case yesNo            // yes/no
    case custom([String], [String]) // (trueValues, falseValues)
}
```

**Number Strategies**:
- Locale-aware decimal separators
- Scientific notation handling
- Thousand separators

### 2.4 Rich Error Reporting

**Enhanced Error Types**:
```swift
struct CSVParsingError: Error {
    let message: String
    let line: Int
    let column: Int
    let context: String  // Snippet of problematic data
}
```

---

## Phase 3: Polish & Professionalization

### 3.1 Performance Optimization

**Areas to Profile**:
- String allocation during parsing
- Regex usage (if any) vs manual parsing
- Memory usage for large files

**Potential Optimizations**:
- Use `Substring` instead of `String` where possible
- Pre-allocate result arrays with estimated capacity
- Consider streaming parsing for large files

### 3.2 DocC Documentation

**Documentation Structure**:
- Getting Started guide
- API reference for all public types
- Code examples
- Migration guide (if API changes)

### 3.3 Release & CHANGELOG

**CHANGELOG Format**:
```markdown
# Changelog

## [1.1.0] - YYYY-MM-DD
### Added
- RFC 4180 compliant quoting/escaping
- Rich error reporting with line/column info
- Header-less decoding mode
### Fixed
- (any bugs fixed)
```

### 3.4 GitHub Actions CI

**Workflow Configuration**:
- Build on macOS (primary)
- Test on all supported platforms
- Swift version matrix (6.0)

---

## Phase 4: Advanced Features

### 4.1 Async/Streaming API

**Design**:
```swift
func decode<T: Decodable>(
    _ type: T.Type,
    from url: URL
) -> AsyncThrowingStream<T, Error>
```

### 4.2 BOM Handling

- Detect and skip UTF-8 BOM (`0xEF 0xBB 0xBF`)
- Support other BOMs (UTF-16 LE/BE)

### 4.3 Benchmark Suite

- Row count scaling (100, 1K, 10K, 100K, 1M rows)
- Column count scaling
- Field size variations
- Comparison with alternative libraries

---

## Testing Strategy

### Unit Tests
- Each strategy option
- Each configuration combination
- Error conditions

### Integration Tests
- Round-trip encoding/decoding
- Real-world CSV samples
- Large file handling

### Edge Case Matrix

| Scenario | Encoding | Decoding |
|----------|----------|----------|
| Empty string | `""` | `` |
| Contains comma | `"a,b"` | `a,b` |
| Contains quote | `"a""b"` | `a"b` |
| Contains newline | `"a\nb"` | multiline |
| Leading/trailing spaces | ` a ` | preserve |
| Unicode | pass-through | pass-through |
