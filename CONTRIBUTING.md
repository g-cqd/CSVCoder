# Contributing to CSVCoder

Contributions are welcome! This document outlines how to contribute to CSVCoder.

## Development Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/g-cqd/CSVCoder.git
   cd CSVCoder
   ```

2. Build the package:
   ```bash
   swift build
   ```

3. Run tests:
   ```bash
   swift test --parallel
   ```

4. Run benchmarks (must be `-c release`, the benchmark harness refuses
   to run without optimizations):
   ```bash
   swift run -c release CSVCoderBenchmarks
   ```

## Requirements

- Swift 6.2+
- Xcode 26+ (Swift 6.2 toolchain)
- macOS 15+ / iOS 18+ / tvOS 18+ / watchOS 11+ / visionOS 2+

## Code Style

- Follow Swift API Design Guidelines
- All public types must be `Sendable`
- Use `nonisolated` for pure functions
- Prefer `async`/`await` over callbacks
- No force unwrapping in library code

## Git Hooks

This repo uses [project-hooks](https://github.com/g-cqd/project-hooks)
for pre-commit and pre-push validation. Configuration is in
`.project-hooks.yml`. To install the hooks locally after cloning:

```bash
project-hooks install
```

The hooks auto-detect `swift-format` and the SwiftPM test runner. The
config layered on top enforces Conventional Commits on pushed commits
and runs `swift test --parallel` on pre-push.

## Pull Request Process

1. Fork the repository and create a feature branch
2. Install hooks: `project-hooks install`
3. Ensure all tests pass: `swift test --parallel`
4. Add tests for new functionality
5. Update documentation if needed
6. Submit a pull request with a clear description; commit messages
   must follow Conventional Commits (`feat:`, `fix:`, `perf:`, etc.)

## Reporting Issues

Please use GitHub Issues to report bugs or request features. Include:
- Swift/Xcode version
- Platform and OS version
- Minimal reproduction case
- Expected vs. actual behavior
