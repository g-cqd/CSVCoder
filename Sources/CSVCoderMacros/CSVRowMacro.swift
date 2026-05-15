//
//  CSVRowMacro.swift
//  CSVCoder
//
//  Macro implementation for @CSVRow that generates CSVRowDecodable / CSVRowEncodable
//  conformance.
//

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// MARK: - Diagnostics

/// Diagnostic message emitted when two `@CSVColumn` attributes claim the
/// same external column name on the same `@CSVRow` struct.
private struct DuplicateColumnDiagnostic: DiagnosticMessage {
    let columnName: String
    let firstProperty: String
    let secondProperty: String

    var message: String {
        "Duplicate CSV column name '\(columnName)' on '\(firstProperty)' and '\(secondProperty)'"
    }

    var diagnosticID: MessageID {
        MessageID(domain: "CSVCoderMacros", id: "duplicateColumnName")
    }

    var severity: DiagnosticSeverity { .error }
}

/// Diagnostic message emitted when `@CSVColumn` is applied to a property
/// whose parent struct lacks `@CSVRow` (or the deprecated `@CSVIndexed`).
/// Without the row-level macro to read it, the column rename silently has
/// no effect — surface that as a warning at expansion time.
private struct OrphanCSVColumnDiagnostic: DiagnosticMessage {
    var message: String {
        "@CSVColumn has no effect without @CSVRow on the containing struct"
    }

    var diagnosticID: MessageID {
        MessageID(domain: "CSVCoderMacros", id: "orphanCSVColumn")
    }

    var severity: DiagnosticSeverity { .warning }
}

/// Swift reserved keywords that need backtick-escaping when used as property
/// names.  This is the subset that legally appears in a value declaration
/// (so `Self` / `Any` etc. are intentionally excluded).
private let swiftReservedWords: Set<String> = [
    "associatedtype", "class", "deinit", "enum", "extension", "fileprivate",
    "func", "import", "init", "inout", "internal", "let", "open", "operator",
    "private", "precedencegroup", "protocol", "public", "rethrows", "static",
    "struct", "subscript", "typealias", "var",
    "break", "case", "catch", "continue", "default", "defer", "do", "else",
    "fallthrough", "for", "guard", "if", "in", "repeat", "return", "throw",
    "switch", "where", "while",
    "as", "false", "is", "nil", "self", "super", "throws", "true", "try",
]

/// Backtick-escapes a property name if it is a Swift reserved keyword.
private func escapeIdentifier(_ name: String) -> String {
    swiftReservedWords.contains(name) ? "`\(name)`" : name
}

// MARK: - CSVRowMacroError

/// Error types for macro diagnostics.
public enum CSVRowMacroError: Error, CustomStringConvertible {
    case notAStruct
    case noStoredProperties
    case existingCodingKeysNotCaseIterable

    // MARK: Public

    public var description: String {
        switch self {
        case .notAStruct:
            "@CSVRow can only be applied to structs"

        case .noStoredProperties:
            "@CSVRow requires at least one stored property"

        case .existingCodingKeysNotCaseIterable:
            "Existing CodingKeys must conform to CaseIterable for @CSVRow"
        }
    }
}

/// Deprecated alias retained for one release cycle so external code that
/// caught `CSVIndexedMacroError` still compiles.
@available(*, deprecated, renamed: "CSVRowMacroError")
public typealias CSVIndexedMacroError = CSVRowMacroError

// MARK: - Property metadata

/// Per-property metadata collected from the struct's stored declarations
/// and passed between the macro's internal helpers. File-scope so every
/// helper signature stays under the `lineLength` cap.
private typealias Property = (
    name: String,
    customName: String?,
    attribute: AttributeSyntax?,
    typeName: String?,
    isOptional: Bool
)

// MARK: - CSVRowMacro

/// The `@CSVRow` macro generates ``CSVRowDecodable`` and ``CSVRowEncodable``
/// conformance.
///
/// It creates:
/// - `CodingKeys` enum with `CaseIterable` conformance (if not already present)
/// - `typealias CSVCodingKeys = CodingKeys`
/// - Extensions conforming to `CSVRowDecodable` and `CSVRowEncodable`
///
/// The legacy `@CSVIndexed` macro routes to the same implementation; the two
/// expand identically.
public struct CSVRowMacro: MemberMacro, ExtensionMacro {
    // MARK: Public

    // MARK: - MemberMacro

    public static func expansion(
        of _: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in context: some MacroExpansionContext,
    ) throws -> [DeclSyntax] {
        // Ensure we're attached to a struct
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw CSVRowMacroError.notAStruct
        }

        // Determine access level from struct modifiers
        let accessLevel = extractAccessLevel(from: structDecl.modifiers)

        // Extract stored properties
        let storedProperties = extractStoredProperties(from: structDecl)
        guard !storedProperties.isEmpty else {
            throw CSVRowMacroError.noStoredProperties
        }

        // Emit a diagnostic for duplicate @CSVColumn names. Two properties
        // resolving to the same external column produce a `case foo = "x"`
        // / `case bar = "x"` enum, which the Swift compiler rejects with a
        // less actionable error.
        diagnoseDuplicateColumns(storedProperties, in: context)

        // Check if CodingKeys already exists
        let existingCodingKeys = findExistingCodingKeys(in: structDecl)

        var members: [DeclSyntax] = []

        if existingCodingKeys == nil {
            // Generate CodingKeys enum with appropriate access level
            let codingKeysDecl = generateCodingKeys(properties: storedProperties, accessLevel: accessLevel)
            members.append(codingKeysDecl)
        }

        // Generate typealias CSVCodingKeys = CodingKeys with appropriate access level
        let typealiasDecl = generateTypealias(accessLevel: accessLevel)
        members.append(typealiasDecl)

        return members
    }

    /// Scans `properties` for duplicate external column names and reports
    /// each collision via the macro expansion context.
    private static func diagnoseDuplicateColumns(
        _ properties: [Property],
        in context: some MacroExpansionContext,
    ) {
        var seen: [String: String] = [:]
        for property in properties {
            // Only `@CSVColumn` renames participate in duplicate detection;
            // bare properties always use their own name.
            guard let columnName = property.customName, let attribute = property.attribute else { continue }
            if let firstProperty = seen[columnName] {
                let diag = Diagnostic(
                    node: Syntax(attribute),
                    message: DuplicateColumnDiagnostic(
                        columnName: columnName,
                        firstProperty: firstProperty,
                        secondProperty: property.name,
                    ),
                )
                context.diagnose(diag)
            } else {
                seen[columnName] = property.name
            }
        }
    }

    // MARK: - ExtensionMacro

    public static func expansion(
        of _: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo _: [TypeSyntax],
        in _: some MacroExpansionContext,
    ) throws -> [ExtensionDeclSyntax] {
        var extensions: [ExtensionDeclSyntax] = []

        // Always-emitted conformances. These carry the column-order metadata
        // and bind the type to the standard `Codable` path.
        extensions.append(try ExtensionDeclSyntax("extension \(type): CSVRowDecodable {}"))
        extensions.append(try ExtensionDeclSyntax("extension \(type): CSVRowEncodable {}"))

        // Direct-decode conformance only fires when every stored property has
        // a type the field decoder knows how to handle. Otherwise the type
        // falls back to the standard Codable path with no behavioural change.
        if let structDecl = declaration.as(StructDeclSyntax.self) {
            let storedProperties = extractStoredProperties(from: structDecl)
            if shouldEmitDirectDecodable(for: storedProperties) {
                let initBody = generateDirectInitBody(properties: storedProperties)
                let directExt = try ExtensionDeclSyntax(
                    """
                    extension \(type): CSVDirectDecodable {
                        public init(
                            csvRow: CSVRowView,
                            columnIndices: [Int],
                            configuration: CSVDecoder.Configuration,
                            rowIndex: Int?
                        ) throws {
                    \(raw: initBody)
                        }
                    }
                    """,
                )
                extensions.append(directExt)
            }
        }

        return extensions
    }

    // MARK: - Direct-decode synthesis

    /// Types supported by ``CSVDirectFieldDecoder``. The macro consults this
    /// set to decide whether to emit ``CSVDirectDecodable`` conformance.
    private static let directlyDecodableTypes: Set<String> = [
        "String", "Bool", "Double", "Float",
        "Int", "Int8", "Int16", "Int32", "Int64",
        "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
        "Decimal", "UUID", "URL", "Date",
        // Foundation-qualified spellings that may appear in user source.
        "Foundation.Decimal", "Foundation.UUID", "Foundation.URL", "Foundation.Date",
        "Swift.String", "Swift.Bool", "Swift.Double", "Swift.Float",
        "Swift.Int", "Swift.Int8", "Swift.Int16", "Swift.Int32", "Swift.Int64",
        "Swift.UInt", "Swift.UInt8", "Swift.UInt16", "Swift.UInt32", "Swift.UInt64",
    ]

    /// Returns `true` when every property has a supported direct-decode type.
    private static func shouldEmitDirectDecodable(
        for properties: [Property],
    ) -> Bool {
        guard !properties.isEmpty else { return false }
        for property in properties {
            guard let typeName = property.typeName else { return false }
            // No Foundation in the macros target, so trim ASCII whitespace via stdlib.
            let normalized = String(
                typeName.drop(while: \.isWhitespace)
                    .reversed()
                    .drop(while: \.isWhitespace)
                    .reversed(),
            )
            if !directlyDecodableTypes.contains(normalized) {
                return false
            }
        }
        return true
    }

    /// Generates the body of the direct-decode init by emitting one
    /// `CSVDirectFieldDecoder.*` call per stored property. Each call captures
    /// the per-property column index from `columnIndices`, plus the property
    /// name for error locations.
    private static func generateDirectInitBody(
        properties: [Property],
    ) -> String {
        var lines: [String] = []
        for (offset, property) in properties.enumerated() {
            guard let typeName = property.typeName else { continue }
            // No Foundation in the macros target, so trim ASCII whitespace via stdlib.
            let normalized = String(
                typeName.drop(while: \.isWhitespace)
                    .reversed()
                    .drop(while: \.isWhitespace)
                    .reversed(),
            )
            let escapedName = escapeIdentifier(property.name)
            let helperCall = directDecodeCall(
                forType: normalized,
                isOptional: property.isOptional,
                propertyName: property.name,
                columnOffset: offset,
            )
            lines.append("        self.\(escapedName) = \(helperCall)")
        }
        return lines.joined(separator: "\n")
    }

    /// Returns the `CSVDirectFieldDecoder.*` invocation that decodes the
    /// given property type at the supplied column offset. `propertyName` is
    /// used both for the `key` parameter (error locations) and for the
    /// stored-property assignment on the caller side.
    private static func directDecodeCall(
        forType type: String,
        isOptional: Bool,
        propertyName: String,
        columnOffset: Int,
    ) -> String {
        // Strip Swift./Foundation. qualifiers so we match the helper name.
        // (`String.replacingOccurrences` lives in Foundation, which the macros
        // target doesn't import — do it with stdlib `dropFirst` instead.)
        var bare = type
        if bare.hasPrefix("Foundation.") {
            bare = String(bare.dropFirst("Foundation.".count))
        } else if bare.hasPrefix("Swift.") {
            bare = String(bare.dropFirst("Swift.".count))
        }

        let index = "columnIndices[\(columnOffset)]"
        let common =
            "from: csvRow, index: \(index), configuration: configuration, "
            + "key: \"\(propertyName)\", rowIndex: rowIndex"
        let commonNoKey = "from: csvRow, index: \(index), configuration: configuration"

        let optionalCall = isOptional ? "optional" : ""
        switch (bare, isOptional) {
        case ("String", true):
            // optionalString does not throw — no `try`.
            return "CSVDirectFieldDecoder.optionalString(\(commonNoKey))"
        case ("String", false):
            return "try CSVDirectFieldDecoder.string(\(common))"
        case ("Bool", _):
            return "try CSVDirectFieldDecoder.\(optionalCall)\(isOptional ? "Bool" : "bool")(\(common))"
        case ("Double", _):
            return "try CSVDirectFieldDecoder.\(optionalCall)\(isOptional ? "Double" : "double")(\(common))"
        case ("Float", _):
            // No optionalFloat helper — route through optionalDouble for `Float?` and narrow.
            if isOptional {
                return "(try CSVDirectFieldDecoder.optionalDouble(\(common))).map(Float.init)"
            }
            return "try CSVDirectFieldDecoder.float(\(common))"
        case ("Decimal", _):
            return "try CSVDirectFieldDecoder.\(optionalCall)\(isOptional ? "Decimal" : "decimal")(\(common))"
        case ("UUID", _):
            return "try CSVDirectFieldDecoder.\(optionalCall)\(isOptional ? "UUID" : "uuid")(\(common))"
        case ("URL", _):
            return "try CSVDirectFieldDecoder.\(optionalCall)\(isOptional ? "URL" : "url")(\(common))"
        case ("Date", _):
            return "try CSVDirectFieldDecoder.\(optionalCall)\(isOptional ? "Date" : "date")(\(common))"
        case ("UInt64", false):
            // UInt64 may exceed Int64 range — route through the dedicated helper.
            return "try CSVDirectFieldDecoder.uInt64(\(common))"
        case ("UInt64", true):
            // No optionalUInt64 helper — fall back to optionalInteger which handles Int64-range values.
            // Values exceeding Int64.max in an Optional context are an unsupported edge case.
            return "try CSVDirectFieldDecoder.optionalInteger(UInt64.self, \(common))"
        default:
            // All other fixed-width integers route through the generic helper.
            if isOptional {
                return "try CSVDirectFieldDecoder.optionalInteger(\(bare).self, \(common))"
            }
            return "try CSVDirectFieldDecoder.integer(\(bare).self, \(common))"
        }
    }

    // MARK: Private

    // MARK: - Access Level Handling

    /// Access levels that can be applied to generated members.
    private enum AccessLevel: String {
        case `public` = "public "
        case open = "open "
        case `internal` = ""
        case `fileprivate` = "fileprivate "
        case `private` = "private "
    }

    /// Extracts the access level from declaration modifiers.
    private static func extractAccessLevel(from modifiers: DeclModifierListSyntax) -> AccessLevel {
        for modifier in modifiers {
            switch modifier.name.tokenKind {
            case .keyword(.public):
                return .public

            case .keyword(.open):
                return .open

            case .keyword(.fileprivate):
                return .fileprivate

            case .keyword(.private):
                return .private

            case .keyword(.internal):
                return .internal

            default:
                continue
            }
        }
        return .internal
    }

    /// Generates the typealias declaration with appropriate access level.
    private static func generateTypealias(accessLevel: AccessLevel) -> DeclSyntax {
        "\(raw: accessLevel.rawValue)typealias CSVCodingKeys = CodingKeys"
    }

    // MARK: - Helpers

    /// Extracts stored property metadata from a struct declaration.
    /// Each entry captures the property name, an optional `@CSVColumn` rename
    /// (with the attribute syntax for diagnostics), the declared Swift type
    /// (as a string, e.g. `"Int"`, `"String?"`, `"[Double]"`), and whether
    /// that type is `Optional`. Type-less bindings (no annotation, no
    /// initializer expression we can use) report `typeName == nil`, which
    /// suppresses the direct-decode synthesis for the whole type.
    private static func extractStoredProperties(from structDecl: StructDeclSyntax) -> [(
        name: String,
        customName: String?,
        attribute: AttributeSyntax?,
        typeName: String?,
        isOptional: Bool,
    )] {
        typealias Property = (
            name: String,
            customName: String?,
            attribute: AttributeSyntax?,
            typeName: String?,
            isOptional: Bool
        )
        var properties: [Property] = []

        for member in structDecl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }

            // Skip computed properties (those with accessors that aren't just stored)
            let isComputed = varDecl.bindings.contains { binding in
                if let accessor = binding.accessorBlock {
                    // If it has a getter but no setter, it's computed
                    switch accessor.accessors {
                    case .getter:
                        return true

                    case .accessors(let list):
                        return list.contains { $0.accessorSpecifier.tokenKind == .keyword(.get) }
                    }
                }
                return false
            }

            guard !isComputed else { continue }

            // Extract property names
            for binding in varDecl.bindings {
                guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
                let propertyName = identifier.identifier.text

                // Check for @CSVColumn attribute
                let (customName, attribute) = extractCSVColumnInfo(from: varDecl.attributes)

                let (typeName, isOptional) = extractType(from: binding)

                properties.append(
                    (
                        name: propertyName,
                        customName: customName,
                        attribute: attribute,
                        typeName: typeName,
                        isOptional: isOptional,
                    ),
                )
            }
        }

        return properties
    }

    /// Extracts the Swift type spelling from a binding's `: T` annotation,
    /// trimming whitespace and detecting `Optional` shorthand (`T?`) and
    /// long-form (`Optional<T>`). Returns `(nil, false)` when no type
    /// annotation is present — in that case the macro cannot synthesise a
    /// direct-decode init for this property.
    private static func extractType(from binding: PatternBindingSyntax) -> (typeName: String?, isOptional: Bool) {
        guard let typeAnnotation = binding.typeAnnotation else { return (nil, false) }
        var typeText = typeAnnotation.type.trimmedDescription
        // Strip a trailing `!` (implicitly unwrapped) and treat it as optional.
        if typeText.hasSuffix("!") {
            typeText = String(typeText.dropLast())
            return (typeText, true)
        }
        if typeText.hasSuffix("?") {
            let inner = String(typeText.dropLast())
            return (inner, true)
        }
        // Detect `Optional<T>` long-form.
        if typeText.hasPrefix("Optional<"), typeText.hasSuffix(">") {
            let start = typeText.index(typeText.startIndex, offsetBy: "Optional<".count)
            let end = typeText.index(before: typeText.endIndex)
            return (String(typeText[start ..< end]), true)
        }
        return (typeText, false)
    }

    /// Extracts the custom column name and the originating attribute syntax
    /// from `@CSVColumn("…")`, if present.
    private static func extractCSVColumnInfo(
        from attributes: AttributeListSyntax,
    ) -> (name: String?, attribute: AttributeSyntax?) {
        for attribute in attributes {
            guard case .attribute(let attr) = attribute else { continue }
            guard let identifier = attr.attributeName.as(IdentifierTypeSyntax.self),
                identifier.name.text == "CSVColumn"
            else { continue }

            // Extract the argument
            if let arguments = attr.arguments,
                case .argumentList(let argList) = arguments,
                let firstArg = argList.first,
                let stringLiteral = firstArg.expression.as(StringLiteralExprSyntax.self),
                let segment = stringLiteral.segments.first,
                case .stringSegment(let stringSegment) = segment
            {
                return (stringSegment.content.text, attr)
            }
        }
        return (nil, nil)
    }

    /// Finds existing CodingKeys enum in the struct.
    private static func findExistingCodingKeys(in structDecl: StructDeclSyntax) -> EnumDeclSyntax? {
        for member in structDecl.memberBlock.members {
            if let enumDecl = member.decl.as(EnumDeclSyntax.self),
                enumDecl.name.text == "CodingKeys"
            {
                return enumDecl
            }
        }
        return nil
    }

    /// Generates the `CodingKeys` enum with `CaseIterable` conformance.
    /// Property names that collide with Swift reserved keywords are
    /// backtick-escaped so `init` / `class` / `default` etc. compile cleanly.
    private static func generateCodingKeys(
        properties: [Property],
        accessLevel: AccessLevel,
    ) -> DeclSyntax {
        var lines: [String] = []
        for prop in properties {
            let escapedName = escapeIdentifier(prop.name)
            if let customName = prop.customName {
                lines.append("case \(escapedName) = \"\(customName)\"")
            } else {
                lines.append("case \(escapedName)")
            }
        }
        let body = lines.joined(separator: "\n    ")

        return """
            \(raw: accessLevel.rawValue)enum CodingKeys: String, CodingKey, CaseIterable {
                \(raw: body)
            }
            """
    }
}

/// Deprecated alias retained for source compatibility with consumers that
/// referenced `CSVIndexedMacro` directly.  Routes to ``CSVRowMacro``.
@available(*, deprecated, renamed: "CSVRowMacro")
public typealias CSVIndexedMacro = CSVRowMacro

// MARK: - CSVColumnMacro

/// The `@CSVColumn` macro marks a property with a custom CSV column name.
/// This is a peer macro that doesn't generate any code itself; it's read by
/// ``CSVRowMacro`` to customize `CodingKeys`.
///
/// When applied to a property whose parent struct is not annotated with
/// `@CSVRow` (or the deprecated `@CSVIndexed`), the rename is silently
/// dropped. Emit a warning so the mistake surfaces during macro expansion
/// rather than at runtime.
public struct CSVColumnMacro: PeerMacro {
    public static func expansion(
        of attribute: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext,
    ) throws -> [DeclSyntax] {
        // Walk up the syntax tree looking for the containing struct.
        var parent: Syntax? = declaration.parent
        while let node = parent {
            if let structDecl = node.as(StructDeclSyntax.self) {
                let hasRowMacro = structDecl.attributes.contains { element in
                    guard case .attribute(let attr) = element,
                        let identifier = attr.attributeName.as(IdentifierTypeSyntax.self)
                    else { return false }
                    let name = identifier.name.text
                    // Accept both the new `@CSVRow` and the legacy `@CSVIndexed`.
                    return name == "CSVRow" || name == "CSVIndexed"
                }
                if !hasRowMacro {
                    context.diagnose(
                        Diagnostic(node: Syntax(attribute), message: OrphanCSVColumnDiagnostic()),
                    )
                }
                break
            }
            parent = node.parent
        }

        // This macro doesn't generate any code; it's a marker that @CSVRow reads.
        return []
    }
}
