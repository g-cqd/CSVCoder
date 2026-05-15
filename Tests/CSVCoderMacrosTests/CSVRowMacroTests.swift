//
//  CSVRowMacroTests.swift
//  CSVCoder
//
//  Tests for @CSVRow and @CSVColumn macros.
//

import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

#if canImport(CSVCoderMacros)
    @testable import CSVCoderMacros

    @Suite("CSVRow Macro Tests")
    struct CSVRowMacroTests {
        let testMacros: [String: Macro.Type] = [
            "CSVRow": CSVRowMacro.self,
            "CSVColumn": CSVColumnMacro.self,
        ]

        // MARK: - Direct-decode fast path

        @Test("Macro synthesizes CSVDirectDecodable when all field types are supported")
        func macroEmitsDirectDecodable() {
            assertMacroExpansion(
                """
                @CSVRow
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

                    extension Person: CSVRowDecodable {
                    }

                    extension Person: CSVRowEncodable {
                    }

                    extension Person: CSVDirectDecodable {
                        public init(
                            csvRow: CSVRowView,
                            columnIndices: [Int],
                            configuration: CSVDecoder.Configuration,
                            rowIndex: Int?
                        ) throws {
                            self.name = try CSVDirectFieldDecoder.string(from: csvRow, index: columnIndices[0], configuration: configuration, key: "name", rowIndex: rowIndex)
                            self.age = try CSVDirectFieldDecoder.integer(Int.self, from: csvRow, index: columnIndices[1], configuration: configuration, key: "age", rowIndex: rowIndex)
                        }
                    }
                    """,
                macros: testMacros,
            )
        }

        // MARK: - Basic Expansion Tests

        @Test("Basic macro expansion generates CodingKeys and typealias")
        func basicMacroExpansion() {
            assertMacroExpansion(
                """
                @CSVRow
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

                    extension Person: CSVRowDecodable {
                    }

                    extension Person: CSVRowEncodable {
                    }
                    """,
                macros: testMacros,
            )
        }

        @Test("Macro handles optional properties")
        func macroWithOptionalProperty() {
            assertMacroExpansion(
                """
                @CSVRow
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

                    extension User: CSVRowDecodable {
                    }

                    extension User: CSVRowEncodable {
                    }
                    """,
                macros: testMacros,
            )
        }

        // MARK: - @CSVColumn Tests

        @Test("Macro with @CSVColumn generates custom raw values")
        func macroWithCSVColumn() {
            assertMacroExpansion(
                """
                @CSVRow
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

                    extension Product: CSVRowDecodable {
                    }

                    extension Product: CSVRowEncodable {
                    }
                    """,
                macros: testMacros,
            )
        }

        // MARK: - Property Order Tests

        @Test("Macro preserves property declaration order")
        func macroPreservesPropertyOrder() {
            assertMacroExpansion(
                """
                @CSVRow
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

                    extension Record: CSVRowDecodable {
                    }

                    extension Record: CSVRowEncodable {
                    }
                    """,
                macros: testMacros,
            )
        }

        // MARK: - Error Cases

        @Test("Macro fails on class")
        func macroFailsOnClass() {
            assertMacroExpansion(
                """
                @CSVRow
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
                    DiagnosticSpec(message: "@CSVRow can only be applied to structs", line: 1, column: 1)
                ],
                macros: testMacros,
            )
        }

        // MARK: - Computed Property Tests

        @Test("Macro skips computed properties")
        func macroSkipsComputedProperties() {
            assertMacroExpansion(
                """
                @CSVRow
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

                    extension WithComputed: CSVRowDecodable {
                    }

                    extension WithComputed: CSVRowEncodable {
                    }
                    """,
                macros: testMacros,
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
                macros: testMacros,
            )
        }

        // MARK: - Multiple Properties Tests

        @Test("Macro handles many properties")
        func macroHandlesManyProperties() {
            assertMacroExpansion(
                """
                @CSVRow
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

                    extension LargeRecord: CSVRowDecodable {
                    }

                    extension LargeRecord: CSVRowEncodable {
                    }
                    """,
                macros: testMacros,
            )
        }

        // MARK: - Access Level Tests

        @Test("Macro generates public CodingKeys and typealias for public struct")
        func macroHandlesPublicStruct() {
            assertMacroExpansion(
                """
                @CSVRow
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

                    extension PublicRecord: CSVRowDecodable {
                    }

                    extension PublicRecord: CSVRowEncodable {
                    }
                    """,
                macros: testMacros,
            )
        }

        @Test("Macro generates public members with @CSVColumn for public struct")
        func macroHandlesPublicStructWithCSVColumn() {
            assertMacroExpansion(
                """
                @CSVRow
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

                    extension PublicProduct: CSVRowDecodable {
                    }

                    extension PublicProduct: CSVRowEncodable {
                    }
                    """,
                macros: testMacros,
            )
        }

        @Test("Macro generates internal CodingKeys for internal struct")
        func macroHandlesInternalStruct() {
            assertMacroExpansion(
                """
                @CSVRow
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

                    extension InternalRecord: CSVRowDecodable {
                    }

                    extension InternalRecord: CSVRowEncodable {
                    }
                    """,
                macros: testMacros,
            )
        }

        @Test("Macro generates fileprivate CodingKeys for fileprivate struct")
        func macroHandlesFileprivateStruct() {
            assertMacroExpansion(
                """
                @CSVRow
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

                    extension FileprivateRecord: CSVRowDecodable {
                    }

                    extension FileprivateRecord: CSVRowEncodable {
                    }
                    """,
                macros: testMacros,
            )
        }

        @Test("Macro generates private CodingKeys for private struct")
        func macroHandlesPrivateStruct() {
            assertMacroExpansion(
                """
                @CSVRow
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

                    extension PrivateRecord: CSVRowDecodable {
                    }

                    extension PrivateRecord: CSVRowEncodable {
                    }
                    """,
                macros: testMacros,
            )
        }

        @Test("Macro defaults to internal for struct with no explicit access level")
        func macroDefaultsToInternal() {
            // This is the same as the basic test but explicitly verifies
            // that no access modifier means internal (no prefix)
            assertMacroExpansion(
                """
                @CSVRow
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

                    extension DefaultRecord: CSVRowDecodable {
                    }

                    extension DefaultRecord: CSVRowEncodable {
                    }
                    """,
                macros: testMacros,
            )
        }

        // MARK: - Diagnostics

        @Test("Macro reports duplicate @CSVColumn names")
        func macroReportsDuplicateColumns() {
            assertMacroExpansion(
                """
                @CSVRow
                struct R: Codable {
                    @CSVColumn("x")
                    let a: Int
                    @CSVColumn("x")
                    let b: Int
                }
                """,
                expandedSource: """
                    struct R: Codable {
                        @CSVColumn("x")
                        let a: Int
                        @CSVColumn("x")
                        let b: Int

                        enum CodingKeys: String, CodingKey, CaseIterable {
                            case a = "x"
                            case b = "x"
                        }

                        typealias CSVCodingKeys = CodingKeys
                    }

                    extension R: CSVRowDecodable {
                    }

                    extension R: CSVRowEncodable {
                    }
                    """,
                diagnostics: [
                    DiagnosticSpec(
                        message: "Duplicate CSV column name 'x' on 'a' and 'b'",
                        line: 5,
                        column: 5,
                    )
                ],
                macros: testMacros,
            )
        }

        @Test("Macro warns on orphan @CSVColumn (no @CSVRow on container)")
        func macroWarnsOnOrphanCSVColumn() {
            assertMacroExpansion(
                """
                struct Loose: Codable {
                    @CSVColumn("renamed")
                    let value: Int
                }
                """,
                expandedSource: """
                    struct Loose: Codable {
                        @CSVColumn("renamed")
                        let value: Int
                    }
                    """,
                diagnostics: [
                    DiagnosticSpec(
                        message: "@CSVColumn has no effect without @CSVRow on the containing struct",
                        line: 2,
                        column: 5,
                        severity: .warning,
                    )
                ],
                macros: testMacros,
            )
        }

        @Test("Macro escapes Swift keyword property names")
        func macroEscapesKeywords() {
            assertMacroExpansion(
                """
                @CSVRow
                struct K: Codable {
                    let `init`: Int
                    let `class`: String
                }
                """,
                expandedSource: """
                    struct K: Codable {
                        let `init`: Int
                        let `class`: String

                        enum CodingKeys: String, CodingKey, CaseIterable {
                            case `init`
                            case `class`
                        }

                        typealias CSVCodingKeys = CodingKeys
                    }

                    extension K: CSVRowDecodable {
                    }

                    extension K: CSVRowEncodable {
                    }
                    """,
                macros: testMacros,
            )
        }
    }

#endif
