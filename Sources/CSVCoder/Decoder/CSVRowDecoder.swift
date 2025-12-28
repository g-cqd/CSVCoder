//
//  CSVRowDecoder.swift
//  CSVCoder
//
//  Implements the Decoder protocol for CSV row decoding.
//

import Foundation

/// A decoder for a single CSV row.
struct CSVRowDecoder: Decoder {
    enum RowSource {
        case dictionary([String: String])
        case view(CSVRowView, headerMap: [String: Int])
    }

    let source: RowSource
    let configuration: CSVDecoder.Configuration
    let codingPath: [CodingKey]
    let rowIndex: Int?
    /// The effective encoding to use for string conversion (may differ from configuration.encoding after transcoding).
    let encoding: String.Encoding
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    init(row: [String: String], configuration: CSVDecoder.Configuration, codingPath: [CodingKey], rowIndex: Int? = nil) {
        self.source = .dictionary(row)
        self.configuration = configuration
        self.codingPath = codingPath
        self.rowIndex = rowIndex
        self.encoding = .utf8  // Dictionary source uses pre-decoded strings
    }

    init(view: CSVRowView, headerMap: [String: Int], configuration: CSVDecoder.Configuration, codingPath: [CodingKey], rowIndex: Int? = nil, encoding: String.Encoding = .utf8) {
        self.source = .view(view, headerMap: headerMap)
        self.configuration = configuration
        self.codingPath = codingPath
        self.rowIndex = rowIndex
        self.encoding = encoding
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        KeyedDecodingContainer(CSVKeyedDecodingContainer(source: source, configuration: configuration, codingPath: codingPath, rowIndex: rowIndex, encoding: encoding))
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        throw CSVDecodingError.unsupportedType("Unkeyed containers are not supported in CSV decoding")
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        throw CSVDecodingError.unsupportedType("Single value containers are not supported at root level")
    }
}

/// A keyed decoding container for CSV data.
struct CSVKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let source: CSVRowDecoder.RowSource
    let configuration: CSVDecoder.Configuration
    let codingPath: [CodingKey]
    let rowIndex: Int?
    let keyPrefix: String?
    /// The effective encoding to use for string conversion from CSVRowView.
    let encoding: String.Encoding

    init(source: CSVRowDecoder.RowSource, configuration: CSVDecoder.Configuration, codingPath: [CodingKey], rowIndex: Int?, keyPrefix: String? = nil, encoding: String.Encoding = .utf8) {
        self.source = source
        self.configuration = configuration
        self.codingPath = codingPath
        self.rowIndex = rowIndex
        self.keyPrefix = keyPrefix
        self.encoding = encoding
    }

    var allKeys: [Key] {
        switch source {
        case .dictionary(let row):
            return row.keys.compactMap { Key(stringValue: $0) }
        case .view(_, let headerMap):
            return headerMap.keys.compactMap { Key(stringValue: $0) }
        }
    }

    func contains(_ key: Key) -> Bool {
        switch source {
        case .dictionary(let row):
            return row[key.stringValue] != nil
        case .view(let view, let headerMap):
            guard let index = headerMap[key.stringValue] else { return false }
            return index < view.count
        }
    }

    private func makeLocation(for key: Key, includeAvailableKeys: Bool = false) -> CSVLocation {
        let keys: [String]?
        switch source {
        case .dictionary(let row): keys = includeAvailableKeys ? Array(row.keys) : nil
        case .view(_, let headerMap): keys = includeAvailableKeys ? Array(headerMap.keys) : nil
        }
        
        return CSVLocation(
            row: rowIndex,
            column: key.stringValue,
            codingPath: codingPath + [key],
            availableKeys: keys
        )
    }

    private func getValue(for key: Key) throws -> String {
        let rawValue: String
        switch source {
        case .dictionary(let row):
            guard let value = row[key.stringValue] else {
                throw CSVDecodingError.keyNotFound(
                    key.stringValue,
                    location: makeLocation(for: key, includeAvailableKeys: true)
                )
            }
            rawValue = value

        case .view(let view, let headerMap):
            guard let index = headerMap[key.stringValue], index < view.count else {
                throw CSVDecodingError.keyNotFound(
                    key.stringValue,
                    location: makeLocation(for: key, includeAvailableKeys: true)
                )
            }
            // Decode string on demand using the effective encoding
            guard let value = view.string(at: index, encoding: encoding) else {
                throw CSVDecodingError.keyNotFound(
                    key.stringValue,
                    location: makeLocation(for: key, includeAvailableKeys: true)
                )
            }
            rawValue = value
        }

        // Apply trimWhitespace configuration
        return configuration.trimWhitespace ? rawValue.trimmingCharacters(in: .whitespaces) : rawValue
    }

    /// Returns the string value for a key, or nil if not present.
    private func stringValue(forKey key: Key) -> String? {
        switch source {
        case .dictionary(let row):
            return row[key.stringValue]
        case .view(let view, let headerMap):
            guard let index = headerMap[key.stringValue], index < view.count else { return nil }
            return view.string(at: index)
        }
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        let value: String?
        switch source {
        case .dictionary(let row):
            guard let v = row[key.stringValue] else { return true }
            value = v

        case .view(let view, let headerMap):
            guard let index = headerMap[key.stringValue] else { return true }
            if index >= view.count { return true }
            guard let v = view.string(at: index) else { return true }
            value = v
        }

        guard let value = value else { return true }

        // Apply nil decoding strategy
        switch configuration.nilDecodingStrategy {
        case .emptyString:
            return value.isEmpty
        case .nullLiteral:
            let lowered = value.lowercased()
            return value.isEmpty || lowered == "null"
        case .custom(let nilValues):
            return value.isEmpty || nilValues.contains(value)
        }
    }

    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
        let value = try getValue(for: key).lowercased()
        let location = makeLocation(for: key)

        switch configuration.boolDecodingStrategy {
        case .standard:
            switch value {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: throw CSVDecodingError.typeMismatch(expected: "Bool", actual: value, location: location)
            }

        case .flexible:
            if flexibleTrueValues.contains(value) { return true }
            if flexibleFalseValues.contains(value) { return false }
            // Try numeric: any non-zero is true
            if let num = Int(value) { return num != 0 }
            throw CSVDecodingError.typeMismatch(expected: "Bool", actual: value, location: location)

        case .custom(let trueValues, let falseValues):
            if trueValues.contains(value) { return true }
            if falseValues.contains(value) { return false }
            throw CSVDecodingError.typeMismatch(expected: "Bool", actual: value, location: location)
        }
    }

    // MARK: - Flexible Boolean Values (i18n)

    private var flexibleTrueValues: Set<String> {
        ["true", "yes", "1", "y", "t", "on", "full", "fulltank",
         "oui", "si", "ja", "да", "是", "満", "voll", "真", "sí"]
    }

    private var flexibleFalseValues: Set<String> {
        ["false", "no", "0", "n", "f", "off", "partial", "partialtank",
         "non", "nein", "нет", "否", "部分", "假"]
    }

    func decode(_ type: String.Type, forKey key: Key) throws -> String {
        try getValue(for: key)
    }

    func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
        let value = try getValue(for: key)
        guard let result = parseDouble(value) else {
            throw CSVDecodingError.typeMismatch(expected: "Double", actual: value, location: makeLocation(for: key))
        }
        return result
    }

    func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
        let value = try getValue(for: key)
        guard let result = parseDouble(value) else {
            throw CSVDecodingError.typeMismatch(expected: "Float", actual: value, location: makeLocation(for: key))
        }
        return Float(result)
    }

    // MARK: - Flexible Number Parsing

    private func parseDouble(_ value: String) -> Double? {
        switch configuration.numberDecodingStrategy {
        case .standard:
            return Double(value)

        case .flexible:
            return parseFlexibleDouble(value)

        case .locale(let locale):
            let formatter = NumberFormatter()
            formatter.locale = locale
            formatter.numberStyle = .decimal
            return formatter.number(from: value)?.doubleValue

        case .parseStrategy(let locale):
            if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
                return LocaleUtilities.parseDouble(value, locale: locale)
            } else {
                return parseFlexibleDouble(value)
            }

        case .currency(_, let locale):
            if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
                return LocaleUtilities.parseDecimal(value, locale: locale).flatMap { Double(truncating: $0 as NSDecimalNumber) }
            } else {
                return parseFlexibleDouble(value)
            }
        }
    }

    /// Parses a Decimal value using the configured strategy.
    private func parseDecimal(_ value: String) -> Decimal? {
        switch configuration.numberDecodingStrategy {
        case .standard:
            return Decimal(string: value)

        case .flexible:
            // Normalize the string first, then parse as Decimal
            guard let cleaned = normalizeNumberString(value) else { return nil }
            return Decimal(string: cleaned)

        case .locale(let locale):
            let formatter = NumberFormatter()
            formatter.locale = locale
            formatter.numberStyle = .decimal
            return formatter.number(from: value)?.decimalValue

        case .parseStrategy(let locale):
            if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
                return LocaleUtilities.parseDecimal(value, locale: locale)
            } else {
                guard let cleaned = normalizeNumberString(value) else { return nil }
                return Decimal(string: cleaned)
            }

        case .currency(let code, let locale):
            if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
                return LocaleUtilities.parseCurrency(value, code: code, locale: locale)
            } else {
                guard let cleaned = normalizeNumberString(value) else { return nil }
                return Decimal(string: cleaned)
            }
        }
    }

    /// Normalizes a number string by removing currency and fixing decimal separators.
    private func normalizeNumberString(_ value: String) -> String? {
        // Use LocaleUtilities to strip currency symbols and units
        var cleaned = LocaleUtilities.stripCurrencyAndUnits(value)
        guard !cleaned.isEmpty else { return nil }

        let hasComma = cleaned.contains(",")
        let hasDot = cleaned.contains(".")

        if hasComma && hasDot {
            if let lastComma = cleaned.lastIndex(of: ","),
               let lastDot = cleaned.lastIndex(of: ".") {
                if lastComma > lastDot {
                    cleaned = cleaned.replacingOccurrences(of: ".", with: "")
                    cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
                } else {
                    cleaned = cleaned.replacingOccurrences(of: ",", with: "")
                }
            }
        } else if hasComma && !hasDot {
            let parts = cleaned.split(separator: ",")
            if parts.count == 2 && parts[1].count <= 2 {
                cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
            } else {
                cleaned = cleaned.replacingOccurrences(of: ",", with: "")
            }
        }

        cleaned = String(cleaned.filter { $0.isNumber || $0 == "." || $0 == "-" })
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Parses a numeric value handling various decimal separators and currency symbols.
    /// Supports both US (1,234.56) and EU (1.234,56) formats.
    private func parseFlexibleDouble(_ value: String) -> Double? {
        // Use LocaleUtilities to strip currency symbols and units
        var cleaned = LocaleUtilities.stripCurrencyAndUnits(value)
        guard !cleaned.isEmpty else { return nil }

        // Detect format: if both . and , exist, the last one is decimal separator
        let hasComma = cleaned.contains(",")
        let hasDot = cleaned.contains(".")

        if hasComma && hasDot {
            // Both exist: last occurrence is decimal separator
            if let lastComma = cleaned.lastIndex(of: ","),
               let lastDot = cleaned.lastIndex(of: ".") {
                if lastComma > lastDot {
                    // Comma is decimal (European: 1.234,56)
                    cleaned = cleaned.replacingOccurrences(of: ".", with: "")
                    cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
                } else {
                    // Dot is decimal (US: 1,234.56)
                    cleaned = cleaned.replacingOccurrences(of: ",", with: "")
                }
            }
        } else if hasComma && !hasDot {
            // Only comma: check if it's thousands or decimal
            let parts = cleaned.split(separator: ",")
            if parts.count == 2 && parts[1].count <= 2 {
                // Likely decimal (45,50 = 45.50)
                cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
            } else {
                // Likely thousands separator (1,234 = 1234)
                cleaned = cleaned.replacingOccurrences(of: ",", with: "")
            }
        }
        // If only dot, it's already in the right format

        // Remove any remaining non-numeric characters except . and -
        cleaned = String(cleaned.filter { $0.isNumber || $0 == "." || $0 == "-" })

        return Double(cleaned)
    }

    func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
        let value = try getValue(for: key)
        guard let result = Int(value) else {
            throw CSVDecodingError.typeMismatch(expected: "Int", actual: value, location: makeLocation(for: key))
        }
        return result
    }

    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
        let value = try getValue(for: key)
        guard let result = Int8(value) else {
            throw CSVDecodingError.typeMismatch(expected: "Int8", actual: value, location: makeLocation(for: key))
        }
        return result
    }

    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
        let value = try getValue(for: key)
        guard let result = Int16(value) else {
            throw CSVDecodingError.typeMismatch(expected: "Int16", actual: value, location: makeLocation(for: key))
        }
        return result
    }

    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
        let value = try getValue(for: key)
        guard let result = Int32(value) else {
            throw CSVDecodingError.typeMismatch(expected: "Int32", actual: value, location: makeLocation(for: key))
        }
        return result
    }

    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
        let value = try getValue(for: key)
        guard let result = Int64(value) else {
            throw CSVDecodingError.typeMismatch(expected: "Int64", actual: value, location: makeLocation(for: key))
        }
        return result
    }

    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
        let value = try getValue(for: key)
        guard let result = UInt(value) else {
            throw CSVDecodingError.typeMismatch(expected: "UInt", actual: value, location: makeLocation(for: key))
        }
        return result
    }

    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
        let value = try getValue(for: key)
        guard let result = UInt8(value) else {
            throw CSVDecodingError.typeMismatch(expected: "UInt8", actual: value, location: makeLocation(for: key))
        }
        return result
    }

    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
        let value = try getValue(for: key)
        guard let result = UInt16(value) else {
            throw CSVDecodingError.typeMismatch(expected: "UInt16", actual: value, location: makeLocation(for: key))
        }
        return result
    }

    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
        let value = try getValue(for: key)
        guard let result = UInt32(value) else {
            throw CSVDecodingError.typeMismatch(expected: "UInt32", actual: value, location: makeLocation(for: key))
        }
        return result
    }

    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
        let value = try getValue(for: key)
        guard let result = UInt64(value) else {
            throw CSVDecodingError.typeMismatch(expected: "UInt64", actual: value, location: makeLocation(for: key))
        }
        return result
    }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        // Check if key exists - if not, check for nested type strategies
        let keyExists: Bool
        switch source {
        case .dictionary(let row):
            keyExists = row[key.stringValue] != nil
        case .view(let view, let headerMap):
            if let index = headerMap[key.stringValue] {
                keyExists = index < view.count
            } else {
                keyExists = false
            }
        }

        // Handle nested types based on strategy
        switch configuration.nestedTypeDecodingStrategy {
        case .flatten(let separator):
            // Check if this is a nested type by looking for prefixed keys
            let prefix = key.stringValue + separator
            let hasPrefixedKeys: Bool
            switch source {
            case .dictionary(let row):
                hasPrefixedKeys = row.keys.contains { $0.hasPrefix(prefix) }
            case .view(_, let headerMap):
                hasPrefixedKeys = headerMap.keys.contains { $0.hasPrefix(prefix) }
            }

            if hasPrefixedKeys && !keyExists {
                // Decode as nested type with prefixed keys
                let nestedSource = createPrefixedSource(prefix: prefix)
                let decoder = CSVNestedRowDecoder(
                    source: nestedSource,
                    configuration: configuration,
                    codingPath: codingPath + [key],
                    rowIndex: rowIndex
                )
                return try T(from: decoder)
            }

        case .json, .codable:
            // For JSON/codable, the value should exist and be a JSON string
            if keyExists {
                let value = try getValue(for: key)
                guard let data = value.data(using: .utf8) else {
                    throw CSVDecodingError.typeMismatch(expected: "valid UTF-8 JSON", actual: value, location: makeLocation(for: key))
                }
                return try JSONDecoder().decode(T.self, from: data)
            }

        case .error:
            break
        }

        // Get value for standard decoding
        let value = try getValue(for: key)
        let location = makeLocation(for: key)

        // Handle Date specially
        if type == Date.self {
            return try decodeDate(from: value, key: key) as! T
        }

        // Handle Decimal specially
        if type == Decimal.self {
            guard let decimal = parseDecimal(value) else {
                throw CSVDecodingError.typeMismatch(expected: "Decimal", actual: value, location: location)
            }
            return decimal as! T
        }

        // Handle UUID specially
        if type == UUID.self {
            guard let uuid = UUID(uuidString: value) else {
                throw CSVDecodingError.typeMismatch(expected: "UUID", actual: value, location: location)
            }
            return uuid as! T
        }

        // Handle URL specially
        if type == URL.self {
            guard let url = URL(string: value) else {
                throw CSVDecodingError.typeMismatch(expected: "URL", actual: value, location: location)
            }
            return url as! T
        }

        // Handle Optional types
        if let optionalType = T.self as? OptionalDecodable.Type {
            if value.isEmpty {
                return optionalType.nilValue as! T
            }
        }

        // Try to decode using single value container
        let singleValueDecoder = CSVSingleValueDecoder(
            value: value,
            configuration: configuration,
            codingPath: codingPath + [key]
        )
        return try T(from: singleValueDecoder)
    }

    private func decodeDate<K: CodingKey>(from value: String, key: K) throws -> Date {
        let location = CSVLocation(row: rowIndex, column: key.stringValue, codingPath: codingPath + [key])

        switch configuration.dateDecodingStrategy {
        case .deferredToDate:
            throw CSVDecodingError.typeMismatch(expected: "Date (use a date strategy)", actual: value, location: location)

        case .secondsSince1970:
            guard let seconds = Double(value) else {
                throw CSVDecodingError.typeMismatch(expected: "Unix timestamp", actual: value, location: location)
            }
            return Date(timeIntervalSince1970: seconds)

        case .millisecondsSince1970:
            guard let milliseconds = Double(value) else {
                throw CSVDecodingError.typeMismatch(expected: "Unix timestamp (ms)", actual: value, location: location)
            }
            return Date(timeIntervalSince1970: milliseconds / 1000)

        case .iso8601:
            let formatter = ISO8601DateFormatter()
            guard let date = formatter.date(from: value) else {
                throw CSVDecodingError.typeMismatch(expected: "ISO8601 date", actual: value, location: location)
            }
            return date

        case .formatted(let format):
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale.autoupdatingCurrent
            formatter.timeZone = TimeZone.autoupdatingCurrent
            guard let date = formatter.date(from: value) else {
                throw CSVDecodingError.typeMismatch(expected: "Date with format \(format)", actual: value, location: location)
            }
            return date

        case .custom(let closure):
            return try closure(value)

        case .flexible:
            guard let date = parseFlexibleDate(value, hint: nil) else {
                throw CSVDecodingError.typeMismatch(expected: "Date (no matching format found)", actual: value, location: location)
            }
            return date

        case .flexibleWithHint(let preferred):
            guard let date = parseFlexibleDate(value, hint: preferred) else {
                throw CSVDecodingError.typeMismatch(expected: "Date (no matching format found)", actual: value, location: location)
            }
            return date

        case .localeAware(let locale, let style):
            if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
                if let date = LocaleUtilities.parseDate(value, locale: locale, style: style) {
                    return date
                }
                // Fall back to flexible parsing if locale-aware fails
                if let date = parseFlexibleDate(value, hint: nil) {
                    return date
                }
                throw CSVDecodingError.typeMismatch(expected: "Date (locale-aware)", actual: value, location: location)
            } else {
                // Pre-iOS 15: use flexible parsing
                guard let date = parseFlexibleDate(value, hint: nil) else {
                    throw CSVDecodingError.typeMismatch(expected: "Date", actual: value, location: location)
                }
                return date
            }
        }
    }

    // MARK: - Flexible Date Parsing

    /// Common date formats to try, in order of prevalence.
    private var dateFormats: [String] {[
        // ISO 8601
        "yyyy-MM-dd",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd'T'HH:mm:ssZ",
        "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd HH:mm",

        // European (day first)
        "dd/MM/yyyy",
        "dd-MM-yyyy",
        "dd.MM.yyyy",
        "dd/MM/yy",
        "dd-MM-yy",
        "dd.MM.yy",

        // US (month first)
        "MM/dd/yyyy",
        "MM-dd-yyyy",
        "MM/dd/yy",
        "MM-dd-yy",

        // With time
        "dd/MM/yyyy HH:mm",
        "dd/MM/yyyy HH:mm:ss",
        "MM/dd/yyyy HH:mm",
        "MM/dd/yyyy HH:mm:ss",

        // Compact
        "yyyyMMdd",
        "ddMMyyyy",

        // Verbose
        "MMMM d, yyyy",
        "d MMMM yyyy",
        "MMM d, yyyy",
        "d MMM yyyy"
    ]}

    /// Attempts to parse a date string using multiple formats.
    private func parseFlexibleDate(_ value: String, hint: String?) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        // Try hint first if provided
        if let hint = hint {
            formatter.dateFormat = hint
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }

        // Try all known formats
        for format in dateFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }

        // Try relative date expressions
        return parseRelativeDate(trimmed)
    }

    /// Parses relative date expressions like "today", "yesterday".
    private func parseRelativeDate(_ value: String) -> Date? {
        let lower = value.lowercased()
        let calendar = Calendar.current

        switch lower {
        case "today":
            return calendar.startOfDay(for: Date())
        case "yesterday":
            return calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))
        default:
            return nil
        }
    }

    func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
        switch configuration.nestedTypeDecodingStrategy {
        case .error:
            throw CSVDecodingError.unsupportedType("Nested containers are not supported in CSV. Configure nestedTypeDecodingStrategy to enable.")

        case .flatten(let separator):
            // Create a container that reads keys with prefix "key<separator>"
            let prefix = key.stringValue + separator
            let nestedSource = createPrefixedSource(prefix: prefix)
            let nestedContainer = CSVKeyedDecodingContainer<NestedKey>(
                source: nestedSource,
                configuration: configuration,
                codingPath: codingPath + [key],
                rowIndex: rowIndex,
                keyPrefix: prefix
            )
            return KeyedDecodingContainer(nestedContainer)

        case .json:
            // Get the field value and decode as JSON
            guard let jsonString = stringValue(forKey: key) else {
                throw CSVDecodingError.keyNotFound(key.stringValue, location: makeLocation(for: key, includeAvailableKeys: true))
            }
            guard let jsonData = jsonString.data(using: .utf8) else {
                throw CSVDecodingError.typeMismatch(expected: "valid UTF-8 JSON string", actual: jsonString, location: makeLocation(for: key))
            }
            let jsonDecoder = JSONDecoder()
            // Create a wrapper that returns a keyed container from JSON
            let jsonContainer = try jsonDecoder.decode(NestedJSONContainer<NestedKey>.self, from: jsonData)
            return KeyedDecodingContainer(jsonContainer.container)

        case .codable:
            // Get the field value as Data and use it directly
            guard let fieldValue = stringValue(forKey: key) else {
                throw CSVDecodingError.keyNotFound(key.stringValue, location: makeLocation(for: key, includeAvailableKeys: true))
            }
            guard let data = fieldValue.data(using: .utf8) else {
                throw CSVDecodingError.typeMismatch(expected: "valid UTF-8 data", actual: fieldValue, location: makeLocation(for: key))
            }
            // Try JSON first as the most common Codable format
            let jsonDecoder = JSONDecoder()
            let jsonContainer = try jsonDecoder.decode(NestedJSONContainer<NestedKey>.self, from: data)
            return KeyedDecodingContainer(jsonContainer.container)
        }
    }

    /// Creates a source filtered to keys with the given prefix, stripping the prefix.
    private func createPrefixedSource(prefix: String) -> CSVRowDecoder.RowSource {
        switch source {
        case .dictionary(let row):
            var filtered: [String: String] = [:]
            for (key, value) in row where key.hasPrefix(prefix) {
                let strippedKey = String(key.dropFirst(prefix.count))
                filtered[strippedKey] = value
            }
            return .dictionary(filtered)

        case .view(let view, let headerMap):
            var filtered: [String: Int] = [:]
            for (key, index) in headerMap where key.hasPrefix(prefix) {
                let strippedKey = String(key.dropFirst(prefix.count))
                filtered[strippedKey] = index
            }
            return .view(view, headerMap: filtered)
        }
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        throw CSVDecodingError.unsupportedType("Nested unkeyed containers (arrays) are not supported in CSV")
    }

    func superDecoder() throws -> Decoder {
        throw CSVDecodingError.unsupportedType("Super decoder is not supported in CSV")
    }

    func superDecoder(forKey key: Key) throws -> Decoder {
        throw CSVDecodingError.unsupportedType("Super decoder is not supported in CSV")
    }
}

/// Protocol for handling optional decoding.
private protocol OptionalDecodable {
    static var nilValue: Any { get }
}

extension Optional: OptionalDecodable {
    static var nilValue: Any { Self.none as Any }
}

// MARK: - Nested JSON Decoding Support

/// A wrapper to extract keyed container from JSON data.
private struct NestedJSONContainer<Key: CodingKey>: Decodable {
    let container: JSONKeyedDecodingContainer<Key>

    init(from decoder: Decoder) throws {
        let keyedContainer = try decoder.container(keyedBy: Key.self)
        self.container = JSONKeyedDecodingContainer(wrapped: keyedContainer)
    }
}

/// A keyed decoding container backed by a JSON decoder's container.
private struct JSONKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    private let wrapped: KeyedDecodingContainer<Key>

    init(wrapped: KeyedDecodingContainer<Key>) {
        self.wrapped = wrapped
    }

    var codingPath: [CodingKey] { wrapped.codingPath }
    var allKeys: [Key] { wrapped.allKeys }

    func contains(_ key: Key) -> Bool { wrapped.contains(key) }
    func decodeNil(forKey key: Key) throws -> Bool { try wrapped.decodeNil(forKey: key) }
    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool { try wrapped.decode(type, forKey: key) }
    func decode(_ type: String.Type, forKey key: Key) throws -> String { try wrapped.decode(type, forKey: key) }
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double { try wrapped.decode(type, forKey: key) }
    func decode(_ type: Float.Type, forKey key: Key) throws -> Float { try wrapped.decode(type, forKey: key) }
    func decode(_ type: Int.Type, forKey key: Key) throws -> Int { try wrapped.decode(type, forKey: key) }
    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { try wrapped.decode(type, forKey: key) }
    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 { try wrapped.decode(type, forKey: key) }
    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 { try wrapped.decode(type, forKey: key) }
    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 { try wrapped.decode(type, forKey: key) }
    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { try wrapped.decode(type, forKey: key) }
    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 { try wrapped.decode(type, forKey: key) }
    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { try wrapped.decode(type, forKey: key) }
    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { try wrapped.decode(type, forKey: key) }
    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { try wrapped.decode(type, forKey: key) }
    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T { try wrapped.decode(type, forKey: key) }

    func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
        try wrapped.nestedContainer(keyedBy: type, forKey: key)
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        try wrapped.nestedUnkeyedContainer(forKey: key)
    }

    func superDecoder() throws -> Decoder { try wrapped.superDecoder() }
    func superDecoder(forKey key: Key) throws -> Decoder { try wrapped.superDecoder(forKey: key) }
}

// MARK: - Nested Row Decoder for Flatten Strategy

/// A decoder for nested types that reads from a filtered/prefixed source.
struct CSVNestedRowDecoder: Decoder {
    let source: CSVRowDecoder.RowSource
    let configuration: CSVDecoder.Configuration
    let codingPath: [CodingKey]
    let rowIndex: Int?
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        KeyedDecodingContainer(CSVKeyedDecodingContainer(
            source: source,
            configuration: configuration,
            codingPath: codingPath,
            rowIndex: rowIndex
        ))
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        throw CSVDecodingError.unsupportedType("Unkeyed containers are not supported in CSV decoding")
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        throw CSVDecodingError.unsupportedType("Single value containers are not supported for nested types")
    }
}
