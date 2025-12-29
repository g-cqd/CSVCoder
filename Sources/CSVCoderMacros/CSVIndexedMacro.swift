//
//  CSVIndexedMacro.swift
//  CSVCoder
//
//  Macro implementation for @CSVIndexed that generates CSVIndexedDecodable conformance.
//

import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

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
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
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

    // MARK: - ExtensionMacro

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext,
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
    private static func extractStoredProperties(from structDecl: StructDeclSyntax) -> [(
        name: String,
        customName: String?,
    )] {
        var properties: [(name: String, customName: String?)] = []

        for member in structDecl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }

            // Skip computed properties (those with accessors that aren't just stored)
            let isComputed = varDecl.bindings.contains { binding in
                if let accessor = binding.accessorBlock {
                    // If it has a getter but no setter, it's computed
                    switch accessor.accessors {
                    case .getter:
                        return true

                    case let .accessors(list):
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
                let customName = extractCSVColumnName(from: varDecl.attributes)

                properties.append((name: propertyName, customName: customName))
            }
        }

        return properties
    }

    /// Extracts custom column name from @CSVColumn attribute if present.
    private static func extractCSVColumnName(from attributes: AttributeListSyntax) -> String? {
        for attribute in attributes {
            guard case let .attribute(attr) = attribute else { continue }
            guard let identifier = attr.attributeName.as(IdentifierTypeSyntax.self),
                  identifier.name.text == "CSVColumn" else { continue }

            // Extract the argument
            if let arguments = attr.arguments,
               case let .argumentList(argList) = arguments,
               let firstArg = argList.first,
               let stringLiteral = firstArg.expression.as(StringLiteralExprSyntax.self),
               let segment = stringLiteral.segments.first,
               case let .stringSegment(stringSegment) = segment {
                return stringSegment.content.text
            }
        }
        return nil
    }

    /// Finds existing CodingKeys enum in the struct.
    private static func findExistingCodingKeys(in structDecl: StructDeclSyntax) -> EnumDeclSyntax? {
        for member in structDecl.memberBlock.members {
            if let enumDecl = member.decl.as(EnumDeclSyntax.self),
               enumDecl.name.text == "CodingKeys" {
                return enumDecl
            }
        }
        return nil
    }

    /// Generates CodingKeys enum with CaseIterable conformance.
    private static func generateCodingKeys(properties: [(name: String, customName: String?)],
                                           accessLevel: AccessLevel) -> DeclSyntax {
        var casesCode = ""
        for (index, prop) in properties.enumerated() {
            if index > 0 { casesCode += "\n" }
            if let customName = prop.customName {
                casesCode += "        case \(prop.name) = \"\(customName)\""
            } else {
                casesCode += "        case \(prop.name)"
            }
        }

        return """
        \(raw: accessLevel.rawValue)enum CodingKeys: String, CodingKey, CaseIterable {
        \(raw: casesCode)
        }
        """
    }
}

// MARK: - CSVColumnMacro

/// The @CSVColumn macro marks a property with a custom CSV column name.
/// This is a peer macro that doesn't generate any code itself;
/// it's read by @CSVIndexed to customize CodingKeys.
public struct CSVColumnMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext,
    ) throws -> [DeclSyntax] {
        // This macro doesn't generate any code
        // It's just a marker that @CSVIndexed reads
        []
    }
}
