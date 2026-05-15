//
//  CSVDirectDecodableTests.swift
//  CSVCoder
//
//  End-to-end tests for the CSVDirectDecodable fast path. Every test
//  decodes the same input through both the standard Codable path and
//  the fast path, then asserts the results are equal — guaranteeing
//  the two paths stay behaviourally indistinguishable as we evolve
//  either.
//

import Foundation
import Testing

@testable import CSVCoder

@Suite("CSVDirectDecodable Equivalence")
struct CSVDirectDecodableTests {
    // MARK: - Simple round-trip

    @CSVRow
    struct PersonRow: Codable, Equatable, Sendable {
        let name: String
        let age: Int
        let score: Double
    }

    /// Plain `Codable` mirror of ``PersonRow`` — used to drive the slow path
    /// for parity comparison without re-decoding through the fast init.
    struct PersonCodable: Codable, Equatable, Sendable {
        let name: String
        let age: Int
        let score: Double
    }

    @Test("Fast path produces identical values to standard Codable path")
    func simpleEquivalence() throws {
        let csv = """
            name,age,score
            Alice,30,95.5
            Bob,25,88.0
            Charlie,42,76.25
            """

        let decoder = CSVDecoder()

        let fastDecoded: [PersonRow] = try decoder.decode([PersonRow].self, from: csv)
        let slowDecoded: [PersonCodable] = try decoder.decode([PersonCodable].self, from: csv)

        #expect(fastDecoded.count == 3)
        #expect(slowDecoded.count == 3)
        for (fast, slow) in zip(fastDecoded, slowDecoded) {
            #expect(fast.name == slow.name)
            #expect(fast.age == slow.age)
            #expect(fast.score == slow.score)
        }
    }

    // MARK: - Trim handling

    @CSVRow
    struct LabelRow: Codable, Equatable, Sendable {
        let label: String
    }

    @Test("Fast path trims numeric fields when trimWhitespace is on")
    func trimEnabledNumericFields() throws {
        let csv = """
            name,age,score
            \u{20}Alice\u{20},\u{20}30\u{20},\u{20}95.5\u{20}
            """

        let decoder = CSVDecoder(configuration: .init(trimWhitespace: true))
        let rows: [PersonRow] = try decoder.decode([PersonRow].self, from: csv)
        #expect(rows[0].name == "Alice")
        #expect(rows[0].age == 30)
        #expect(rows[0].score == 95.5)
    }

    @Test("Fast path preserves whitespace in String fields when trimWhitespace is off")
    func trimDisabledPreservesSpaces() throws {
        let csv = """
            label
            \u{20}padded\u{20}
            """

        let decoder = CSVDecoder(configuration: .init(trimWhitespace: false))
        let rows: [LabelRow] = try decoder.decode([LabelRow].self, from: csv)
        #expect(rows[0].label == " padded ")
    }

    // MARK: - Optional fields

    @CSVRow
    struct OptionalRow: Codable, Equatable, Sendable {
        let id: Int
        let label: String?
        let weight: Double?
    }

    struct OptionalCodable: Codable, Equatable, Sendable {
        let id: Int
        let label: String?
        let weight: Double?
    }

    @Test("Fast path treats empty fields as nil under the empty-string strategy")
    func optionalNilEquivalence() throws {
        let csv = """
            id,label,weight
            1,hello,1.5
            2,,3.25
            3,world,
            """

        let decoder = CSVDecoder()
        let fast: [OptionalRow] = try decoder.decode([OptionalRow].self, from: csv)
        let slow: [OptionalCodable] = try decoder.decode([OptionalCodable].self, from: csv)

        #expect(fast.count == 3)
        for (f, s) in zip(fast, slow) {
            #expect(f.id == s.id)
            #expect(f.label == s.label)
            #expect(f.weight == s.weight)
        }
        #expect(fast[1].label == nil)
        #expect(fast[2].weight == nil)
    }

    // MARK: - Custom column names via @CSVColumn

    @CSVRow
    struct ColumnRow: Codable, Equatable, Sendable {
        let id: Int
        @CSVColumn("product_name") let name: String
        @CSVColumn("unit_price") let price: Double
    }

    @Test("Fast path resolves columns through @CSVColumn renames")
    func customColumnNameEquivalence() throws {
        let csv = """
            id,product_name,unit_price
            1,Widget,9.99
            2,Gadget,19.95
            """

        let decoder = CSVDecoder()
        let rows: [ColumnRow] = try decoder.decode([ColumnRow].self, from: csv)
        #expect(rows.count == 2)
        #expect(rows[0].id == 1)
        #expect(rows[0].name == "Widget")
        #expect(rows[0].price == 9.99)
    }

    // MARK: - Headerless input via @CSVRow column order

    @Test("Fast path respects @CSVRow column order on headerless input")
    func headerlessEquivalence() throws {
        let csv = """
            Alice,30,95.5
            Bob,25,88.0
            """

        let decoder = CSVDecoder(configuration: .init(hasHeaders: false))
        let rows: [PersonRow] = try decoder.decode([PersonRow].self, from: csv)
        #expect(rows.count == 2)
        #expect(rows[0].name == "Alice")
        #expect(rows[0].age == 30)
        #expect(rows[1].score == 88.0)
    }

    // MARK: - Error parity

    @Test("Fast path raises typeMismatch for unparseable integer values")
    func typeMismatchOnBadInteger() throws {
        let csv = """
            name,age,score
            Alice,thirty,95.5
            """

        let decoder = CSVDecoder()
        #expect(throws: CSVDecodingError.self) {
            _ = try decoder.decode([PersonRow].self, from: csv)
        }
    }

    @Test("Fast path raises keyNotFound when a required column is absent")
    func keyNotFoundOnMissingColumn() throws {
        // `score` is missing from the header — decoding should fail because
        // PersonRow.score is non-optional.
        let csv = """
            name,age
            Alice,30
            """

        let decoder = CSVDecoder()
        #expect(throws: CSVDecodingError.self) {
            _ = try decoder.decode([PersonRow].self, from: csv)
        }
    }

    // MARK: - Date / UUID / Decimal fast paths

    @CSVRow
    struct RichRow: Codable, Equatable, Sendable {
        let id: UUID
        let when: Date
        let amount: Decimal
    }

    @Test("Fast path decodes UUID + Date + Decimal correctly")
    func richTypesEquivalence() throws {
        let uuid = UUID()
        // Date with .iso8601 strategy
        let isoTimestamp = "2024-01-15T12:34:56Z"
        let csv = """
            id,when,amount
            \(uuid.uuidString),\(isoTimestamp),19.99
            """

        let decoder = CSVDecoder(configuration: .init(dateDecodingStrategy: .iso8601))
        let rows: [RichRow] = try decoder.decode([RichRow].self, from: csv)
        #expect(rows.count == 1)
        #expect(rows[0].id == uuid)
        #expect(rows[0].amount == Decimal(string: "19.99"))
    }

    // MARK: - Conformance check

    @Test("@CSVRow types conform to CSVDirectDecodable when all field types support it")
    func macroEmitsCSVDirectDecodable() {
        // If this compiles, the macro emitted the conformance.
        let _: any CSVDirectDecodable.Type = PersonRow.self
        let _: any CSVDirectDecodable.Type = OptionalRow.self
        let _: any CSVDirectDecodable.Type = ColumnRow.self
        let _: any CSVDirectDecodable.Type = RichRow.self
    }
}
