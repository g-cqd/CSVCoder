//
//  CSVDecoderErrorTests.swift
//  CSVCoder
//
//  Tests for error locations, error suggestions, and diagnostics.
//

import Testing
@testable import CSVCoder
import Foundation

@Suite("CSVDecoder Error Tests")
struct CSVDecoderErrorTests {

    struct SimpleRecord: Codable, Equatable {
        let name: String
        let age: Int
        let score: Double
    }

    // MARK: - Error Location Tests

    @Test("Error includes row and column location")
    func errorIncludesLocation() throws {
        let csv = """
        name,age,score
        Alice,30,95.5
        Bob,invalid,88.0
        Carol,40,77.5
        """

        let decoder = CSVDecoder()

        do {
            _ = try decoder.decode([SimpleRecord].self, from: csv)
            Issue.record("Expected error to be thrown")
        } catch let error as CSVDecodingError {
            let location = error.location
            #expect(location?.row == 3)  // Row 3 (1-based, after header)
            #expect(location?.column == "age")

            let description = error.errorDescription ?? ""
            #expect(description.contains("row 3"))
            #expect(description.contains("age"))
        }
    }

    @Test("Error includes key not found location")
    func keyNotFoundErrorIncludesLocation() throws {
        struct StrictRecord: Codable {
            let name: String
            let requiredField: String
        }

        let csv = """
        name,otherField
        Alice,value
        """

        let decoder = CSVDecoder()

        do {
            _ = try decoder.decode([StrictRecord].self, from: csv)
            Issue.record("Expected error to be thrown")
        } catch let error as CSVDecodingError {
            let location = error.location
            #expect(location?.row == 2)
            #expect(location?.column == "requiredField")
        }
    }

    @Test("CSVLocation description formats correctly")
    func csvLocationDescription() {
        let location1 = CSVLocation(row: 5, column: "name", codingPath: [])
        #expect(location1.description == "row 5, column 'name'")

        let location2 = CSVLocation(row: 10, column: nil, codingPath: [])
        #expect(location2.description == "row 10")

        let location3 = CSVLocation(row: nil, column: "age", codingPath: [])
        #expect(location3.description == "column 'age'")

        let location4 = CSVLocation()
        #expect(location4.description == "unknown location")
    }

    @Test("CSVLocation equality ignores availableKeys")
    func csvLocationEqualityIgnoresAvailableKeys() {
        let loc1 = CSVLocation(row: 1, column: "name", availableKeys: ["a", "b"])
        let loc2 = CSVLocation(row: 1, column: "name", availableKeys: ["c", "d"])
        let loc3 = CSVLocation(row: 1, column: "name", availableKeys: nil)

        #expect(loc1 == loc2)
        #expect(loc2 == loc3)
    }

    // MARK: - Error Suggestion Tests

    @Test("Error suggests similar key for typo")
    func errorSuggestsSimilarKey() throws {
        let csv = """
        naame,age,score
        Alice,30,95.5
        """

        let decoder = CSVDecoder()
        do {
            _ = try decoder.decode([SimpleRecord].self, from: csv)
            Issue.record("Should have thrown an error")
        } catch let error as CSVDecodingError {
            let description = error.errorDescription ?? ""
            // Should suggest 'naame' for 'name'
            #expect(description.contains("Did you mean"))
        }
    }

    @Test("Error lists available columns for unknown key")
    func errorListsAvailableColumns() throws {
        struct TwoFields: Codable {
            let xyz: Int
            let abc: Int
        }

        let csv = """
        foo,bar
        1,2
        """

        let decoder = CSVDecoder()
        do {
            _ = try decoder.decode([TwoFields].self, from: csv)
            Issue.record("Should have thrown an error")
        } catch let error as CSVDecodingError {
            let description = error.errorDescription ?? ""
            // Should list available columns when no close match exists
            #expect(description.contains("Available columns") || description.contains("foo") || description.contains("bar"))
        }
    }

    @Test("Error suggests flexible number strategy for currency")
    func errorSuggestsNumberStrategy() throws {
        struct PriceRecord: Codable {
            let price: Double
        }

        let csv = """
        price
        $1,234.56
        """

        let decoder = CSVDecoder()
        do {
            _ = try decoder.decode([PriceRecord].self, from: csv)
            Issue.record("Should have thrown an error")
        } catch let error as CSVDecodingError {
            let suggestion = error.suggestion ?? ""
            #expect(suggestion.contains("numberDecodingStrategy") || suggestion.contains("currency"))
        }
    }

    @Test("Error suggests date strategy for date-like value")
    func errorSuggestsDateStrategy() throws {
        struct EventRecord: Codable {
            let date: Date
        }

        let csv = """
        date
        2024-12-25
        """

        // Default strategy is deferredToDate which will fail
        let decoder = CSVDecoder()
        do {
            _ = try decoder.decode([EventRecord].self, from: csv)
            Issue.record("Should have thrown an error")
        } catch let error as CSVDecodingError {
            // The error message itself contains strategy advice
            let description = error.errorDescription ?? ""
            #expect(description.contains("date strategy") || description.contains("Date"))
        }
    }

    @Test("Error suggestion for case mismatch")
    func errorSuggestionForCaseMismatch() throws {
        struct CaseSensitive: Codable {
            let Name: String  // uppercase N
        }

        let csv = """
        name
        Alice
        """

        let decoder = CSVDecoder()
        do {
            _ = try decoder.decode([CaseSensitive].self, from: csv)
            Issue.record("Should have thrown an error")
        } catch let error as CSVDecodingError {
            let description = error.errorDescription ?? ""
            #expect(description.contains("case differs") || description.contains("Did you mean"))
        }
    }
}
