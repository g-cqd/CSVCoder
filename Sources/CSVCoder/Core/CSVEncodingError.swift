//
//  CSVEncodingError.swift
//  CSVCoder
//
//  Error types for CSV encoding.
//

import Foundation

/// Errors that can occur during CSV encoding.
public enum CSVEncodingError: Error, LocalizedError, Sendable {
    /// The value could not be encoded to the expected type.
    case invalidValue(String)

    /// The requested operation is not supported for CSV encoding.
    case unsupportedType(String)

    /// A required key was missing during encoding.
    case missingKey(String)

    /// The encoding produced invalid output.
    case invalidOutput(String)

    public var errorDescription: String? {
        switch self {
        case .invalidValue(let message):
            return "Invalid value: \(message)"
        case .unsupportedType(let message):
            return "Unsupported operation: \(message)"
        case .missingKey(let key):
            return "Missing key '\(key)' during encoding"
        case .invalidOutput(let message):
            return "Invalid output: \(message)"
        }
    }
}
