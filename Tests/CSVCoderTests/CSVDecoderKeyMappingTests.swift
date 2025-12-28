//
//  CSVDecoderKeyMappingTests.swift
//  CSVCoder
//
//  Tests for key strategies, column mapping, index mapping, and CSVIndexedDecodable.
//

import Testing
@testable import CSVCoder
import Foundation

@Suite("CSVDecoder Key Mapping Tests")
struct CSVDecoderKeyMappingTests {

    struct SimpleRecord: Codable, Equatable {
        let name: String
        let age: Int
        let score: Double
    }

    struct CamelCaseRecord: Codable, Equatable {
        let firstName: String
        let lastName: String
        let emailAddress: String
    }

    // MARK: - Key Decoding Strategy Tests

    @Test("Decode with snake_case to camelCase conversion")
    func decodeSnakeCaseToCamelCase() throws {
        let csv = """
        first_name,last_name,email_address
        John,Doe,john@example.com
        Jane,Smith,jane@example.com
        """

        let config = CSVDecoder.Configuration(
            keyDecodingStrategy: .convertFromSnakeCase
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([CamelCaseRecord].self, from: csv)

        #expect(records.count == 2)
        #expect(records[0] == CamelCaseRecord(firstName: "John", lastName: "Doe", emailAddress: "john@example.com"))
        #expect(records[1] == CamelCaseRecord(firstName: "Jane", lastName: "Smith", emailAddress: "jane@example.com"))
    }

    @Test("Decode with kebab-case to camelCase conversion")
    func decodeKebabCaseToCamelCase() throws {
        let csv = """
        first-name,last-name,email-address
        Alice,Johnson,alice@example.com
        """

        let config = CSVDecoder.Configuration(
            keyDecodingStrategy: .convertFromKebabCase
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([CamelCaseRecord].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].firstName == "Alice")
        #expect(records[0].lastName == "Johnson")
    }

    @Test("Decode with SCREAMING_SNAKE_CASE to camelCase conversion")
    func decodeScreamingSnakeCaseToCamelCase() throws {
        let csv = """
        FIRST_NAME,LAST_NAME,EMAIL_ADDRESS
        Bob,Wilson,bob@example.com
        """

        let config = CSVDecoder.Configuration(
            keyDecodingStrategy: .convertFromScreamingSnakeCase
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([CamelCaseRecord].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].firstName == "Bob")
    }

    @Test("Decode with PascalCase to camelCase conversion")
    func decodePascalCaseToCamelCase() throws {
        let csv = """
        FirstName,LastName,EmailAddress
        Carol,Brown,carol@example.com
        """

        let config = CSVDecoder.Configuration(
            keyDecodingStrategy: .convertFromPascalCase
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([CamelCaseRecord].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].firstName == "Carol")
    }

    @Test("Decode with custom key transformation")
    func decodeWithCustomKeyTransformation() throws {
        let csv = """
        fn,ln,email
        David,Lee,david@example.com
        """

        let config = CSVDecoder.Configuration(
            keyDecodingStrategy: .custom { key in
                switch key {
                case "fn": return "firstName"
                case "ln": return "lastName"
                default: return key + "Address"
                }
            }
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([CamelCaseRecord].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].firstName == "David")
        #expect(records[0].lastName == "Lee")
        #expect(records[0].emailAddress == "david@example.com")
    }

    // MARK: - Column Mapping Tests

    @Test("Decode with explicit column mapping")
    func decodeWithColumnMapping() throws {
        let csv = """
        First Name,Last Name,E-mail
        Emily,Davis,emily@example.com
        """

        let config = CSVDecoder.Configuration(
            columnMapping: [
                "First Name": "firstName",
                "Last Name": "lastName",
                "E-mail": "emailAddress"
            ]
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([CamelCaseRecord].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].firstName == "Emily")
        #expect(records[0].lastName == "Davis")
        #expect(records[0].emailAddress == "emily@example.com")
    }

    @Test("Column mapping takes precedence over key strategy")
    func columnMappingTakesPrecedence() throws {
        let csv = """
        first_name,surname,email_address
        Frank,Miller,frank@example.com
        """

        let config = CSVDecoder.Configuration(
            keyDecodingStrategy: .convertFromSnakeCase,
            columnMapping: [
                "surname": "lastName"  // Override snake_case conversion for this column
            ]
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([CamelCaseRecord].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].firstName == "Frank")
        #expect(records[0].lastName == "Miller")
    }

    // MARK: - Index-Based Decoding Tests

    @Test("Decode headerless CSV with index mapping")
    func decodeHeaderlessWithIndexMapping() throws {
        let csv = """
        Alice,30,95.5
        Bob,25,88.0
        Carol,35,92.0
        """

        let config = CSVDecoder.Configuration(
            hasHeaders: false,
            indexMapping: [0: "name", 1: "age", 2: "score"]
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([SimpleRecord].self, from: csv)

        #expect(records.count == 3)
        #expect(records[0] == SimpleRecord(name: "Alice", age: 30, score: 95.5))
        #expect(records[1] == SimpleRecord(name: "Bob", age: 25, score: 88.0))
        #expect(records[2] == SimpleRecord(name: "Carol", age: 35, score: 92.0))
    }

    @Test("Index mapping with sparse indices")
    func indexMappingWithSparseIndices() throws {
        // CSV with extra columns we want to skip
        let csv = """
        ignore,Alice,skip,30,extra,95.5
        ignore,Bob,skip,25,extra,88.0
        """

        let config = CSVDecoder.Configuration(
            hasHeaders: false,
            indexMapping: [1: "name", 3: "age", 5: "score"]
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([SimpleRecord].self, from: csv)

        #expect(records.count == 2)
        #expect(records[0].name == "Alice")
        #expect(records[0].age == 30)
        #expect(records[0].score == 95.5)
    }

    @Test("Index mapping overrides header names")
    func indexMappingOverridesHeaders() throws {
        // CSV has headers but we want to use different property names
        let csv = """
        col1,col2,col3
        David,40,77.5
        """

        let config = CSVDecoder.Configuration(
            hasHeaders: true,
            indexMapping: [0: "name", 1: "age", 2: "score"]
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([SimpleRecord].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].name == "David")
        #expect(records[0].age == 40)
    }

    @Test("Index mapping with partial coverage")
    func indexMappingPartialCoverage() throws {
        struct PartialRecord: Codable, Equatable {
            let first: String
            let third: String
        }

        let csv = """
        a,b,c
        value1,value2,value3
        """

        let config = CSVDecoder.Configuration(
            hasHeaders: false,
            indexMapping: [0: "first", 2: "third"]
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([PartialRecord].self, from: csv)

        #expect(records.count == 2) // Header row is treated as data
        #expect(records[0].first == "a")
        #expect(records[0].third == "c")
    }

    // MARK: - CSVIndexedDecodable Tests

    struct IndexedRecord: CSVIndexedDecodable, Equatable {
        let name: String
        let age: Int
        let score: Double

        enum CodingKeys: String, CodingKey, CaseIterable {
            case name, age, score
        }

        typealias CSVCodingKeys = CodingKeys
    }

    @Test("Decode headerless CSV with CSVIndexedDecodable")
    func decodeHeaderlessWithCSVIndexedDecodable() throws {
        let csv = """
        Alice,30,95.5
        Bob,25,88.0
        Carol,35,92.0
        """

        // No indexMapping needed - uses CodingKeys order
        let config = CSVDecoder.Configuration(hasHeaders: false)
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([IndexedRecord].self, from: csv)

        #expect(records.count == 3)
        #expect(records[0] == IndexedRecord(name: "Alice", age: 30, score: 95.5))
        #expect(records[1] == IndexedRecord(name: "Bob", age: 25, score: 88.0))
        #expect(records[2] == IndexedRecord(name: "Carol", age: 35, score: 92.0))
    }

    @Test("CSVIndexedDecodable with headers still works")
    func csvIndexedDecodableWithHeaders() throws {
        let csv = """
        name,age,score
        Alice,30,95.5
        """

        let decoder = CSVDecoder()
        let records = try decoder.decode([IndexedRecord].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].name == "Alice")
    }

    @Test("CSVIndexedDecodable column order is correct")
    func csvIndexedDecodableColumnOrder() {
        let order = IndexedRecord.csvColumnOrder
        #expect(order == ["name", "age", "score"])
    }

    @Test("Explicit indexMapping overrides CSVIndexedDecodable")
    func explicitIndexMappingOverridesCSVIndexed() throws {
        let csv = """
        95.5,30,Alice
        """

        // Explicit indexMapping should take precedence
        let config = CSVDecoder.Configuration(
            hasHeaders: false,
            indexMapping: [2: "name", 1: "age", 0: "score"]
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([IndexedRecord].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].name == "Alice")
        #expect(records[0].age == 30)
        #expect(records[0].score == 95.5)
    }

    struct ReorderedRecord: CSVIndexedDecodable, Equatable {
        let first: String
        let second: Int
        let third: Double

        enum CodingKeys: String, CodingKey, CaseIterable {
            case third, first, second  // Different order than properties
        }

        typealias CSVCodingKeys = CodingKeys
    }

    @Test("CSVIndexedDecodable respects CodingKeys case order")
    func csvIndexedDecodableRespectsOrder() throws {
        // CSV columns match CodingKeys order: third, first, second
        let csv = """
        99.9,hello,42
        """

        let config = CSVDecoder.Configuration(hasHeaders: false)
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([ReorderedRecord].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].third == 99.9)
        #expect(records[0].first == "hello")
        #expect(records[0].second == 42)
    }
}
