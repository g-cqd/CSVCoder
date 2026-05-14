//
//  CSVIndexedMacro.swift
//  CSVCoder
//
//  Macro implementation for @CSVIndexed that generates CSVIndexedDecodable conformance.
//

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// MARK: - Diagnostics

/// Diagnostic message emitted when two `@CSVColumn` attributes claim the
/// same external column name on the same `@CSVIndexed` struct.
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
/// whose parent struct lacks `@CSVIndexed` — the column rename will silently
/// have no effect, which is almost always a bug.
private struct OrphanCSVColumnDiagnostic: DiagnosticMessage {
    var message: String {
        "@CSVColumn has no effect without @CSVIndexed on the containing struct"
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

// MARK: - CSVIndexedMacroError

/// Error types for macro diagnostics.
public enum CSVIndexedMacroError: Error, CustomStringConvertible {
    case notAStruct
    case noStoredProperties
    case existingCodingKeysNotCaseIterable

    // MARK: Public

    public var description: String {
        switch self {
        case .notAStruct:
            "@CSVIndexed can only be applied to structs"

        case .noStoredProperties:
            "@CSVIndexed requires at least one stored property"

        case .existingCodingKeysNotCaseIterable:
            "Existing CodingKeys must conform to CaseIterable for @CSVIndexed"
        }
    }
}

// MARK: - CSVIndexedMacro

/// The @CSVIndexed macro generates CSVIndexedDecodable conformance.
///
/// It creates:
/// - CodingKeys enum with CaseIterable conformance (if not already present)
/// - typealias CSVCodingKeys = CodingKeys
/// - CSVIndexedDecodable and CSVIndexedEncodable conformance via extensions
public struct CSVIndexedMacro: MemberMacro, ExtensionMacro {
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
            throw CSVIndexedMacroError.notAStruct
        }

        // Determine access level from struct modifiers
        let accessLevel = extractAccessLevel(from: structDecl.modifiers)

        // Extract stored properties
        let storedProperties = extractStoredProperties(from: structDecl)
        guard !storedProperties.isEmpty else {
            throw CSVIndexedMacroError.noStoredProperties
        }

        // Audit D5: emit a diagnostic for duplicate @CSVColumn names.  Two
        // properties resolving to the same external column produce a
        // `case foo = "x"` / `case bar = "x"` enum, which the Swift compiler
        // rejects with a much less actionable error.
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
        _ properties: [(name: String, customName: String?, attribute: AttributeSyntax?)],
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
        attachedTo _: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo _: [TypeSyntax],
        in _: some MacroExpansionContext,
    ) throws -> [ExtensionDeclSyntax] {
        // Generate extensions for protocol conformance
        let decodableExt = try ExtensionDeclSyntax("extension \(type): CSVIndexedDecodable {}")
        let encodableExt = try ExtensionDeclSyntax("extension \(type): CSVIndexedEncodable {}")

        return [decodableExt, encodableExt]
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

    /// Extracts stored property names from a struct declaration.
    /// The `attribute` field carries the `@CSVColumn` syntax node when a custom
    /// name was provided, so diagnostics can point at the offending source.
    private static func extractStoredProperties(from structDecl: StructDeclSyntax) -> [(
        name: String,
        customName: String?,
        attribute: AttributeSyntax?,
    )] {
        var properties: [(name: String, customName: String?, attribute: AttributeSyntax?)] = []

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

                properties.append((name: propertyName, customName: customName, attribute: attribute))
            }
        }

        return properties
    }

    /// Extracts the custom column name and the originating attribute syntax
    /// from `@CSVColumn("…")`, if present.
    private static func extractCSVColumnInfo(
        from attributes: AttributeListSyntax
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
        properties: [(name: String, customName: String?, attribute: AttributeSyntax?)],
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

// MARK: - CSVColumnMacro

/// The @CSVColumn macro marks a property with a custom CSV column name.
/// This is a peer macro that doesn't generate any code itself;
/// it's read by @CSVIndexed to customize CodingKeys.
///
/// Audit D5: when applied to a property whose parent struct is not annotated
/// with `@CSVIndexed`, the rename is silently dropped.  Emit a warning so the
/// mistake surfaces during macro expansion rather than at runtime.
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
                let hasCSVIndexed = structDecl.attributes.contains { element in
                    guard case .attribute(let attr) = element,
                        let identifier = attr.attributeName.as(IdentifierTypeSyntax.self)
                    else { return false }
                    return identifier.name.text == "CSVIndexed"
                }
                if !hasCSVIndexed {
                    context.diagnose(
                        Diagnostic(node: Syntax(attribute), message: OrphanCSVColumnDiagnostic())
                    )
                }
                break
            }
            parent = node.parent
        }

        // This macro doesn't generate any code; it's a marker that @CSVIndexed reads.
        return []
    }
}
