//
//  CSVEncodingError.swift
//  CSVCoder
//
//  Error types for CSV encoding.
//

import Foundation

// MARK: - CSVEncodingError

/// Errors that occur during CSV encoding.
///
/// These errors indicate issues with the data being encoded, such as
/// unsupported types or invalid values that cannot be represented in CSV format.
///
/// ## Common Causes
///
/// - **unsupportedType**: Nested collections or unhandled `Codable` types
///   without a ``CSVEncoder/NestedTypeEncodingStrategy``
/// - **invalidValue**: Values that cannot be converted to valid CSV strings
/// - **missingKey**: Internal error when a key is unexpectedly absent
///
/// ## Handling Nested Types
///
/// By default, the encoder throws for nested types. Configure handling:
///
/// ```swift
/// var config = CSVEncoder.Configuration()
/// config.nestedTypeEncodingStrategy = .json  // Encode as JSON string
/// // or
/// config.nestedTypeEncodingStrategy = .flatten(separator: "_")
/// ```
///
/// ## See Also
///
/// - ``CSVEncoder/NestedTypeEncodingStrategy``
/// - ``CSVDecodingError`` for decode-side errors
public enum CSVEncodingError: Error, LocalizedError, Sendable {
    /// The value could not be encoded to the expected type.
    case invalidValue(String)

    /// The requested operation is not supported for CSV encoding.
    case unsupportedType(String)

    /// A required key was missing during encoding.
    case missingKey(String)

    /// The encoding produced invalid output.
    case invalidOutput(String)

    // MARK: Public

    public var errorDescription: String? {
        switch self {
        case .invalidValue(let message):
            "Invalid value: \(message)"

        case .unsupportedType(let message):
            "Unsupported operation: \(message)"

        case .missingKey(let key):
            "Missing key '\(key)' during encoding"

        case .invalidOutput(let message):
            "Invalid output: \(message)"
        }
    }
}
