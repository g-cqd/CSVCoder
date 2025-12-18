//
//  CSVDecodingError.swift
//  CSVCoder
//
//  Error types for CSV decoding.
//

import Foundation

/// Errors that can occur during CSV decoding.
public enum CSVDecodingError: Error, LocalizedError, Sendable {
    /// The data could not be decoded with the specified encoding.
    case invalidEncoding

    /// A required key was not found in the CSV row.
    case keyNotFound(String)

    /// The value could not be converted to the expected type.
    case typeMismatch(expected: String, actual: String)

    /// The requested operation is not supported for CSV decoding.
    case unsupportedType(String)

    /// A parsing error occurred.
    case parsingError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "The data could not be decoded with the specified encoding"
        case .keyNotFound(let key):
            return "Key '\(key)' not found in CSV row"
        case .typeMismatch(let expected, let actual):
            return "Type mismatch: expected \(expected), found '\(actual)'"
        case .unsupportedType(let message):
            return "Unsupported operation: \(message)"
        case .parsingError(let message):
            return "Parsing error: \(message)"
        }
    }
}
