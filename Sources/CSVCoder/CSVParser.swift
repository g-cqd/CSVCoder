//
//  CSVParser.swift
//  CSVCoder
//
//  Parses CSV strings into rows and columns.
//  RFC 4180 compliant parser with proper quote handling.
//

import Foundation

/// Parses CSV text into an array of rows.
/// Implements RFC 4180 compliant parsing with proper handling of:
/// - Quoted fields containing delimiters, quotes, and newlines
/// - Escaped quotes (doubled quotes within quoted fields)
/// - CRLF and LF line endings
struct CSVParser: Sendable {
    let string: String
    let configuration: CSVDecoder.Configuration

    /// Parses the CSV string into rows of string arrays.
    /// - Throws: `CSVDecodingError.parsingError` if the CSV is malformed (e.g., unterminated quotes)
    func parse() throws -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false
        var fieldStartLine = 1
        var fieldStartColumn = 1
        var lineNumber = 1
        var columnNumber = 1

        let chars = Array(string)
        var i = 0

        while i < chars.count {
            let char = chars[i]

            if inQuotes {
                if char == "\"" {
                    // Check for escaped quote ""
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        currentField.append("\"")
                        i += 2
                        columnNumber += 2
                        continue
                    } else {
                        // End of quoted field
                        inQuotes = false
                        i += 1
                        columnNumber += 1
                        continue
                    }
                } else {
                    // Character inside quoted field (including newlines)
                    if char == "\n" {
                        lineNumber += 1
                        columnNumber = 0
                    }
                    currentField.append(char)
                    i += 1
                    columnNumber += 1
                    continue
                }
            }

            // Not in quotes
            if char == "\"" {
                if currentField.isEmpty {
                    // Start of quoted field
                    inQuotes = true
                    fieldStartLine = lineNumber
                    fieldStartColumn = columnNumber
                    i += 1
                    columnNumber += 1
                    continue
                } else {
                    // Quote in middle of unquoted field - treat as literal (lenient)
                    currentField.append(char)
                    i += 1
                    columnNumber += 1
                    continue
                }
            }

            if char == configuration.delimiter {
                currentRow.append(processField(currentField))
                currentField = ""
                i += 1
                columnNumber += 1
                continue
            }

            // Handle line endings (use Unicode scalars for explicit comparison)
            let isCR = char.unicodeScalars.first?.value == 0x0D
            let isLF = char.unicodeScalars.first?.value == 0x0A

            if isCR {
                // Check for CRLF
                let nextIsLF = i + 1 < chars.count && chars[i + 1].unicodeScalars.first?.value == 0x0A
                if nextIsLF {
                    // CRLF
                    currentRow.append(processField(currentField))
                    currentField = ""
                    if !currentRow.isEmpty {
                        rows.append(currentRow)
                    }
                    currentRow = []
                    i += 2  // Skip both \r and \n
                    lineNumber += 1
                    columnNumber = 1
                    continue
                } else {
                    // Lone CR (old Mac style)
                    currentRow.append(processField(currentField))
                    currentField = ""
                    if !currentRow.isEmpty {
                        rows.append(currentRow)
                    }
                    currentRow = []
                    i += 1
                    lineNumber += 1
                    columnNumber = 1
                    continue
                }
            }

            if isLF {
                // LF line ending
                currentRow.append(processField(currentField))
                currentField = ""
                if !currentRow.isEmpty {
                    rows.append(currentRow)
                }
                currentRow = []
                i += 1
                lineNumber += 1
                columnNumber = 1
                continue
            }

            // Regular character
            currentField.append(char)
            i += 1
            columnNumber += 1
        }

        // Check for unterminated quoted field
        if inQuotes {
            throw CSVDecodingError.parsingError(
                "Unterminated quoted field starting at line \(fieldStartLine), column \(fieldStartColumn)"
            )
        }

        // Handle last field and row
        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(processField(currentField))
            if !currentRow.isEmpty {
                rows.append(currentRow)
            }
        }

        return rows
    }

    private func processField(_ field: String) -> String {
        if configuration.trimWhitespace {
            return field.trimmingCharacters(in: .whitespaces)
        }
        return field
    }
}
