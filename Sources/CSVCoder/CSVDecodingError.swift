//
//  CSVDecodingError.swift
//  CSVCoder
//
//  Error types for CSV decoding.
//

import Foundation

/// Location information for errors in CSV data.
public struct CSVLocation: Sendable, Equatable, CustomStringConvertible {
    /// The 1-based row number in the CSV file.
    public let row: Int?
    /// The column name or index where the error occurred.
    public let column: String?
    /// The coding path at the point of the error.
    public let codingPath: [String]
    /// Available keys in the current context (for suggestions).
    public let availableKeys: [String]?

    public init(
        row: Int? = nil,
        column: String? = nil,
        codingPath: [CodingKey] = [],
        availableKeys: [String]? = nil
    ) {
        self.row = row
        self.column = column
        self.codingPath = codingPath.map { $0.stringValue }
        self.availableKeys = availableKeys
    }

    public var description: String {
        var parts: [String] = []
        if let row = row {
            parts.append("row \(row)")
        }
        if let column = column {
            parts.append("column '\(column)'")
        }
        if !codingPath.isEmpty {
            parts.append("path: \(codingPath.joined(separator: "."))")
        }
        return parts.isEmpty ? "unknown location" : parts.joined(separator: ", ")
    }

    public static func == (lhs: CSVLocation, rhs: CSVLocation) -> Bool {
        lhs.row == rhs.row &&
        lhs.column == rhs.column &&
        lhs.codingPath == rhs.codingPath
        // Note: availableKeys intentionally excluded from equality
    }
}

/// Errors that can occur during CSV decoding.
public enum CSVDecodingError: Error, LocalizedError, Sendable {
    /// The data could not be decoded with the specified encoding.
    case invalidEncoding

    /// A required key was not found in the CSV row.
    case keyNotFound(String, location: CSVLocation)

    /// The value could not be converted to the expected type.
    case typeMismatch(expected: String, actual: String, location: CSVLocation)

    /// The requested operation is not supported for CSV decoding.
    case unsupportedType(String)

    /// A parsing error occurred.
    case parsingError(String, line: Int?, column: Int?)

    // Legacy initializers for backward compatibility
    public static func keyNotFound(_ key: String) -> CSVDecodingError {
        .keyNotFound(key, location: CSVLocation())
    }

    public static func typeMismatch(expected: String, actual: String) -> CSVDecodingError {
        .typeMismatch(expected: expected, actual: actual, location: CSVLocation())
    }

    public static func parsingError(_ message: String) -> CSVDecodingError {
        .parsingError(message, line: nil, column: nil)
    }

    /// The location where the error occurred, if available.
    public var location: CSVLocation? {
        switch self {
        case .invalidEncoding, .unsupportedType:
            return nil
        case .keyNotFound(_, let location):
            return location
        case .typeMismatch(_, _, let location):
            return location
        case .parsingError(_, let line, let column):
            return CSVLocation(row: line, column: column.map { "character \($0)" })
        }
    }

    public var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "The data could not be decoded with the specified encoding"
        case .keyNotFound(let key, let location):
            let loc = location.row != nil ? " at \(location)" : ""
            var message = "Key '\(key)' not found in CSV row\(loc)"
            if let suggestion = suggestion {
                message += ". \(suggestion)"
            }
            return message
        case .typeMismatch(let expected, let actual, let location):
            let loc = location.row != nil ? " at \(location)" : ""
            var message = "Type mismatch: expected \(expected), found '\(actual)'\(loc)"
            if let suggestion = suggestion {
                message += ". \(suggestion)"
            }
            return message
        case .unsupportedType(let message):
            return "Unsupported operation: \(message)"
        case .parsingError(let message, let line, let column):
            var loc = ""
            if let line = line {
                loc = " at line \(line)"
                if let column = column {
                    loc += ", column \(column)"
                }
            }
            return "Parsing error: \(message)\(loc)"
        }
    }

    // MARK: - Suggestions

    /// Returns a helpful suggestion for fixing the error.
    public var suggestion: String? {
        switch self {
        case .keyNotFound(let key, let location):
            return suggestSimilarKey(key, from: location.availableKeys)

        case .typeMismatch(let expected, let actual, _):
            return suggestTypeFix(expected: expected, actual: actual)

        case .invalidEncoding:
            return "Try using a different encoding (e.g., .utf8, .isoLatin1, .windowsCP1252)"

        case .parsingError(let message, _, _):
            return suggestParsingFix(message)

        case .unsupportedType:
            return nil
        }
    }

    /// Finds similar keys using edit distance.
    private func suggestSimilarKey(_ key: String, from availableKeys: [String]?) -> String? {
        guard let keys = availableKeys, !keys.isEmpty else { return nil }

        // Find the closest match
        let matches = keys
            .map { (key: $0, distance: Self.editDistance($0.lowercased(), key.lowercased())) }
            .filter { $0.distance <= max(3, key.count / 2) } // Allow up to half the key length or 3 edits
            .sorted { $0.distance < $1.distance }

        if let best = matches.first {
            if best.distance == 0 {
                // Case mismatch
                return "Did you mean '\(best.key)'? (case differs)"
            } else if best.distance <= 2 {
                return "Did you mean '\(best.key)'?"
            } else {
                return "Similar columns available: \(matches.prefix(3).map { "'\($0.key)'" }.joined(separator: ", "))"
            }
        }

        // No close match, show available columns
        if keys.count <= 5 {
            return "Available columns: \(keys.map { "'\($0)'" }.joined(separator: ", "))"
        }
        return nil
    }

    /// Suggests fixes for type mismatches.
    private func suggestTypeFix(expected: String, actual: String) -> String? {
        let lowercaseActual = actual.lowercased()

        switch expected {
        case "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64":
            if actual.contains(".") || actual.contains(",") {
                return "Value appears to be a decimal. Use Double or Decimal type, or check for locale-specific formatting"
            }
            if actual.contains("$") || actual.contains("€") || actual.contains("£") {
                return "Value contains currency symbol. Use numberDecodingStrategy: .flexible to strip currency symbols"
            }

        case "Double", "Float", "Decimal":
            if actual.contains(",") && actual.contains(".") {
                return "Value may use European number format (1.234,56). Use numberDecodingStrategy: .flexible or .locale(Locale)"
            }
            if actual.contains("$") || actual.contains("€") || actual.contains("£") {
                return "Value contains currency symbol. Use numberDecodingStrategy: .flexible to strip currency symbols"
            }

        case "Bool":
            let boolLike = ["yes", "no", "true", "false", "1", "0", "oui", "non", "ja", "nein", "да", "нет"]
            if boolLike.contains(lowercaseActual) {
                return "Value '\(actual)' is boolean-like. Use boolDecodingStrategy: .flexible for extended boolean values"
            }

        case "Date":
            if actual.contains("/") || actual.contains("-") || actual.contains(".") {
                return "Value appears to be a date. Use dateDecodingStrategy: .flexible for auto-detection, or .formatted(\"yyyy-MM-dd\") for specific format"
            }
            if Double(actual) != nil {
                return "Value appears to be a timestamp. Use dateDecodingStrategy: .secondsSince1970 or .millisecondsSince1970"
            }

        default:
            break
        }

        return nil
    }

    /// Suggests fixes for parsing errors.
    private func suggestParsingFix(_ message: String) -> String? {
        if message.lowercased().contains("unterminated") || message.lowercased().contains("quote") {
            return "Check for unmatched quotes in the CSV data. Quotes inside fields should be escaped as \"\""
        }
        if message.lowercased().contains("delimiter") {
            return "Try a different delimiter (e.g., semicolon ';' for European CSV, tab '\\t' for TSV)"
        }
        return nil
    }

    /// Computes Levenshtein edit distance between two strings.
    private static func editDistance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        let m = a.count
        let n = b.count

        if m == 0 { return n }
        if n == 0 { return m }

        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,      // deletion
                    curr[j - 1] + 1,  // insertion
                    prev[j - 1] + cost // substitution
                )
            }
            swap(&prev, &curr)
        }

        return prev[n]
    }
}
