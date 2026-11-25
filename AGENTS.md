# Working in `CSVCoder`

SIMD-accelerated, `Codable`-compatible CSV encoder and decoder with `@CSVRow`/`@CSVColumn` macros, streaming, and parallel processing (`g-cqd/CSVCoder`).

## Engineering principles

- **Verify claims with executable checks.** Write a failing test or measurement before changing behaviour; never state unmeasured performance or unverified behaviour as fact.
- **Strictness.** Swift 6 language mode, strict concurrency, strict memory safety where configured, and warnings as errors. No force-unwraps or force-casts in production paths.
- **Bounded work and safety.** Bound untrusted inputs, recursion depth, and memory before allocation; handle errors explicitly without crashing on hostile input.
- **Factual documentation.** Keep `README.md`, user docs, and `Package.swift` aligned with the current codebase—no roadmaps, speculative plans, or diary logs in public docs.

Keep decoding/encoding trap-free (`fatalError` is forbidden on runtime paths; throw typed `CSVDecodingError`/`CSVEncodingError`).

## Commands

```sh
swift test
swift format lint --strict --recursive Sources Tests Package.swift
```

## Architecture records

Accepted architectural decisions live in `docs/adr/` (when present). Only add a new ADR for durable architectural choices; mark superseded records clearly.
