//
//  CSVDirectFieldDecoder.swift
//  CSVCoder
//
//  Field-level read helpers for the CSVDirectDecodable fast path.
//
//  The @CSVRow macro emits one helper call per stored property, keeping the
//  generated init small and routing every typed conversion through the same
//  CSVValueParser used by the standard Codable path. Identical inputs
//  produce identical results regardless of which path the decoder takes.
//

import Foundation

/// Field-level read helpers for ``CSVDirectDecodable``-conforming types.
///
/// Each method:
/// - Validates the column was present (`index >= 0`), throwing
///   ``CSVDecodingError/keyNotFound(_:location:)`` otherwise.
/// - Reads the raw field via ``CSVRowView/string(at:encoding:)`` using the
///   configuration's encoding.
/// - Applies `trimWhitespace` if configured.
/// - Delegates type conversion to ``CSVValueParser`` so behaviour matches
///   the standard `Codable` path bit-for-bit.
///
/// The macro-generated init makes one call per stored property; this type
/// is not intended to be called by user code (but is `public` so the
/// macro expansion in user modules links cleanly).
public enum CSVDirectFieldDecoder {
    /// Reads the field at `index` as a raw `String` (after trim).

    public static func string(
        from row: CSVRowView,
        index: Int,
        configuration: CSVDecoder.Configuration,
        key: String,
        rowIndex: Int?,
    ) throws -> String {
        try requireRaw(from: row, index: index, configuration: configuration, key: key, rowIndex: rowIndex)
    }

    /// Reads the field as a `Bool` using the configured ``CSVDecoder/BoolDecodingStrategy``.
    public static func bool(
        from row: CSVRowView,
        index: Int,
        configuration: CSVDecoder.Configuration,
        key: String,
        rowIndex: Int?,
    ) throws -> Bool {
        let raw = try requireRaw(from: row, index: index, configuration: configuration, key: key, rowIndex: rowIndex)
        if let value = CSVValueParser.parseBoolean(raw, strategy: configuration.boolDecodingStrategy) {
            return value
        }
        if case .flexible = configuration.boolDecodingStrategy, let num = Int(raw) {
            return num != 0
        }
        throw CSVDecodingError.typeMismatch(
            expected: "Bool",
            actual: raw,
            location: location(key: key, rowIndex: rowIndex),
        )
    }

    /// Reads the field as a `Double` using the configured ``CSVDecoder/NumberDecodingStrategy``.
    public static func double(
        from row: CSVRowView,
        index: Int,
        configuration: CSVDecoder.Configuration,
        key: String,
        rowIndex: Int?,
    ) throws -> Double {
        let raw = try requireRaw(from: row, index: index, configuration: configuration, key: key, rowIndex: rowIndex)
        guard let value = CSVValueParser.parseDouble(raw, strategy: configuration.numberDecodingStrategy) else {
            throw CSVDecodingError.typeMismatch(
                expected: "Double",
                actual: raw,
                location: location(key: key, rowIndex: rowIndex),
            )
        }
        return value
    }

    /// Reads the field as a `Float`.
    public static func float(
        from row: CSVRowView,
        index: Int,
        configuration: CSVDecoder.Configuration,
        key: String,
        rowIndex: Int?,
    ) throws -> Float {
        let raw = try requireRaw(from: row, index: index, configuration: configuration, key: key, rowIndex: rowIndex)
        guard let value = CSVValueParser.parseDouble(raw, strategy: configuration.numberDecodingStrategy) else {
            throw CSVDecodingError.typeMismatch(
                expected: "Float",
                actual: raw,
                location: location(key: key, rowIndex: rowIndex),
            )
        }
        return Float(value)
    }

    /// Reads the field as `Decimal`.
    public static func decimal(
        from row: CSVRowView,
        index: Int,
        configuration: CSVDecoder.Configuration,
        key: String,
        rowIndex: Int?,
    ) throws -> Decimal {
        let raw = try requireRaw(from: row, index: index, configuration: configuration, key: key, rowIndex: rowIndex)
        guard let value = CSVValueParser.parseDecimal(raw, strategy: configuration.numberDecodingStrategy) else {
            throw CSVDecodingError.typeMismatch(
                expected: "Decimal",
                actual: raw,
                location: location(key: key, rowIndex: rowIndex),
            )
        }
        return value
    }

    /// Reads the field as `UUID`.
    public static func uuid(
        from row: CSVRowView,
        index: Int,
        configuration: CSVDecoder.Configuration,
        key: String,
        rowIndex: Int?,
    ) throws -> UUID {
        let raw = try requireRaw(from: row, index: index, configuration: configuration, key: key, rowIndex: rowIndex)
        guard let value = UUID(uuidString: raw) else {
            throw CSVDecodingError.typeMismatch(
                expected: "UUID",
                actual: raw,
                location: location(key: key, rowIndex: rowIndex),
            )
        }
        return value
    }

    /// Reads the field as `URL`, with strict invalid-character rejection.
    public static func url(
        from row: CSVRowView,
        index: Int,
        configuration: CSVDecoder.Configuration,
        key: String,
        rowIndex: Int?,
    ) throws -> URL {
        let raw = try requireRaw(from: row, index: index, configuration: configuration, key: key, rowIndex: rowIndex)
        guard let value = URL(string: raw, encodingInvalidCharacters: false) else {
            throw CSVDecodingError.typeMismatch(
                expected: "URL",
                actual: raw,
                location: location(key: key, rowIndex: rowIndex),
            )
        }
        return value
    }

    /// Reads the field as `Date` using the configured ``CSVDecoder/DateDecodingStrategy``.
    public static func date(
        from row: CSVRowView,
        index: Int,
        configuration: CSVDecoder.Configuration,
        key: String,
        rowIndex: Int?,
    ) throws -> Date {
        let raw = try requireRaw(from: row, index: index, configuration: configuration, key: key, rowIndex: rowIndex)
        return try CSVValueParser.parseDate(
            from: raw,
            strategy: configuration.dateDecodingStrategy,
            codingPath: [],
            row: rowIndex,
            column: key,
        )
    }

    // MARK: - Fixed-width integers

    /// Reads the field as a fixed-width integer of arbitrary type, applying
    /// the configured ``CSVDecoder/NumberDecodingStrategy`` and bounds-checking
    /// the result to the target type's range.

    public static func integer<I: FixedWidthInteger>(
        _ type: I.Type,
        from row: CSVRowView,
        index: Int,
        configuration: CSVDecoder.Configuration,
        key: String,
        rowIndex: Int?,
    ) throws -> I {
        let raw = try requireRaw(from: row, index: index, configuration: configuration, key: key, rowIndex: rowIndex)
        guard let int64 = CSVValueParser.parseInt64(raw, strategy: configuration.numberDecodingStrategy),
            let narrowed = I(exactly: int64)
        else {
            throw CSVDecodingError.typeMismatch(
                expected: String(describing: I.self),
                actual: raw,
                location: location(key: key, rowIndex: rowIndex),
            )
        }
        return narrowed
    }

    /// Variant that accepts values outside `Int64.max` (e.g., `UInt64` values
    /// up to `UInt64.max`). Uses direct `UInt64(_:)` parsing on `.standard`
    /// strategy, otherwise routes through the standard `parseInt64` path.
    public static func uInt64(
        from row: CSVRowView,
        index: Int,
        configuration: CSVDecoder.Configuration,
        key: String,
        rowIndex: Int?,
    ) throws -> UInt64 {
        let raw = try requireRaw(from: row, index: index, configuration: configuration, key: key, rowIndex: rowIndex)
        if case .standard = configuration.numberDecodingStrategy, let direct = UInt64(raw) {
            return direct
        }
        guard let int64 = CSVValueParser.parseInt64(raw, strategy: configuration.numberDecodingStrategy),
            let value = UInt64(exactly: int64)
        else {
            throw CSVDecodingError.typeMismatch(
                expected: "UInt64",
                actual: raw,
                location: location(key: key, rowIndex: rowIndex),
            )
        }
        return value
    }

    // MARK: - Optional helpers

    /// Optional-aware string read: returns `nil` when the raw value matches the
    /// configured ``CSVDecoder/NilDecodingStrategy``, the column is absent
    /// (`index < 0`), or the column slot is missing from this row.

    public static func optionalString(
        from row: CSVRowView,
        index: Int,
        configuration: CSVDecoder.Configuration,
    ) -> String? {
        guard let raw = readOptionalRaw(from: row, index: index, configuration: configuration) else {
            return nil
        }
        return raw
    }

    /// Optional-aware bool read.
    public static func optionalBool(
        from row: CSVRowView,
        index: Int,
        configuration: CSVDecoder.Configuration,
        key: String,
        rowIndex: Int?,
    ) throws -> Bool? {
        guard let raw = readOptionalRaw(from: row, index: index, configuration: configuration) else { return nil }
        if let value = CSVValueParser.parseBoolean(raw, strategy: configuration.boolDecodingStrategy) {
            return value
        }
        if case .flexible = configuration.boolDecodingStrategy, let num = Int(raw) {
            return num != 0
        }
        throw CSVDecodingError.typeMismatch(
            expected: "Bool",
            actual: raw,
            location: location(key: key, rowIndex: rowIndex),
        )
    }

    /// Optional-aware double read.
    public static func optionalDouble(
        from row: CSVRowView,
        index: Int,
        configuration: CSVDecoder.Configuration,
        key: String,
        rowIndex: Int?,
    ) throws -> Double? {
        guard let raw = readOptionalRaw(from: row, index: index, configuration: configuration) else { return nil }
        guard let value = CSVValueParser.parseDouble(raw, strategy: configuration.numberDecodingStrategy) else {
            throw CSVDecodingError.typeMismatch(
                expected: "Double",
                actual: raw,
                location: location(key: key, rowIndex: rowIndex),
            )
        }
        return value
    }

    /// Optional-aware integer read.

    public static func optionalInteger<I: FixedWidthInteger>(
        _ type: I.Type,
        from row: CSVRowView,
        index: Int,
        configuration: CSVDecoder.Configuration,
        key: String,
        rowIndex: Int?,
    ) throws -> I? {
        guard let raw = readOptionalRaw(from: row, index: index, configuration: configuration) else { return nil }
        guard let int64 = CSVValueParser.parseInt64(raw, strategy: configuration.numberDecodingStrategy),
            let narrowed = I(exactly: int64)
        else {
            throw CSVDecodingError.typeMismatch(
                expected: String(describing: I.self),
                actual: raw,
                location: location(key: key, rowIndex: rowIndex),
            )
        }
        return narrowed
    }

    /// Optional-aware date read.
    public static func optionalDate(
        from row: CSVRowView,
        index: Int,
        configuration: CSVDecoder.Configuration,
        key: String,
        rowIndex: Int?,
    ) throws -> Date? {
        guard let raw = readOptionalRaw(from: row, index: index, configuration: configuration) else { return nil }
        return try CSVValueParser.parseDate(
            from: raw,
            strategy: configuration.dateDecodingStrategy,
            codingPath: [],
            row: rowIndex,
            column: key,
        )
    }

    /// Optional-aware UUID read.
    public static func optionalUUID(
        from row: CSVRowView,
        index: Int,
        configuration: CSVDecoder.Configuration,
        key: String,
        rowIndex: Int?,
    ) throws -> UUID? {
        guard let raw = readOptionalRaw(from: row, index: index, configuration: configuration) else { return nil }
        guard let value = UUID(uuidString: raw) else {
            throw CSVDecodingError.typeMismatch(
                expected: "UUID",
                actual: raw,
                location: location(key: key, rowIndex: rowIndex),
            )
        }
        return value
    }

    /// Optional-aware URL read (strict).
    public static func optionalURL(
        from row: CSVRowView,
        index: Int,
        configuration: CSVDecoder.Configuration,
        key: String,
        rowIndex: Int?,
    ) throws -> URL? {
        guard let raw = readOptionalRaw(from: row, index: index, configuration: configuration) else { return nil }
        guard let value = URL(string: raw, encodingInvalidCharacters: false) else {
            throw CSVDecodingError.typeMismatch(
                expected: "URL",
                actual: raw,
                location: location(key: key, rowIndex: rowIndex),
            )
        }
        return value
    }

    /// Optional-aware Decimal read.
    public static func optionalDecimal(
        from row: CSVRowView,
        index: Int,
        configuration: CSVDecoder.Configuration,
        key: String,
        rowIndex: Int?,
    ) throws -> Decimal? {
        guard let raw = readOptionalRaw(from: row, index: index, configuration: configuration) else { return nil }
        guard let value = CSVValueParser.parseDecimal(raw, strategy: configuration.numberDecodingStrategy) else {
            throw CSVDecodingError.typeMismatch(
                expected: "Decimal",
                actual: raw,
                location: location(key: key, rowIndex: rowIndex),
            )
        }
        return value
    }

    // MARK: - Private

    /// Reads the raw trimmed string at `index`, throwing if the column is
    /// absent or the field cannot be materialised in the configured encoding.

    static func requireRaw(
        from row: CSVRowView,
        index: Int,
        configuration: CSVDecoder.Configuration,
        key: String,
        rowIndex: Int?,
    ) throws -> String {
        guard index >= 0, index < row.count else {
            throw CSVDecodingError.keyNotFound(
                key,
                location: location(key: key, rowIndex: rowIndex),
            )
        }
        guard let value = row.string(at: index, encoding: configuration.encoding) else {
            throw CSVDecodingError.keyNotFound(
                key,
                location: location(key: key, rowIndex: rowIndex),
            )
        }
        return configuration.trimWhitespace ? value.trimmingCharacters(in: .whitespaces) : value
    }

    /// Returns the trimmed raw string, or `nil` if the column is missing or
    /// the value matches the configured nil strategy.

    static func readOptionalRaw(
        from row: CSVRowView,
        index: Int,
        configuration: CSVDecoder.Configuration,
    ) -> String? {
        guard index >= 0, index < row.count else { return nil }
        guard let value = row.string(at: index, encoding: configuration.encoding) else { return nil }
        let trimmed = configuration.trimWhitespace ? value.trimmingCharacters(in: .whitespaces) : value
        switch configuration.nilDecodingStrategy {
        case .emptyString:
            return trimmed.isEmpty ? nil : trimmed

        case .nullLiteral:
            return trimmed.isEmpty || trimmed.lowercased() == "null" ? nil : trimmed

        case .custom(let nilValues):
            return trimmed.isEmpty || nilValues.contains(trimmed) ? nil : trimmed
        }
    }

    static func location(key: String, rowIndex: Int?) -> CSVLocation {
        CSVLocation(row: rowIndex, column: key)
    }
}
