//
//  CSVIndexedMacroTests.swift
//  CSVCoder
//
//  Tests for @CSVIndexed and @CSVColumn macros.
//

import Testing
import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport

#if canImport(CSVCoderMacros)
@testable import CSVCoderMacros

@Suite("CSVIndexed Macro Tests")
struct CSVIndexedMacroTests {

    let testMacros: [String: Macro.Type] = [
        "CSVIndexed": CSVIndexedMacro.self,
        "CSVColumn": CSVColumnMacro.self
    ]

    // MARK: - Basic Expansion Tests

    @Test("Basic macro expansion generates CodingKeys and typealias")
    func basicMacroExpansion() {
        assertMacroExpansion(
            """
            @CSVIndexed
            struct Person: Codable {
                let name: String
                let age: Int
            }
            """,
            expandedSource: """
            struct Person: Codable {
                let name: String
                let age: Int

                enum CodingKeys: String, CodingKey, CaseIterable {
                    case name
                    case age
                }

                typealias CSVCodingKeys = CodingKeys
            }

            extension Person: CSVIndexedDecodable {
            }

            extension Person: CSVIndexedEncodable {
            }
            """,
            macros: testMacros
        )
    }

    @Test("Macro handles optional properties")
    func macroWithOptionalProperty() {
        assertMacroExpansion(
            """
            @CSVIndexed
            struct User: Codable {
                let id: Int
                let name: String
                let email: String?
            }
            """,
            expandedSource: """
            struct User: Codable {
                let id: Int
                let name: String
                let email: String?

                enum CodingKeys: String, CodingKey, CaseIterable {
                    case id
                    case name
                    case email
                }

                typealias CSVCodingKeys = CodingKeys
            }

            extension User: CSVIndexedDecodable {
            }

            extension User: CSVIndexedEncodable {
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - @CSVColumn Tests

    @Test("Macro with @CSVColumn generates custom raw values")
    func macroWithCSVColumn() {
        assertMacroExpansion(
            """
            @CSVIndexed
            struct Product: Codable {
                let id: Int

                @CSVColumn("product_name")
                let name: String

                @CSVColumn("unit_price")
                let price: Double
            }
            """,
            expandedSource: """
            struct Product: Codable {
                let id: Int

                let name: String

                let price: Double

                enum CodingKeys: String, CodingKey, CaseIterable {
                    case id
                    case name = "product_name"
                    case price = "unit_price"
                }

                typealias CSVCodingKeys = CodingKeys
            }

            extension Product: CSVIndexedDecodable {
            }

            extension Product: CSVIndexedEncodable {
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - Property Order Tests

    @Test("Macro preserves property declaration order")
    func macroPreservesPropertyOrder() {
        assertMacroExpansion(
            """
            @CSVIndexed
            struct Record: Codable {
                let third: Double
                let first: String
                let second: Int
            }
            """,
            expandedSource: """
            struct Record: Codable {
                let third: Double
                let first: String
                let second: Int

                enum CodingKeys: String, CodingKey, CaseIterable {
                    case third
                    case first
                    case second
                }

                typealias CSVCodingKeys = CodingKeys
            }

            extension Record: CSVIndexedDecodable {
            }

            extension Record: CSVIndexedEncodable {
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - Error Cases

    @Test("Macro fails on class")
    func macroFailsOnClass() {
        assertMacroExpansion(
            """
            @CSVIndexed
            class NotAStruct: Codable {
                let value: Int
            }
            """,
            expandedSource: """
            class NotAStruct: Codable {
                let value: Int
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "@CSVIndexed can only be applied to structs", line: 1, column: 1)
            ],
            macros: testMacros
        )
    }

    // MARK: - Computed Property Tests

    @Test("Macro skips computed properties")
    func macroSkipsComputedProperties() {
        assertMacroExpansion(
            """
            @CSVIndexed
            struct WithComputed: Codable {
                let stored: Int

                var computed: String {
                    "value"
                }
            }
            """,
            expandedSource: """
            struct WithComputed: Codable {
                let stored: Int

                var computed: String {
                    "value"
                }

                enum CodingKeys: String, CodingKey, CaseIterable {
                    case stored
                }

                typealias CSVCodingKeys = CodingKeys
            }

            extension WithComputed: CSVIndexedDecodable {
            }

            extension WithComputed: CSVIndexedEncodable {
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - @CSVColumn Alone Tests

    @Test("@CSVColumn alone generates nothing")
    func csvColumnMacroGeneratesNothing() {
        assertMacroExpansion(
            """
            struct Standalone {
                @CSVColumn("custom_name")
                let field: String
            }
            """,
            expandedSource: """
            struct Standalone {
                let field: String
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - Multiple Properties Tests

    @Test("Macro handles many properties")
    func macroHandlesManyProperties() {
        assertMacroExpansion(
            """
            @CSVIndexed
            struct LargeRecord: Codable {
                let a: String
                let b: Int
                let c: Double
                let d: Bool
                let e: Date
            }
            """,
            expandedSource: """
            struct LargeRecord: Codable {
                let a: String
                let b: Int
                let c: Double
                let d: Bool
                let e: Date

                enum CodingKeys: String, CodingKey, CaseIterable {
                    case a
                    case b
                    case c
                    case d
                    case e
                }

                typealias CSVCodingKeys = CodingKeys
            }

            extension LargeRecord: CSVIndexedDecodable {
            }

            extension LargeRecord: CSVIndexedEncodable {
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - Access Level Tests

    @Test("Macro generates public CodingKeys and typealias for public struct")
    func macroHandlesPublicStruct() {
        assertMacroExpansion(
            """
            @CSVIndexed
            public struct PublicRecord: Codable {
                public let name: String
                public let value: Int
            }
            """,
            expandedSource: """
            public struct PublicRecord: Codable {
                public let name: String
                public let value: Int

                public enum CodingKeys: String, CodingKey, CaseIterable {
                    case name
                    case value
                }

                public typealias CSVCodingKeys = CodingKeys
            }

            extension PublicRecord: CSVIndexedDecodable {
            }

            extension PublicRecord: CSVIndexedEncodable {
            }
            """,
            macros: testMacros
        )
    }

    @Test("Macro generates public members with @CSVColumn for public struct")
    func macroHandlesPublicStructWithCSVColumn() {
        assertMacroExpansion(
            """
            @CSVIndexed
            public struct PublicProduct: Codable, Sendable {
                @CSVColumn("Product Name")
                public let name: String

                @CSVColumn("Unit Price")
                public let price: Double
            }
            """,
            expandedSource: """
            public struct PublicProduct: Codable, Sendable {
                public let name: String

                public let price: Double

                public enum CodingKeys: String, CodingKey, CaseIterable {
                    case name = "Product Name"
                    case price = "Unit Price"
                }

                public typealias CSVCodingKeys = CodingKeys
            }

            extension PublicProduct: CSVIndexedDecodable {
            }

            extension PublicProduct: CSVIndexedEncodable {
            }
            """,
            macros: testMacros
        )
    }

    @Test("Macro generates internal CodingKeys for internal struct")
    func macroHandlesInternalStruct() {
        assertMacroExpansion(
            """
            @CSVIndexed
            internal struct InternalRecord: Codable {
                let name: String
            }
            """,
            expandedSource: """
            internal struct InternalRecord: Codable {
                let name: String

                enum CodingKeys: String, CodingKey, CaseIterable {
                    case name
                }

                typealias CSVCodingKeys = CodingKeys
            }

            extension InternalRecord: CSVIndexedDecodable {
            }

            extension InternalRecord: CSVIndexedEncodable {
            }
            """,
            macros: testMacros
        )
    }

    @Test("Macro generates fileprivate CodingKeys for fileprivate struct")
    func macroHandlesFileprivateStruct() {
        assertMacroExpansion(
            """
            @CSVIndexed
            fileprivate struct FileprivateRecord: Codable {
                let name: String
            }
            """,
            expandedSource: """
            fileprivate struct FileprivateRecord: Codable {
                let name: String

                fileprivate enum CodingKeys: String, CodingKey, CaseIterable {
                    case name
                }

                fileprivate typealias CSVCodingKeys = CodingKeys
            }

            extension FileprivateRecord: CSVIndexedDecodable {
            }

            extension FileprivateRecord: CSVIndexedEncodable {
            }
            """,
            macros: testMacros
        )
    }

    @Test("Macro generates private CodingKeys for private struct")
    func macroHandlesPrivateStruct() {
        assertMacroExpansion(
            """
            @CSVIndexed
            private struct PrivateRecord: Codable {
                let name: String
            }
            """,
            expandedSource: """
            private struct PrivateRecord: Codable {
                let name: String

                private enum CodingKeys: String, CodingKey, CaseIterable {
                    case name
                }

                private typealias CSVCodingKeys = CodingKeys
            }

            extension PrivateRecord: CSVIndexedDecodable {
            }

            extension PrivateRecord: CSVIndexedEncodable {
            }
            """,
            macros: testMacros
        )
    }

    @Test("Macro defaults to internal for struct with no explicit access level")
    func macroDefaultsToInternal() {
        // This is the same as the basic test but explicitly verifies
        // that no access modifier means internal (no prefix)
        assertMacroExpansion(
            """
            @CSVIndexed
            struct DefaultRecord: Codable {
                let value: Int
            }
            """,
            expandedSource: """
            struct DefaultRecord: Codable {
                let value: Int

                enum CodingKeys: String, CodingKey, CaseIterable {
                    case value
                }

                typealias CSVCodingKeys = CodingKeys
            }

            extension DefaultRecord: CSVIndexedDecodable {
            }

            extension DefaultRecord: CSVIndexedEncodable {
            }
            """,
            macros: testMacros
        )
    }
}

#endif
