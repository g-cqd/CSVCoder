# Security Policy

## Supported Versions

The current development line on `main` receives security fixes. No
versioned releases have been cut yet; once a stable tag is published
this table will be updated.

## Reporting a Vulnerability

If you discover a security vulnerability in CSVCoder, please report it
privately via GitHub's "Report a vulnerability" form on the repository
Security tab, or open an issue prefixed with `[SECURITY]` if private
reporting is unavailable.

We aim to acknowledge reports within 48 hours.

## Security Considerations

CSVCoder is designed to handle untrusted CSV input safely. Defences in depth:

- **Memory-mapped reads**: file-backed inputs use
  `Data(contentsOf:options: .mappedIfSafe)`, avoiding full loads of large
  files into RAM. The OS falls back to a regular read on network volumes
  where SIGBUS handling is unsafe.
- **Bounded nested JSON**: the `.json(maxBytes:)` nested strategy rejects
  cell payloads larger than the configured budget (default 1 MiB),
  bounding the work done by the inner `JSONDecoder`/`JSONEncoder`.
- **Strict UTF-8 in strict mode**: `parsingMode: .strict` rejects
  invalid UTF-8 byte sequences instead of substituting U+FFFD.
- **Strict URL parsing**: `URL` fields are decoded with
  `encodingInvalidCharacters: false`, rejecting malformed URLs.
- **RFC 4180 validation**: strict mode rejects unterminated quotes,
  quotes inside unquoted fields, and (when configured) field-count
  mismatches.
- **No dynamic code execution**, **no network access**, **no implicit
  file system writes** — file output occurs only through the explicit
  `encode(_:to:URL)` family.

## Response targets (best-effort, solo maintainer)

This project is maintained by a single developer on a best-effort basis; the targets below are realistic guidelines
rather than contractual SLAs:

| Milestone | Best-effort target |
| --- | --- |
| Private acknowledgement | Within **7–14 days** |
| Initial triage & severity confirmation | Within **30 days** |
| Fix & advisory — **Critical** | Within **30 days** (sooner when actively exploited) |
| Fix & advisory — **High** | Within **60–90 days** |
| Fix — **Medium / Low** | Next scheduled release, as time permits |

Security fixes in released versions are published with a GitHub Security Advisory (and CVE identifier where applicable)
and named in the release notes.