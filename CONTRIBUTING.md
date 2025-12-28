# Contributing to CSVCoder

Contributions are welcome! This document outlines how to contribute to CSVCoder.

## Development Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/your-org/CSVCoder.git
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

4. Run benchmarks:
   ```bash
   swift run -c release CSVCoderBenchmarks
   ```

## Requirements

- Swift 6.2+
- Xcode 16.2+
- macOS 15+ / iOS 18+ / tvOS 18+ / watchOS 11+ / visionOS 2+

## Code Style

- Follow Swift API Design Guidelines
- All public types must be `Sendable`
- Use `nonisolated` for pure functions
- Prefer `async`/`await` over callbacks
- No force unwrapping in library code

## Pull Request Process

1. Fork the repository and create a feature branch
2. Ensure all tests pass: `swift test --parallel`
3. Add tests for new functionality
4. Update documentation if needed
5. Submit a pull request with a clear description

## Reporting Issues

Please use GitHub Issues to report bugs or request features. Include:
- Swift/Xcode version
- Platform and OS version
- Minimal reproduction case
- Expected vs. actual behavior
