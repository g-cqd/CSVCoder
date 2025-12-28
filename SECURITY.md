# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.x     | :white_check_mark: |

## Reporting a Vulnerability

If you discover a security vulnerability in CSVCoder, please report it by opening a GitHub Issue.

For sensitive security issues, please include "[SECURITY]" in the issue title.

We will respond within 48 hours and work with you to understand and address the issue.

## Security Considerations

CSVCoder is designed to safely parse untrusted CSV input:

- Memory-mapped I/O prevents loading entire files into memory
- Strict mode validates RFC 4180 compliance
- No dynamic code execution
- No network access
- No file system writes (except explicit file output APIs)
