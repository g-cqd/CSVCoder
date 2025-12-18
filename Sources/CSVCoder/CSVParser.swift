//
//  CSVParser.swift
//  CSVCoder
//
//  Parses CSV strings into rows and columns.
//

import Foundation

/// Parses CSV text into an array of rows.
struct CSVParser: Sendable {
    let string: String
    let configuration: CSVDecoder.Configuration

    /// Parses the CSV string into rows of string arrays.
    func parse() throws -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false
        var index = string.startIndex

        while index < string.endIndex {
            let char = string[index]

            if inQuotes {
                if char == "\"" {
                    let nextIndex = string.index(after: index)
                    if nextIndex < string.endIndex && string[nextIndex] == "\"" {
                        // Escaped quote
                        currentField.append("\"")
                        index = nextIndex
                    } else {
                        // End of quoted field
                        inQuotes = false
                    }
                } else {
                    currentField.append(char)
                }
            } else {
                if char == "\"" {
                    inQuotes = true
                } else if char == configuration.delimiter {
                    currentRow.append(processField(currentField))
                    currentField = ""
                } else if char.isNewline {
                    currentRow.append(processField(currentField))
                    currentField = ""
                    if !currentRow.allSatisfy({ $0.isEmpty }) || !currentRow.isEmpty {
                        rows.append(currentRow)
                    }
                    currentRow = []
                } else {
                    currentField.append(char)
                }
            }

            index = string.index(after: index)
        }

        // Handle last field and row
        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(processField(currentField))
            if !currentRow.allSatisfy({ $0.isEmpty }) {
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
