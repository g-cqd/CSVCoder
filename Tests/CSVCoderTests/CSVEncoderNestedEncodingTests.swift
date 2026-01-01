//
//  CSVEncoderNestedEncodingTests.swift
//  CSVCoder
//
//  Tests for CSVEncoder nested type encoding.
//

import Foundation
import Testing

@testable import CSVCoder

@Suite("CSVEncoder Nested Encoding Tests")
struct CSVEncoderNestedEncodingTests {
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

    @Test("Nested encoding with flatten strategy")
    func nestedEncodingFlatten() throws {
        let records = [
            PersonWithAddress(
                name: "Alice",
                age: 30,
                address: Address(street: "123 Main St", city: "Springfield", zipCode: "12345"),
            )
        ]

        let config = CSVEncoder.Configuration(nestedTypeEncodingStrategy: .flatten(separator: "_"))
        let encoder = CSVEncoder(configuration: config)
        let csv = try encoder.encodeToString(records)

        #expect(csv.contains("address_street"))
        #expect(csv.contains("address_city"))
        #expect(csv.contains("address_zipCode"))
        #expect(csv.contains("123 Main St"))
        #expect(csv.contains("Springfield"))
        #expect(csv.contains("12345"))
    }

    @Test("Nested encoding with JSON strategy")
    func nestedEncodingJSON() throws {
        let records = [
            PersonWithAddress(
                name: "Bob",
                age: 25,
                address: Address(street: "456 Oak Ave", city: "Shelbyville", zipCode: "67890"),
            )
        ]

        let config = CSVEncoder.Configuration(nestedTypeEncodingStrategy: .json)
        let encoder = CSVEncoder(configuration: config)
        let csv = try encoder.encodeToString(records)

        #expect(csv.contains("Bob"))
        #expect(csv.contains("25"))
        #expect(csv.contains("city"))
        #expect(csv.contains("street"))
    }

    @Test("Nested encoding with codable strategy")
    func nestedEncodingCodable() throws {
        let records = [
            PersonWithAddress(
                name: "Carol",
                age: 35,
                address: Address(street: "789 Pine Rd", city: "Capital City", zipCode: "11111"),
            )
        ]

        let config = CSVEncoder.Configuration(nestedTypeEncodingStrategy: .codable)
        let encoder = CSVEncoder(configuration: config)
        let csv = try encoder.encodeToString(records)

        #expect(csv.contains("Carol"))
        #expect(csv.contains("35"))
        #expect(csv.contains("city") || csv.contains("Capital City"))
    }

    @Test("Nested encoding roundtrip with flatten strategy")
    func nestedEncodingRoundtripFlatten() throws {
        let original = [
            PersonWithAddress(
                name: "Dave",
                age: 40,
                address: Address(street: "321 Elm St", city: "Townsville", zipCode: "22222"),
            )
        ]

        let encoderConfig = CSVEncoder.Configuration(nestedTypeEncodingStrategy: .flatten(separator: "_"))
        let encoder = CSVEncoder(configuration: encoderConfig)
        let csv = try encoder.encodeToString(original)

        let decoderConfig = CSVDecoder.Configuration(nestedTypeDecodingStrategy: .flatten(separator: "_"))
        let decoder = CSVDecoder(configuration: decoderConfig)
        let decoded = try decoder.decode([PersonWithAddress].self, from: csv)

        #expect(decoded == original)
    }

    @Test("Nested encoding roundtrip with JSON strategy")
    func nestedEncodingRoundtripJSON() throws {
        let original = [
            PersonWithAddress(
                name: "Eve",
                age: 28,
                address: Address(street: "555 Maple Dr", city: "Riverdale", zipCode: "33333"),
            )
        ]

        let encoderConfig = CSVEncoder.Configuration(nestedTypeEncodingStrategy: .json)
        let encoder = CSVEncoder(configuration: encoderConfig)
        let csv = try encoder.encodeToString(original)

        let decoderConfig = CSVDecoder.Configuration(nestedTypeDecodingStrategy: .json)
        let decoder = CSVDecoder(configuration: decoderConfig)
        let decoded = try decoder.decode([PersonWithAddress].self, from: csv)

        #expect(decoded == original)
    }

    @Test("Nested encoding with multiple nested fields")
    func nestedEncodingMultipleNestedFields() throws {
        struct Contact: Codable, Equatable {
            let email: String
            let phone: String
        }

        struct Employee: Codable, Equatable {
            let name: String
            let address: Address
            let contact: Contact
        }

        let records = [
            Employee(
                name: "Frank",
                address: Address(street: "100 Work St", city: "Office City", zipCode: "44444"),
                contact: Contact(email: "frank@example.com", phone: "555-1234"),
            )
        ]

        let config = CSVEncoder.Configuration(nestedTypeEncodingStrategy: .flatten(separator: "_"))
        let encoder = CSVEncoder(configuration: config)
        let csv = try encoder.encodeToString(records)

        #expect(csv.contains("address_street"))
        #expect(csv.contains("contact_email"))
        #expect(csv.contains("frank@example.com"))
    }

    @Test("Nested encoding error strategy throws for nested types")
    func nestedEncodingErrorStrategy() throws {
        let records = [
            PersonWithAddress(
                name: "Grace",
                age: 45,
                address: Address(street: "999 Error St", city: "Failtown", zipCode: "00000"),
            )
        ]

        let config = CSVEncoder.Configuration(nestedTypeEncodingStrategy: .error)
        let encoder = CSVEncoder(configuration: config)

        #expect(throws: (any Error).self) {
            _ = try encoder.encodeToString(records)
        }
    }

    @Test("Nested encoding with special characters in nested values")
    func nestedEncodingSpecialCharacters() throws {
        let records = [
            PersonWithAddress(
                name: "Henry",
                age: 50,
                address: Address(street: "123 \"Quoted\" St, Apt 5", city: "New\nYork", zipCode: "55555"),
            )
        ]

        let encoderConfig = CSVEncoder.Configuration(nestedTypeEncodingStrategy: .flatten(separator: "_"))
        let encoder = CSVEncoder(configuration: encoderConfig)
        let csv = try encoder.encodeToString(records)

        let decoderConfig = CSVDecoder.Configuration(nestedTypeDecodingStrategy: .flatten(separator: "_"))
        let decoder = CSVDecoder(configuration: decoderConfig)
        let decoded = try decoder.decode([PersonWithAddress].self, from: csv)

        #expect(decoded == records)
    }
}
