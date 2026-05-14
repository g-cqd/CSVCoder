# CSVCoder Audit — 2026-05-14

**Scope.** Full review of `Sources/CSVCoder`, `Sources/CSVCoderMacros`, `Sources/CSVCoderBenchmarks`, and the test
targets. Performed against the README's announced feature set, Apple Foundation (macOS 15 / iOS 18 SDK) idioms, and
Swift 6.2 concurrency rules. Findings are graded by severity:

- **Critical** — broken feature, data corruption, security risk, or contract violation.
- **High** — incorrect behaviour for a documented configuration, or a serious perf regression vs claims.
- **Medium** — code quality, missed native API, duplication that will rot.
- **Low** — nit, style, documentation drift.

References to source use `path:line` so they navigate in any editor.

---

## 0. Executive summary

CSVCoder is a competent, RFC 4180-aware CSV codec with a clean public surface mirroring `JSONEncoder` /
`JSONDecoder`. The hot parsing path is well-engineered (SIMD64 + SWAR + scalar fallbacks, zero-copy
`CSVRowView`). Concurrency primitives are modern (actor `BackpressureController`, `Synchronization.Mutex`,
strict `Sendable`).

Three findings dominate everything else and should be fixed before any other polish:

1. **`CSVIndexedEncodable` is dead code.** The protocol is defined, the macro conforms to it, the
   README advertises it — but the encoder never reads `csvColumnOrder`. Headerless ordered encoding
   silently falls back to property-declaration order. (§4.1)
2. **Parallel encoder ignores `keyEncodingStrategy`.** All three `encodeParallel(_:…)` variants and
   `encodeParallelBatched(_:)` emit raw property names as headers; only the sync and async-sequence
   paths apply `transformKey`. This is a feature-regression that depends entirely on which entry
   point the user calls. (§4.2)
3. **Two divergent parser implementations.** `CSVParser` (SIMD-accelerated, zero-copy) is used by all
   sync / SIMD-streaming paths; `StreamingCSVParser` (byte-by-byte scalar, `[UInt8]` accumulator) is
   used by the back-pressure and progress streams. They have different field-count, quote-handling,
   and lone-CR behaviour — the same input may decode differently depending on which API the caller
   picks. (§5.1)

The remaining findings are isolated and not blocking.

---

## 1. Architecture overview

```
┌── Public API ─────────────────────────────────────────────────────────┐
│  CSVDecoder / CSVEncoder  (final, Sendable, Configuration value type) │
└──┬───────────────────────────────────────────────────────────────────┘
   │ sync                          async / streaming                parallel
   ▼                                ▼                                ▼
 decodeRowsFromBytes(…)        streamDecode(…)               decodeParallel(…)
   │  CSVParser (SIMD)            │ MemoryMappedReader            │ parseToStringRows
   │  → [CSVRowView]              │ CSVParser (SIMD)              │ → [[String]]
   │  → CSVRowDecoder            │ → CSVRowDecoder                │ → TaskGroup{ CSVRowDecoder }
   │                              │
   ▼                              ▼
 [T]                          AsyncThrowingStream<T>

 decodeWithBackpressure / decodeBatchedWithBackpressure / decodeWithProgress
   │ StreamingCSVParser (scalar, allocates [UInt8] per field)
   │ → StreamingRowProcessor<T>
   │ → AsyncThrowingStream<T>
```

The encoder mirrors this layout (`encode`, `encodeToString`, `encode(_:to:)`, `encode(asyncSequence,
to:)`, `encodeParallel(…)`, `encodeAsync(…)`, `encodeBatched(…)`, `encodeToStream(…)`).

Auxiliary types:

- `CSVParser` / `CSVRowView` / `SIMDScanner` — zero-copy row parsing.
- `CSVUtilities` — BOM detection, UTF-16/32 transcoding, escape/unescape, row builder.
- `CSVValueParser` / `CSVValueFormatter` / `LocaleUtilities` / `FormatterCache` — value-level
  encode/decode + cached `DateFormatter`/`NumberFormatter` templates.
- `CSVIndexedDecodable` / `CSVIndexedEncodable` — opt-in headerless column ordering protocol.
- `CSVCoderMacros` — `@CSVIndexed`, `@CSVColumn` (SwiftSyntax compiler plugin).

The decomposition is reasonable. The main coupling problem is that `Configuration` does not flow
through any single decode/encode pipeline — there are three independent pipelines, each re-implementing
header resolution, trimming, strict-mode validation, and key transformation. See §4 for concrete
divergences.

---

## 2. Performance audit

### 2.1 SIMD scanner is doing O(64) work per chunk — Medium

`SIMDScanner.findNextStructural`, `findNextQuote`, `needsQuoting`, `scanStructural`, and
`countNewlinesApprox` all follow the same pattern (`Sources/CSVCoder/Parsing/SIMDScanner.swift`):

```swift
let combinedMask = quoteMask .| delimMask .| crMask .| lfMask
for i in 0 ..< 64 where combinedMask[i] {
    return offset + i               // or: positions.append(…)
}
```

`SIMD64<UInt8>.==` produces a `SIMDMask<SIMD64<...>>` (one bit per lane), and the standard library
exposes it as a SIMD vector of `Bool`-bits. Iterating `0..<64` with a `where` predicate compiles to
64 conditional branches per chunk, regardless of whether any byte matched. That dominates the SIMD
gain for sparse inputs.

The portable, branch-free idiom on Apple silicon (NEON) is to **convert the mask to an integer and
use `trailingZeroBitCount`**:

```swift
let bits = unsafeBitCast(combinedMask, to: UInt64.self)   // 1 bit per lane on 64-byte mask
if bits != 0 { return offset + bits.trailingZeroBitCount }
```

`trailingZeroBitCount` lowers to `RBIT` + `CLZ` on AArch64 (two instructions), turning a 64-iteration
loop into a constant. The same shape applies to `scanStructural` (`reservoirEachMatch + popcount`),
and `countNewlinesApprox` already uses `nonzeroBitCount` for SWAR — extending that to the SIMD path
would close the loop. This is consistent with the **John Carmack** review in `CLAUDE.md` ("Is the
data layout cache-friendly? Is this the fastest way?").

Net expected speed-up: ~1.5–3× on the structural scan, which dominates the parser hot path. Verify
with `swift run -c release CSVCoderBenchmarks` before/after.

### 2.2 Parser allocates 4 arrays per row — Medium

`CSVParser.Iterator.next()` (`Sources/CSVCoder/Parsing/CSVParser.swift:103-108`):

```swift
var fieldStarts: [Int] = []
var fieldLengths: [Int] = []
var fieldQuoted: [Bool] = []
var fieldHasEscapedQuote: [Bool] = []
```

Four heap allocations per row, plus two scalar flags. For 1M rows × ~10 fields, that's 4M Array
allocations and 4M `Array<Int>`/`Array<Bool>` retains/releases when constructing `CSVRowView`. This
is the primary reason the raw-parse benchmark hits ~600K rows/s while Codable-decode caps at
~295K rows/s — the row-view allocation alone is on the order of ~3–5 µs per row.

Two improvements:

1. **Struct-of-arrays as one buffer.** Pack the four arrays into a single `ContiguousArray<Field>`
   where `struct Field { var start: Int32; var length: Int32; var flags: UInt8 }` — 9 bytes/field
   instead of 4×(stride+header). `Int32` is sufficient because `CSVRowView` only meaningfully
   addresses up to 4 GB of buffer.
2. **Reuse arrays across rows.** Keep the four arrays as iterator state, `removeAll(keepingCapacity:
   true)` between rows, and have `CSVRowView` take `ArraySlice<Field>` references. Trickier with the
   `withUnsafeBytes` lifetime, but the iterator is already non-`Sendable` so it's safe.

The cleanest modern shape is a `Span<Field>` (Swift 6.2 stdlib), but that requires `unsafe` annotation
and Swift Evolution churn for downstream consumers.

### 2.3 `CSVParser.parse()` materialises every row before decoding — Medium

`Sources/CSVCoder/Core/CSVDecoder.swift:516-548`:

```swift
let parser = CSVParser(buffer: bytes, delimiter: delimiter)
let rows = parser.parse()                            // ← collects to [CSVRowView]
// … strict-mode validation walks `rows` once …
// … decoding walks `rows` again …
```

For 1M rows × ~10 fields, `parser.parse()` allocates a 1M-element array of `CSVRowView`, each
referencing four small arrays from §2.2. That's a guaranteed peak memory of ~80 MB *before*
decoding starts. The decode loop then walks the same array. Fuse into one loop:

```swift
for (i, rowView) in parser.enumerated() where i >= startIndex {
    try validate(rowView, line: i + 1)
    try results.append(T(from: CSVRowDecoder(view: rowView, …)))
}
```

This drops peak memory by ~half on large inputs and improves cache locality. The streaming path
(`streamDecode`) already does this; only the sync path materialises.

### 2.4 `scanStructural` reserveCapacity heuristic is wrong — Low

`Sources/CSVCoder/Parsing/SIMDScanner.swift:116`:

```swift
positions.reserveCapacity(count / 8)   // Estimate ~1 structural per 8 bytes
```

For 100 KB of `aaaa,bbbb,…\n` this reserves 12 500 entries, but the actual count for a typical CSV
is closer to `rows × (fields + 1)` ≈ rows × 11. For a 100 KB CSV with 80-byte rows, the right
reservation is ~14 000 — close to the heuristic — but for quoted-text CSV with long fields the
reservation can be 10× too large, wasting cache. Use `count / 32` as a starting point and let Array
grow.

### 2.5 `Locale.availableIdentifiers` enumeration is a startup hit — Medium

`Sources/CSVCoder/Utilities/LocaleUtilities.swift:52-63`:

```swift
static let allCurrencySymbols: Set<String> = {
    var symbols = Set<String>()
    for identifier in Locale.availableIdentifiers {
        let locale = Locale(identifier: identifier)
        if let symbol = locale.currencySymbol { symbols.insert(symbol) }
    }
    …
}()
```

`Locale.availableIdentifiers.count` is ~900 on macOS 15. Constructing a `Locale` per identifier and
querying `currencySymbol` triggers ICU lookups (~10–50 µs each), yielding ~10–45 ms on first use of
`.flexible` number parsing or `.currency`. This is amortised by the static-let, but it's a
visible startup hit for short-lived CLI tools that only parse one row.

Replacement: there is no public Swift API in iOS 18+ that enumerates currency codes
(`Locale.commonISOCurrencyCodes` is deprecated). The pragmatic alternative is a hand-curated set of
~100 common symbols ($ € £ ¥ ₹ ₽ ¢ R$ A$ HK$ NT$ kr zł …). The unit suffixes (`unitSuffixes`)
already follow this pattern.

If the lazy lookup is kept, document the cold-start cost in the README's "Performance"
section.

### 2.6 `stripCurrencyAndUnits` is fragile — Medium

`Sources/CSVCoder/Utilities/LocaleUtilities.swift:103-122`:

```swift
let sortedSymbols = allCurrencySymbols.sorted { $0.count > $1.count }
for symbol in sortedSymbols { … }
```

Two issues:

1. **Single-letter currency symbols** (`R$` → `R`, `kr`, `A$`) collide with property values
   ("Robert", "Korean") in non-currency fields. The code partially guards against this by checking
   `last?.isNumber`, but `replacingOccurrences(of: symbol, with: "", options: .caseInsensitive)`
   for multi-char symbols runs unconditionally over the whole string. `"Krakow,123"` with
   `.flexible` parsing would have `kr` stripped to `akow,123` and fail downstream.
2. **`O(symbols × rows)`** when running with `.flexible` on every numeric column.

A targeted fix: only strip symbols that appear at the start or end of the trimmed string, never in
the middle. The current code does this for single-letter symbols but not for multi-char ones.

### 2.7 `FormatterCache.copy()` defeats most of the caching — Medium

`Sources/CSVCoder/Utilities/CSVValueFormatter.swift:123-172` hands out **a fresh `.copy()` on every
call** because `DateFormatter` / `NumberFormatter` are not thread-safe. The cache only saves the
~5–50 µs cost of fresh `init` + format-string parsing.

For iOS 18+/macOS 15+ deployment, the modern path is `Date.FormatStyle` / `FloatingPointFormatStyle`
/ `Decimal.FormatStyle`, which are **value types and `Sendable`** — no thread-safety concern, no
copy needed. The audit's verified findings (cf. docs-researcher §1) confirm that all 300+ locales
are supported.

Concretely:

- `formatDate(_:strategy: .formatted(format))` should call
  `try Date.VerbatimFormatStyle(format: …).format(date)` (verbatim is ICU-pattern-compatible) — or
  pre-parse the pattern into `Date.FormatStyle` via the strict-format DSL.
- `formatNumber(_:strategy: .locale(locale))` should call
  `FloatingPointFormatStyle<Double>.number.locale(locale).format(value)`.
- `parseDate(strategy: .formatted(format))` should call
  `try Date.VerbatimFormatStyle(format: …, locale: …, timeZone: …).parseStrategy.parse(value)`.

This eliminates the `Mutex<[String: Formatter]>` entirely and removes a `NSObject.copy()` per parse.

### 2.8 Parallel encode contention on `CSVEncodingStorage.Mutex` — Low

`Sources/CSVCoder/Encoder/CSVSingleValueEncoder.swift:318-370`: every keyed `set` takes the mutex,
appends to `orderedKeys`, mutates `values`. In the sync encoder a single thread writes, no
contention. In the parallel encoder each `Task` constructs its **own** `CSVEncodingStorage` via
`encodeValue(_:)` (`Sources/CSVCoder/Extensions/CSVEncoder+Streaming.swift:162-168`), so there is no
cross-task contention. That's correct.

But: a single row's encoding takes the mutex once per field, even though storage is single-task. The
mutex is wasted work on the hot path. Two options:

1. Drop to `@unchecked Sendable` with no lock since each `CSVEncodingStorage` is created per `Task`
   and never crosses isolation. The current code reads as if it expects sharing.
2. Replace `Mutex<State>` with raw `var values: [String: String]` + `var orderedKeys: [String]` and
   document the single-task contract.

Note: `@unchecked Sendable` on line 318 is already declared — the `Mutex` is defensive and not
required by isolation.

### 2.9 `MemoryMappedReader` is a thin wrapper around `Data` — Low

`Sources/CSVCoder/Parsing/MemoryMappedReader.swift` adds **no behaviour** beyond `Data(contentsOf:
options: .mappedIfSafe)`. `Data` is already `Sendable` and supports `withUnsafeBytes`. The class
adds a heap allocation, an extra retain/release, and `MemoryMappedReader.subscript(_:)` which is
strictly less efficient than `Data.subscript`. Delete the class and pass `Data` directly.

### 2.10 Custom snake_case algorithm diverges from `JSONEncoder` — Medium

`Sources/CSVCoder/Core/CSVEncoder.swift:424-446`:

```swift
private func convertCamelCase(_ key: String, separator: Character, uppercase: Bool) -> String { … }
```

This treats every uppercase letter as a word boundary, producing:

- `firstName` → `first_name` ✅
- `myURLProperty` → `my_u_r_l_property` ❌ (JSONEncoder produces `my_url_property`)
- `URLEncoder` → `_u_r_l_encoder` ❌ (JSONEncoder produces `url_encoder`)

`JSONEncoder._convertToSnakeCase` (swift-foundation) implements a "consecutive uppercase as one
acronym word" rule. Users migrating from JSON will hit different headers. Either:

- Document the divergence prominently, or
- Port the JSONEncoder algorithm (it's ~30 lines and unit-testable from the open-source
  swift-foundation `JSONEncoder.swift`).

Decoder's `convertFromSnakeCase` also differs: `split(separator: "_")` drops empty substrings, so
`__name` → `Name` (vs JSONDecoder's `__Name`).

---

## 3. Concurrency & Swift 6 strictness

### 3.1 `BackpressureController.waitForSpace` doesn't handle task cancellation — High

`Sources/CSVCoder/Extensions/CSVDecoder+Backpressure.swift:138-144`:

```swift
func waitForSpace() async {
    guard isPaused else { return }
    await withCheckedContinuation { continuation in
        waiters.append(continuation)
    }
}
```

If the consumer task is cancelled while the producer is suspended in `waitForSpace`, the continuation
stays in `waiters` until `cancelAllWaiters()` is invoked from `AsyncThrowingStream.onTermination`.
That callback fires when the **stream** terminates, not when the **consuming task** is cancelled.
There is a window where the producer holds a suspended continuation forever (or until the stream
GC).

Correct pattern (SE-0304, verified — see docs-researcher §6):

```swift
func waitForSpace() async {
    guard isPaused else { return }
    let id = nextWaiterID; nextWaiterID += 1
    await withTaskCancellationHandler {
        await withCheckedContinuation { continuation in
            waiters[id] = continuation
            // re-check cancellation: handler may have fired between append and suspend
            if Task.isCancelled { resumeWaiter(id: id) }
        }
    } onCancel: {
        Task { await self.resumeWaiter(id: id) }
    }
}
```

A simpler workaround: check `Task.isCancelled` at the top, and `for try await` in the consumer will
propagate cancellation. But the continuation-leak window is real and worth closing for a library API.

### 3.2 `CSVEncodingStorage` is `@unchecked Sendable` unnecessarily — Low

`Sources/CSVCoder/Encoder/CSVSingleValueEncoder.swift:318`:

```swift
nonisolated final class CSVEncodingStorage: @unchecked Sendable {
    private let state = Mutex(State())
}
```

`Mutex<T>` is `Sendable` when `T: ~Copyable` — but in this case `State` is `Copyable` and the
`Mutex` itself is `Sendable`. A `final class` with only `let` Sendable fields is `Sendable` without
`@unchecked`. Drop `@unchecked`.

(If retained for clarity, add a comment explaining what the `@unchecked` is guarding against.)

### 3.3 `Locale.autoupdatingCurrent` as a default arg — Low

`Sources/CSVCoder/Core/CSVDecoder.swift:230, 252, 258`: three strategy cases default to
`.autoupdatingCurrent`. Defaults are **captured at call site**, so a user reading the API doc could
think the locale is fixed at decoder-init time. In practice, an autoupdating locale means parsing
behaviour changes when the user switches system language at runtime — which is the documented
intent for `.localeAware`, but surprising for `.parseStrategy` and `.currency`.

Recommend: default to `.current` (snapshot) for `.parseStrategy` and `.currency`, retain
`.autoupdatingCurrent` only for the explicitly named `.localeAware` strategy. Document the
distinction.

### 3.4 `nonisolated` proliferation is correct but noisy — Low

Every type in `Encoder/` and many in `Decoder/` is marked `nonisolated struct` /
`nonisolated final class`. This is correct for Swift 6.2 with
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, but it bloats every signature. A single
`@_typeEraser` or per-module isolation default would be cleaner. As of Swift 6.2 you can set the
package-wide default via `.unsafeFlags(["-default-isolation", "nonisolated"])` — that's the cleanest
fix and removes ~40 redundant `nonisolated` keywords from the codebase.

(Skill: keep an eye on Swift 6.3+ `@isolated(any)` proposals that may further simplify.)

### 3.5 Test target for actor reentrancy — Low

`CSVConcurrencyStressTests.swift` exists but I did not validate the depth of coverage of the
back-pressure cancellation path described in §3.1. Recommend adding a test that explicitly cancels
the consuming task mid-decode and asserts no continuation leak (Task.isCancelled checked at
producer side, finite test runtime).

---

## 4. Codable architecture & feature coherency

### 4.1 `CSVIndexedEncodable` is dead code — Critical

Public protocol `CSVIndexedEncodable` (`Sources/CSVCoder/Utilities/CSVIndexedCodable.swift:77`) and
the macro-generated conformance (`Sources/CSVCoderMacros/CSVIndexedMacro.swift:98`) advertise that a
type's `CodingKeys` order defines the CSV column order on **encode**. The decoder honours this via
runtime `_CSVIndexedMarker` casting (4 sites in `CSVDecoder.swift` and `CSVDecoder+Streaming.swift`).

The encoder **never references `CSVIndexedEncodable`, `_CSVIndexedMarker`, or `csvColumnOrder`**.
Verified by `grep`:

```
$ grep -rn "CSVIndexedEncodable\|csvColumnOrder" Sources/CSVCoder/Core/ \
                                                 Sources/CSVCoder/Encoder/ \
                                                 Sources/CSVCoder/Extensions/
(no matches)
```

Concrete consequence: `@CSVIndexed struct R { @CSVColumn("b") let bb: Int; @CSVColumn("a") let aa: Int }`
encodes as `bb,aa` (Swift's property-declaration order via synthesised Encodable) regardless of
`hasHeaders` and regardless of any reordering in `CodingKeys`. The advertised
"`@CSVIndexed` Macro (Zero Boilerplate)" section of the README is decoder-only.

Fix sketch:

```swift
public func encode<T: Encodable>(_ values: [T]) throws -> Data {
    var buffer: [UInt8] = []
    let columnOrder = (T.self as? _CSVIndexedMarker.Type)?._csvColumnOrder
    try encodeToBuffer(values, into: &buffer, columnOrder: columnOrder)
    return Data(buffer)
}
```

And in `encodeToBuffer` use `columnOrder ?? orderedKeys` to build the header and pick fields.
Mirror this in all parallel/streaming encode entry points.

Also: `Configuration` lacks an `indexMapping`/`columnOrder` knob on the encoder side, even though
the decoder has both. That makes manual ordering impossible without macros.

### 4.2 Parallel encoder ignores `keyEncodingStrategy` — Critical

Verified in `Sources/CSVCoder/Extensions/CSVEncoder+Parallel.swift`:

| Function                      | Line | Header source            | `transformKey` applied? |
|-------------------------------|------|--------------------------|-------------------------|
| `encodeParallel(_:to:URL)`    | 87   | `orderedKeys`            | ❌                      |
| `encodeParallel(_:)`          | 139  | `orderedKeys`            | ❌                      |
| `encodeParallelBatched(_:)`   | 196  | `orderedKeys.map { escapeField($0) }` | ❌         |

By contrast, `CSVEncoder.encodeToBuffer` (`CSVEncoder.swift:355`) and `encodeToWriter`
(`CSVEncoder.swift:392`) both call `orderedKeys.map { transformKey($0) }`. The streaming variants in
`CSVEncoder+Streaming.swift` (lines 70, 134, 182) also do.

So `keyEncodingStrategy: .convertToSnakeCase` silently no-ops if you switch from `encode()` to
`encodeParallel()`. This is a contract violation.

Fix: apply `transformKey` in all three parallel encode paths. Add a regression test
(`CSVEncoderParallelEncodingTests.swift` exists but doesn't cover this).

### 4.3 `encodeRow` / `encodeToDictionary` / `headers(for:sample:)` don't apply
`keyEncodingStrategy` either — Medium

`Sources/CSVCoder/Core/CSVEncoder.swift:269-305`. None of the three single-value encode helpers
applies `transformKey`. `encodeRow` doesn't emit a header so the symptom is muted, but
`encodeToDictionary` returning `["firstName": …]` instead of `["first_name": …]` when the
strategy is `.convertToSnakeCase` is surprising and breaks symmetry with batch encode.

### 4.4 Two parser implementations — Critical (consistency)

`Sources/CSVCoder/Parsing/CSVParser.swift` and `Sources/CSVCoder/Parsing/StreamingCSVParser.swift`
are independent. `StreamingCSVParser` is used by `decodeWithBackpressure`,
`decodeBatchedWithBackpressure`, and `decodeWithProgress`. The other streaming entry point
(`decode(_:from:URL)` returning `AsyncThrowingStream`) uses `CSVParser` via `streamDecode →
decodeFromReader`.

Divergence checklist:

| Behaviour                       | `CSVParser`                              | `StreamingCSVParser`                       |
|---------------------------------|------------------------------------------|--------------------------------------------|
| SIMD acceleration               | yes (64-byte vectors)                    | no (scalar byte-by-byte)                   |
| Lone `\r` as line terminator    | yes (`resolveTerminator`)                | yes (different code path)                  |
| `expectedFieldCount` validation | in caller, post-iterate                  | inline in `parseNextRow`                   |
| Quote-in-unquoted detection     | per-field flag, lenient/strict in caller | inline strict, lenient = literal           |
| Field accumulation              | offsets into mmap'd buffer (O(1))        | per-field `[UInt8]` buffer (O(field-size)) |
| Trim whitespace                 | caller decides per-string                | inline `String → trim`                     |
| BOM handling                    | `CSVUtilities.adjustedBuffer` in caller  | `skipBOM` in iterator (different path)     |

This is the deepest sin in the codebase. Test users who switch from `decode(_:from:URL)` →
`decodeWithBackpressure(_:from:URL)` will see different decode behaviour for the same data.

Recommended consolidation:

1. Delete `StreamingCSVParser` and `MemoryMappedReader.subscript(_:)`.
2. Build the back-pressure path on top of `CSVParser.Iterator` running inside the
   `Data.withUnsafeBytes` closure, with `yield` happening from outside that scope after copying
   field bytes to `[String]`. The `MemoryMappedReader` already keeps `Data` alive.
3. Move strict-mode validation into a single `CSVParser` post-iterate validator that all paths
   call.

If `StreamingCSVParser` is kept (e.g., for the chunked-network use case), at minimum align its
strict-mode behaviour and document the differences explicitly.

### 4.5 `nestedTypeDecodingStrategy: .codable` is actually `.json` — Low

`Sources/CSVCoder/Decoder/CSVRowDecoder.swift:435-454`:

```swift
case .codable:
    // Get the field value as Data and use it directly
    …
    let jsonDecoder = JSONDecoder()
    let jsonContainer = try jsonDecoder.decode(NestedJSONContainer<NestedKey>.self, from: data)
```

The `.codable` case is identical to `.json` (both run JSONDecoder). The docs claim "Convert field to
Data and decode using the type's Decodable conformance" — but there is no `.codable` data format,
only JSON. Either:

- Implement a non-JSON Codable container (binary plist, PropertyList) for `.codable`, or
- Remove `.codable` and document `.json` as the only nested strategy.

Same on the encoder side (`CSVRowEncoder.swift:218-228`).

### 4.6 `MemoryMappedReader.subscript(range:)` is unused — Low

The `Range<Int>` subscript on `MemoryMappedReader` (`MemoryMappedReader.swift:46-49`) has no
in-tree callers. Dead code, remove with §4.4 cleanup.

### 4.7 `expectedFieldCount` is only validated in strict mode — Medium

`Sources/CSVCoder/Core/CSVDecoder.swift:539`:

```swift
if isStrict, let expected = expectedFieldCount, row.count != expected { throw … }
```

A user setting `expectedFieldCount` is asserting a contract; it's reasonable to expect the assertion
to fire even in lenient mode (perhaps with a different error class). Currently it silently
no-ops. Either:

- Validate in both modes (recommended; expectedFieldCount expresses intent, not parser leniency), or
- Document that `expectedFieldCount` only applies in strict mode.

### 4.8 Single-value decoder hardcodes int parsing without strategy — Medium

`CSVRowDecoder.decode(_:Int.Type, forKey:)` (and Int8…UInt64) uses raw `Int(value)`. No
`numberDecodingStrategy` applied. So `.flexible` (which strips currency from "1,234 €") parses
fine for `Double` but throws for `Int`. This is documented? — README's "Flexible Decoding
Strategies / Number Decoding" doesn't restrict to floating-point.

Fix: route integers through `CSVValueParser.parseDouble(...)` and convert with bounds check, or add
`CSVValueParser.parseInt`/`parseInt64` strategy-aware variants.

### 4.9 `URL(string:)` and `UUID(uuidString:)` are over-permissive — Medium

`CSVRowDecoder.swift:368, 360` and `CSVSingleValueDecoder.swift:170, 178`:

```swift
guard let url = URL(string: value) else { throw … }
```

`URL(string:)` auto-percent-encodes invalid input and returns non-nil for most malformed values. For
a parser intended to reject bad data, use the iOS 17+/macOS 14+ strict variant:

```swift
guard let url = URL(string: value, encodingInvalidCharacters: false) else { throw … }
```

This rejects `https://example.com/foo bar` (returns nil) instead of silently encoding to
`…/foo%20bar`. The deployment target supports it (iOS 18+ baseline).

`UUID(uuidString:)` is already strict.

### 4.10 `JSONDecoder()` inside the row decoder is unguarded — High (security/perf)

`CSVRowDecoder.swift:332-334`:

```swift
case .codable, .json:
    let value = try getValue(for: key)
    return try JSONDecoder().decode(T.self, from: data)
```

A CSV cell containing a 100 MB nested JSON will be parsed into a `T`. There is no size limit, no
depth limit, no `JSONDecoder.allowsJSON5` flag. If an attacker controls input (e.g., uploaded CSV in
a web service) and the model has `nestedTypeDecodingStrategy != .error`, this is a denial-of-service
vector via deeply-nested JSON or pathological strings.

Mitigations:

- The default is `.error`; users have to opt in. Document the DoS implications.
- Add a per-cell size limit to the nested strategy: `.json(maxBytes: Int = 1 << 20)`.
- Pre-construct the `JSONDecoder` once (per-`CSVDecoder.Configuration`) instead of per-row.

---

## 5. Native API & open-source package opportunities

### 5.1 Prefer `FormatStyle`/`ParseStrategy` over `DateFormatter`/`NumberFormatter` — Medium

(Verified by docs-researcher §1.) The codebase already uses `Date.ISO8601FormatStyle` for
`.iso8601`, `Date.FormatStyle.parseStrategy` for `.localeAware`, and
`FloatingPointFormatStyle.ParseStrategy` for `.parseStrategy`. But:

- `.formatted(format)` still routes through `DateFormatter` + `FormatterCache` (§2.7).
- `.locale(locale)` for number parsing routes through `NumberFormatter`.
- `.standard` for `Decimal` uses `Decimal(string:locale:)` — fine but not the modern
  `Decimal.FormatStyle.number.parseStrategy`.

Migration would also remove `import Foundation`'s ICU coupling in benchmarks (faster cold start).

### 5.2 `swift-collections` for `OrderedDictionary` — Medium

`CSVEncodingStorage` and `CSVKeyedDecodingContainer`'s `headerMap` both maintain an ordered set of
keys with a parallel value dictionary. `OrderedDictionary` from `swift-collections` is a single
type that owns both, with O(1) ordered iteration and O(1) lookup. The internal `(orderedKeys,
values)` pairing in `CSVEncodingStorage.State` becomes a single `OrderedDictionary<String, String>`.

Adding `swift-collections` is a one-line `Package.swift` change. It's an Apple SwiftLang project,
ABI-stable, and used by Foundation itself.

### 5.3 `swift-async-algorithms` for streaming — Low

`AsyncBufferedByteIterator` would simplify chunked file reading; `AsyncChain` / `AsyncChunks` would
clean up `encodeBatched`. Not blocking, but a more idiomatic alternative.

### 5.4 `swift-system` for `FileDescriptor` — Low

`AsyncCSVWriter` and `BufferedCSVWriter` both call into `FileHandle` (which is the legacy NSObject
wrapper). `FileDescriptor` from `swift-system` exposes raw POSIX `write(2)` with lower overhead and
better async story. Migration is nontrivial (closes-on-deinit semantics differ); flag as future
work.

### 5.5 `swift-experimental-string-processing` for date hints — Low

`CSVValueParser.dateFormats` is a 23-element array of format strings tried one-by-one. The
`parseFlexibleDate` happy path is 1 ms / call. With Swift 5.7+'s built-in `Regex`, a single
regex (`#/(?<y>\d{4})-(?<m>\d{2})-(?<d>\d{2})/#`) per common pattern is faster and avoids the ICU
DateFormatter heat. Not blocking; benefits scale with `.flexible` row count.

### 5.6 DocC — coverage gaps — Low

`Sources/CSVCoder/CSVCoder.docc/` has articles for `GettingStarted`, `Macros`, `ParallelDecoding`,
`ParallelEncoding`, `StreamingDecoding`, `StreamingEncoding`. Missing:

- "Configuration cookbook" (how to combine `keyDecodingStrategy` + `columnMapping` +
  `indexMapping`).
- "Locale-aware parsing" (the `.flexible` / `.parseStrategy` / `.currency` matrix).
- "Error handling" (the `CSVDecodingError.suggestion` feature is rich but undocumented in
  catalog form).

---

## 6. Security review

### 6.1 Pointer safety — Pass

`CSVParser.parse(data:delimiter:body:)` correctly scopes the unsafe buffer inside
`Data.withUnsafeBytes`. `CSVRowView` is non-`Sendable` and explicitly documented as
"do not store beyond the closure scope". `decodeRowsFromBytes` walks the buffer entirely inside the
closure. The `parse() -> [CSVRowView]` API (line 201) returns `CSVRowView` instances **outside** the
closure — these are valid only as long as the underlying `Data` is alive. The internal callers
keep `Data` alive on the stack frame, so this is sound in practice but fragile if a user copies the
array out.

**Recommendation:** mark `CSVRowView` with `BitwiseCopyable: false` or wrap in a
`~Escapable` (Swift 6 non-escapable types) once stable, to enforce lifetime at compile time.

### 6.2 `Data(contentsOf: url, options: .mappedIfSafe)` — Pass

Verified correct (docs-researcher §2). On local FS this avoids loading the file into RAM; on
network FS it falls back to read. The SIGBUS risk on truncation during read is the only residual,
and there's no mitigation possible from user space.

### 6.3 Nested-JSON DoS — High

See §4.10. The `.json` / `.codable` nested strategies run untrusted `JSONDecoder` on user-controlled
field values with no size/depth limit.

### 6.4 `String(decoding:as:)` substitutes U+FFFD for invalid UTF-8 — Medium

`String(decoding: bytes, as: UTF8.self)` (used in `CSVRowView.string(at:)`, `CSVUnescaper.unescape`,
`CSVUtilities.transcodeToUTF8`, etc.) silently replaces invalid bytes with `\u{FFFD}` rather than
returning nil. For a parser claiming RFC compliance, this is too permissive — invalid UTF-8 in a
CSV field is a parsing error, not data to be quietly mangled.

Recommend: in strict mode, switch `String(decoding:as:)` → `String(bytes:encoding:.utf8)` (returns
nil on invalid) and throw `parsingError`. Lenient mode can keep current behaviour.

### 6.5 `JSONEncoder().outputFormatting = [.sortedKeys]` is one-way — Low

`Sources/CSVCoder/Encoder/CSVRowEncoder.swift:221-223`: nested-encode JSON is sorted-keys.
Round-trip with decoder requires the decoder to not care about key order, which is true. OK.

### 6.6 Field count DoS — Low

A CSV with 100 M columns and 1 row would allocate 100 M `Int` × 4 arrays per row (§2.2) plus
100 M `String` entries in the header map. ~3.2 GB. The parser doesn't guard against pathological
column counts. Practical mitigation: cap headers to, say, 65 535 (per RFC 4180 spirit), or expose
`Configuration.maxFieldCount: Int = .max` for users to tighten.

---

## 7. Macro implementation review

### 7.1 String-template generation is brittle — Low

`Sources/CSVCoderMacros/CSVIndexedMacro.swift:226-245` builds the `CodingKeys` enum with raw string
concatenation:

```swift
casesCode += "        case \(prop.name) = \"\(customName)\""
```

Two issues:

- **Indentation is hardcoded to 8 spaces.** When `@CSVIndexed` is applied to a nested struct inside
  another type, the expansion looks misaligned (cosmetic).
- **Property names are not escaped.** A property named `init` would generate `case init` which is
  not legal Swift. Use backtick escaping when needed.

Use `EnumDeclSyntax(name: …, …) { caseSyntaxes }` via SwiftSyntaxBuilder to avoid string templating.

### 7.2 No diagnostic for `@CSVColumn` without `@CSVIndexed` — Low

`@CSVColumn` on a property of a struct without `@CSVIndexed` silently does nothing (it's a
`@attached(peer)` macro returning `[]`). Add an emit-only diagnostic warning when `@CSVColumn` is
applied to a property in a struct lacking `@CSVIndexed`.

### 7.3 Duplicate `@CSVColumn` names accepted — Low

`@CSVIndexed struct R { @CSVColumn("x") let a: Int; @CSVColumn("x") let b: Int }` produces:

```swift
enum CodingKeys: String, CodingKey, CaseIterable {
    case a = "x"
    case b = "x"   // ❌ duplicate raw value — Swift compiler error
}
```

The error message points to the generated source, not the macro invocation. Add a macro-side
diagnostic ("Duplicate CSV column name 'x' on `R.a` and `R.b`").

### 7.4 No support for inheritance / class — Pass

The macro explicitly throws `CSVIndexedMacroError.notAStruct`. Correct, since synthesised Encodable
for classes uses a different code path.

---

## 8. README ↔ implementation gap analysis

| README claim                                          | Implementation status                                                                                  |
|-------------------------------------------------------|--------------------------------------------------------------------------------------------------------|
| Type-safe CSV encoding/decoding via Codable           | ✅                                                                                                     |
| `@CSVIndexed` / `@CSVColumn` for headerless CSV       | ⚠️ Decoder only. **Encoder ignores `csvColumnOrder`** (§4.1)                                          |
| Streaming encoding/decoding O(1) memory               | ✅ for the SIMD streaming path; the back-pressure path uses a different scalar parser (§4.4)          |
| Parallel encoding/decoding                            | ⚠️ Works, but parallel encode **drops `keyEncodingStrategy`** (§4.2)                                  |
| Smart error suggestions with typo detection           | ✅ Levenshtein-based in `CSVDecodingError.suggestion`                                                  |
| Configurable delimiters                               | ✅ (ASCII precondition enforced)                                                                       |
| Multiple date encoding strategies                     | ✅                                                                                                     |
| Flexible decoding strategies                          | ⚠️ Number `.flexible` has brittle currency-stripping (§2.6); `Int(value)` ignores strategy (§4.8)     |
| Key decoding strategies (snake_case, etc.)            | ⚠️ Algorithm diverges from JSONEncoder for acronyms (§2.10)                                           |
| Index-based decoding                                  | ✅                                                                                                     |
| `CSVIndexedDecodable` auto-detect                     | ✅                                                                                                     |
| Rich error diagnostics with row/column info           | ✅                                                                                                     |
| Optional value handling                               | ✅                                                                                                     |
| SIMD-accelerated parsing                              | ⚠️ SIMD masks scanned with a 64-iteration loop instead of bitmask intrinsics (§2.1)                   |
| Thread-safe with `Sendable`                           | ✅ (with `@unchecked Sendable` on `CSVEncodingStorage` that can be tightened)                          |
| No `fatalError()`, all unsupported ops throw          | ✅ — `CSVPoisonContainers` implements the throwing fallbacks                                          |
| Swift 6.2 Approachable Concurrency                    | ✅                                                                                                     |
| ~602K rows/s raw parse                                | Unverified in audit (Benchmark requires release build). Bench infra exists.                            |
| ~295K rows/s Codable decode                           | Unverified. Likely bounded by row-metadata allocation (§2.2/§2.3).                                     |
| Streaming docs: `for try await record in decoder.decode(…)` | ✅                                                                                                |
| Raw zero-copy `CSVParser.parse(data:)` API            | ✅                                                                                                     |

---

## 9. Recommendations — prioritised

### Must-fix before next minor release

1. **Wire `csvColumnOrder` into all encode entry points** (§4.1). Without this, the macro's
   encoder side is broken.
2. **Apply `transformKey` in the three parallel encode paths** (§4.2). Add a regression test.
3. **Consolidate the two parsers** (§4.4) — pick `CSVParser` and delete `StreamingCSVParser` and
   `MemoryMappedReader`. Or document the differences explicitly and add tests proving they're
   intentional.
4. **Close the continuation-leak window in `BackpressureController`** (§3.1).
5. **Bound `JSONDecoder` use in nested strategy** (§4.10).

### Should-fix

6. SIMD-mask bitmask intrinsics (§2.1) — biggest perf win.
7. Merge per-row Arrays into struct-of-arrays (§2.2) — second-biggest perf win.
8. Fuse `parse()` + decode into one loop (§2.3).
9. `URL(string:encodingInvalidCharacters: false)` (§4.9).
10. Strategy-aware integer parsing (§4.8).
11. `keyEncodingStrategy` applied in `encodeRow` / `encodeToDictionary` / `headers(for:sample:)`
    for consistency (§4.3).
12. Snake_case algorithm parity with JSONEncoder (§2.10).

### Could-fix

13. Hand-curated currency symbol set (§2.5).
14. Migrate `.formatted(format)` to `Date.VerbatimFormatStyle` and `.locale(_:)` to
    `FloatingPointFormatStyle` (§2.7 / §5.1).
15. `swift-collections` `OrderedDictionary` for header maps (§5.2).
16. Drop `@unchecked Sendable` on `CSVEncodingStorage` (§3.2).
17. Package-level `-default-isolation nonisolated` to remove ~40 keyword repetitions (§3.4).
18. Macro diagnostics for duplicate `@CSVColumn` names (§7.3) and orphan `@CSVColumn` (§7.2).
19. DocC catalog: configuration cookbook + error handling article (§5.6).
20. Strict-mode invalid-UTF-8 rejection (§6.4).
21. Document `expectedFieldCount`'s strict-mode-only semantics or extend to lenient (§4.7).

---

## 10. Out-of-scope notes

- Did not run `swift run -c release CSVCoderBenchmarks` — benchmark numbers in the README are
  trusted as reported. The architectural notes in §2 predict where they're CPU-bound (allocator
  and SIMD-tail).
- Did not run `swift test` for this audit pass. The codebase builds clean (`swift build` succeeds
  in 7.5 s on this machine).
- Did not audit the GitHub Actions workflows (`.github/`) or the SwiftProjectKit hooks
  (`.spk.json`) beyond confirming they exist and target the same Swift / platform versions as
  `Package.swift`.
- Did not deep-audit the benchmark target's `HardwareInfo.swift` or `main.swift` (823 LoC) —
  benchmarks are not on the runtime hot path.

---

*Audit performed by an automated reviewer against the codebase at commit `3b20c0c` on `main`.*
