//
//  CSVDecoderNestedTests.swift
//  CSVCoder
//
//  Tests for nested type decoding strategies (flatten, JSON, codable).
//

import Foundation
import Testing

@testable import CSVCoder

@Suite("CSVDecoder Nested Tests")
struct CSVDecoderNestedTests {
    struct Address: Codable, Equatable {
        let street: String
        let city: String
        let zipCode: String
    }

    struct PersonWithAddress: Codable, Equatable {
        let name: String
        let age: Int
        let address: Address
    }

    // MARK: - Flatten Strategy Tests

    @Test("Nested decoding with flatten strategy")
    func nestedDecodingFlatten() throws {
        let csv = """
            name,age,address_street,address_city,address_zipCode
            Alice,30,123 Main St,Springfield,12345
            Bob,25,456 Oak Ave,Shelbyville,67890
            """

        let config = CSVDecoder.Configuration(nestedTypeDecodingStrategy: .flatten(separator: "_"))
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([PersonWithAddress].self, from: csv)

        #expect(records.count == 2)
        #expect(records[0].name == "Alice")
        #expect(records[0].age == 30)
        #expect(records[0].address.street == "123 Main St")
        #expect(records[0].address.city == "Springfield")
        #expect(records[0].address.zipCode == "12345")
        #expect(records[1].address.city == "Shelbyville")
    }

    @Test("Nested decoding with custom separator")
    func nestedDecodingCustomSeparator() throws {
        let csv = """
            name,age,address.street,address.city,address.zipCode
            Grace,45,999 Dot St,Dotville,55555
            """

        let config = CSVDecoder.Configuration(nestedTypeDecodingStrategy: .flatten(separator: "."))
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([PersonWithAddress].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].address.street == "999 Dot St")
        #expect(records[0].address.city == "Dotville")
    }

    @Test("Nested decoding with multiple nested fields flatten")
    func nestedDecodingMultipleNestedFields() throws {
        struct Contact: Codable, Equatable {
            let email: String
            let phone: String
        }

        struct Employee: Codable, Equatable {
            let name: String
            let address: Address
            let contact: Contact
        }

        let csv = """
            name,address_street,address_city,address_zipCode,contact_email,contact_phone
            Frank,100 Work St,Office City,44444,frank@example.com,555-1234
            """

        let config = CSVDecoder.Configuration(nestedTypeDecodingStrategy: .flatten(separator: "_"))
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([Employee].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].name == "Frank")
        #expect(records[0].address.street == "100 Work St")
        #expect(records[0].contact.email == "frank@example.com")
        #expect(records[0].contact.phone == "555-1234")
    }

    @Test("Nested decoding with special characters in values")
    func nestedDecodingSpecialCharacters() throws {
        // Build CSV with embedded newline
        let csv =
            "name,age,address_street,address_city,address_zipCode\nHenry,50,\"123 \"\"Quoted\"\" St, Apt 5\",\"New\nYork\",66666"

        let config = CSVDecoder.Configuration(nestedTypeDecodingStrategy: .flatten(separator: "_"))
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([PersonWithAddress].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].address.street == "123 \"Quoted\" St, Apt 5")
        #expect(records[0].address.city == "New\nYork")
    }

    // MARK: - JSON Strategy Tests

    @Test("Nested decoding with JSON strategy")
    func nestedDecodingJSON() throws {
        // JSON inside CSV needs double-escaped quotes: "" for CSV, then the JSON uses \"
        let json = #"{"street":"789 Pine Rd","city":"Capital City","zipCode":"11111"}"#
        let csv = "name,age,address\nCarol,35,\"\(json.replacingOccurrences(of: "\"", with: "\"\""))\""

        let config = CSVDecoder.Configuration(nestedTypeDecodingStrategy: .json())
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([PersonWithAddress].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].name == "Carol")
        #expect(records[0].address.street == "789 Pine Rd")
        #expect(records[0].address.city == "Capital City")
    }

    // MARK: - Error Strategy Tests

    @Test("Nested decoding error strategy throws for nested types")
    func nestedDecodingErrorStrategy() throws {
        let csv = """
            name,age,address_street,address_city,address_zipCode
            Eve,28,555 Maple Dr,Riverdale,33333
            """

        let config = CSVDecoder.Configuration(nestedTypeDecodingStrategy: .error)
        let decoder = CSVDecoder(configuration: config)

        // With .error strategy, decoding nested types should fail
        #expect(throws: (any Error).self) {
            _ = try decoder.decode([PersonWithAddress].self, from: csv)
        }
    }

    // MARK: - JSON Byte Limit

    @Test("Nested JSON strategy rejects cells exceeding maxBytes")
    func nestedJSONRejectsOversizedCells() throws {
        // Build a JSON cell larger than the configured limit (1 KiB cap).
        let bigString = String(repeating: "A", count: 4_096)
        let json =
            #"{"street":"\#(bigString)","city":"X","zipCode":"1"}"#
        let escaped = json.replacingOccurrences(of: "\"", with: "\"\"")
        let csv = "name,age,address\nMallory,99,\"\(escaped)\""

        let config = CSVDecoder.Configuration(nestedTypeDecodingStrategy: .json(maxBytes: 1_024))
        let decoder = CSVDecoder(configuration: config)

        #expect(throws: CSVDecodingError.self) {
            _ = try decoder.decode([PersonWithAddress].self, from: csv)
        }
    }

    @Test("Nested JSON strategy accepts cells within maxBytes")
    func nestedJSONAcceptsSmallCells() throws {
        let json = #"{"street":"1 A St","city":"X","zipCode":"1"}"#
        let escaped = json.replacingOccurrences(of: "\"", with: "\"\"")
        let csv = "name,age,address\nAlice,30,\"\(escaped)\""

        let config = CSVDecoder.Configuration(nestedTypeDecodingStrategy: .json(maxBytes: 1 << 20))
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([PersonWithAddress].self, from: csv)
        #expect(records.count == 1)
        #expect(records[0].address.street == "1 A St")
    }
}
