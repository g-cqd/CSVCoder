# CI

`.github/workflows/ci.yml` calls the family's pinned swift-ci workflow (`Checks`), configured by `action.json`; run
the same checks here with `.ci/swift-ci local`.

Each change runs quality (swift-format and SwiftLint, strict; the shipped-library discipline; deadwood, dolly and
arcleak against `baselines/`), the macOS debug tests on Swift 6.4.1 and 6.3.3 (the manifest's floor), the release
tests (the performance-sensitive tests assert on optimized code), and `xcodebuild` builds for iOS, macOS, tvOS,
watchOS and visionOS. The sanitizers run nightly or manually. CSVCoder is an Apple-platforms library (its benchmark
executable reads `sysctlbyname`), so there is no Linux leg.

The platform builds use the simulator SDKs, as before the migration (aemi builds for them since 15217a0, where
`CAemiCPU` checks for `timingsafe.h`, which only the device SDKs have).

The TLA+ models run after the macOS release tests (the `tla-models` command: `Formal/*.cfg` must hold,
`Formal/*.buggy.cfg` must be refuted). The workflow's own jobs: the Lean proofs (`Scripts/formal.sh lean`), documentation (validated on every run,
published to GitHub Pages from main), and, when `.version` names a version without a tag, the release with its
benchmarks.

`baselines/dolly.json` accepts the 281 clone findings that predate this configuration; only a new one fails.
