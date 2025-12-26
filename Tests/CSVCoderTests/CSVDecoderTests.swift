//
//  CSVDecoderTests.swift
//  CSVCoder
//
//  Tests for CSVDecoder.
//

import Testing
@testable import CSVCoder
import Foundation

@Suite("CSVDecoder Tests")
struct CSVDecoderTests {

    struct SimpleRecord: Codable, Equatable {
        let name: String
        let age: Int
        let score: Double
    }

    @Test("Decode simple records")
    func decodeSimpleRecords() throws {
        let csv = """
        name,age,score
        Alice,30,95.5
        Bob,25,88.0
        """

        let decoder = CSVDecoder()
        let records = try decoder.decode([SimpleRecord].self, from: csv)

        #expect(records.count == 2)
        #expect(records[0] == SimpleRecord(name: "Alice", age: 30, score: 95.5))
        #expect(records[1] == SimpleRecord(name: "Bob", age: 25, score: 88.0))
    }

    struct NameAge: Codable, Equatable {
        let name: String
        let age: Int
    }

    @Test("Decode with semicolon delimiter")
    func decodeWithSemicolonDelimiter() throws {
        let csv = """
        name;age
        Charlie;35
        """

        let config = CSVDecoder.Configuration(delimiter: ";")
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([NameAge].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].name == "Charlie")
        #expect(records[0].age == 35)
    }

    struct DateRecord: Codable {
        let event: String
        let date: Date
    }

    @Test("Decode dates with format")
    func decodeDatesWithFormat() throws {
        let csv = """
        event,date
        Meeting,25/12/2024
        """

        let config = CSVDecoder.Configuration(
            dateDecodingStrategy: .formatted("dd/MM/yyyy")
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([DateRecord].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].event == "Meeting")
    }

    @Test("Decode from single row dictionary")
    func decodeFromDictionary() throws {
        let row = ["name": "Eve", "age": "28", "score": "92.5"]

        let decoder = CSVDecoder()
        let record = try decoder.decode(SimpleRecord.self, from: row)

        #expect(record.name == "Eve")
        #expect(record.age == 28)
        #expect(record.score == 92.5)
    }

    @Test("Handle quoted fields with delimiters")
    func handleQuotedFields() throws {
        let csv = """
        name,description
        Test,"Value,with,commas"
        """

        let decoder = CSVDecoder()

        struct QuotedRecord: Codable {
            let name: String
            let description: String
        }

        let records = try decoder.decode([QuotedRecord].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].description == "Value,with,commas")
    }

    @Test("Handle empty values")
    func handleEmptyValues() throws {
        let csv = """
        name,value
        Test,
        """

        struct OptionalRecord: Codable {
            let name: String
            let value: String?
        }

        let decoder = CSVDecoder()
        let records = try decoder.decode([OptionalRecord].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].value == nil)
    }

    @Test("Decode UInt8 values")
    func decodeUInt8Values() throws {
        let csv = """
        id,value
        1,42
        2,255
        """

        struct ByteRecord: Codable {
            let id: Int
            let value: UInt8
        }

        let decoder = CSVDecoder()
        let records = try decoder.decode([ByteRecord].self, from: csv)

        #expect(records.count == 2)
        #expect(records[0].value == 42)
        #expect(records[1].value == 255)
    }

    @Test("Decode Decimal values")
    func decodeDecimalValues() throws {
        let csv = """
        price,quantity
        19.99,100
        0.001,999999
        """

        struct PriceRecord: Codable, Equatable {
            let price: Decimal
            let quantity: Int
        }

        let decoder = CSVDecoder()
        let records = try decoder.decode([PriceRecord].self, from: csv)

        #expect(records.count == 2)
        #expect(records[0].price == Decimal(string: "19.99"))
        #expect(records[1].price == Decimal(string: "0.001"))
    }

    @Test("Decode UUID values")
    func decodeUUIDValues() throws {
        let uuid1 = UUID()
        let uuid2 = UUID()
        let csv = """
        id,name
        \(uuid1.uuidString),Item1
        \(uuid2.uuidString),Item2
        """

        struct UUIDRecord: Codable {
            let id: UUID
            let name: String
        }

        let decoder = CSVDecoder()
        let records = try decoder.decode([UUIDRecord].self, from: csv)

        #expect(records.count == 2)
        #expect(records[0].id == uuid1)
        #expect(records[1].id == uuid2)
    }

    @Test("Decode URL values")
    func decodeURLValues() throws {
        let csv = """
        name,website
        Example,https://example.com
        Test,https://test.com/path?query=1
        """

        struct URLRecord: Codable {
            let name: String
            let website: URL
        }

        let decoder = CSVDecoder()
        let records = try decoder.decode([URLRecord].self, from: csv)

        #expect(records.count == 2)
        #expect(records[0].website == URL(string: "https://example.com"))
        #expect(records[1].website == URL(string: "https://test.com/path?query=1"))
    }

    // MARK: - Flexible Date Decoding Tests

    @Test("Decode dates with flexible strategy - ISO format")
    func decodeDatesFlexibleISO() throws {
        let csv = """
        event,date
        Meeting,2024-12-25
        """

        let config = CSVDecoder.Configuration(dateDecodingStrategy: .flexible)
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([DateRecord].self, from: csv)

        #expect(records.count == 1)
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: records[0].date)
        #expect(components.year == 2024)
        #expect(components.month == 12)
        #expect(components.day == 25)
    }

    @Test("Decode dates with flexible strategy - European format")
    func decodeDatesFlexibleEuropean() throws {
        let csv = """
        event,date
        Conference,25/12/2024
        """

        let config = CSVDecoder.Configuration(dateDecodingStrategy: .flexible)
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([DateRecord].self, from: csv)

        #expect(records.count == 1)
    }

    @Test("Decode dates with flexible strategy - multiple formats in same file")
    func decodeDatesFlexibleMixed() throws {
        let csv = """
        event,date
        ISO,2024-12-25
        European,25.12.2024
        USFormat,12/25/2024
        """

        let config = CSVDecoder.Configuration(dateDecodingStrategy: .flexible)
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([DateRecord].self, from: csv)

        #expect(records.count == 3)
    }

    @Test("Decode dates with flexibleWithHint strategy")
    func decodeDatesFlexibleWithHint() throws {
        let csv = """
        event,date
        Meeting,25-Dec-2024
        """

        let config = CSVDecoder.Configuration(
            dateDecodingStrategy: .flexibleWithHint(preferred: "dd-MMM-yyyy")
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([DateRecord].self, from: csv)

        #expect(records.count == 1)
    }

    // MARK: - Flexible Number Decoding Tests

    struct PriceRecord: Codable, Equatable {
        let item: String
        let price: Double
    }

    @Test("Decode numbers with flexible strategy - US format")
    func decodeNumbersFlexibleUS() throws {
        let csv = """
        item,price
        Widget,1234.56
        Gadget,"1,234.56"
        """

        let config = CSVDecoder.Configuration(numberDecodingStrategy: .flexible)
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([PriceRecord].self, from: csv)

        #expect(records.count == 2)
        #expect(records[0].price == 1234.56)
        #expect(records[1].price == 1234.56)
    }

    @Test("Decode numbers with flexible strategy - European format")
    func decodeNumbersFlexibleEuropean() throws {
        let csv = """
        item,price
        Widget,"1.234,56"
        Simple,"45,50"
        """

        let config = CSVDecoder.Configuration(numberDecodingStrategy: .flexible)
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([PriceRecord].self, from: csv)

        #expect(records.count == 2)
        #expect(records[0].price == 1234.56)
        #expect(records[1].price == 45.50)
    }

    @Test("Decode numbers with flexible strategy - currency symbols")
    func decodeNumbersFlexibleCurrency() throws {
        let csv = """
        item,price
        US,$45.00
        EU,45€
        UK,£45.00
        """

        let config = CSVDecoder.Configuration(numberDecodingStrategy: .flexible)
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([PriceRecord].self, from: csv)

        #expect(records.count == 3)
        #expect(records[0].price == 45.0)
        #expect(records[1].price == 45.0)
        #expect(records[2].price == 45.0)
    }

    @Test("Decode Decimal with flexible strategy preserves precision")
    func decodeDecimalFlexible() throws {
        let csv = """
        item,price
        Widget,"1.234,56"
        """

        struct DecimalRecord: Codable {
            let item: String
            let price: Decimal
        }

        let config = CSVDecoder.Configuration(numberDecodingStrategy: .flexible)
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([DecimalRecord].self, from: csv)

        #expect(records.count == 1)
        #expect(records[0].price == Decimal(string: "1234.56"))
    }

    // MARK: - Flexible Boolean Decoding Tests

    struct BoolRecord: Codable {
        let name: String
        let active: Bool
    }

    @Test("Decode booleans with flexible strategy - standard values")
    func decodeBoolFlexibleStandard() throws {
        let csv = """
        name,active
        A,true
        B,yes
        C,1
        D,false
        E,no
        F,0
        """

        let config = CSVDecoder.Configuration(boolDecodingStrategy: .flexible)
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([BoolRecord].self, from: csv)

        #expect(records.count == 6)
        #expect(records[0].active == true)
        #expect(records[1].active == true)
        #expect(records[2].active == true)
        #expect(records[3].active == false)
        #expect(records[4].active == false)
        #expect(records[5].active == false)
    }

    @Test("Decode booleans with flexible strategy - international values")
    func decodeBoolFlexibleInternational() throws {
        let csv = """
        name,active
        French,oui
        German,ja
        Spanish,si
        FrenchNo,non
        GermanNo,nein
        """

        let config = CSVDecoder.Configuration(boolDecodingStrategy: .flexible)
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([BoolRecord].self, from: csv)

        #expect(records.count == 5)
        #expect(records[0].active == true)
        #expect(records[1].active == true)
        #expect(records[2].active == true)
        #expect(records[3].active == false)
        #expect(records[4].active == false)
    }

    @Test("Decode booleans with custom strategy")
    func decodeBoolCustom() throws {
        let csv = """
        name,active
        A,enabled
        B,disabled
        """

        let config = CSVDecoder.Configuration(
            boolDecodingStrategy: .custom(
                trueValues: ["enabled", "on"],
                falseValues: ["disabled", "off"]
            )
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([BoolRecord].self, from: csv)

        #expect(records.count == 2)
        #expect(records[0].active == true)
        #expect(records[1].active == false)
    }
}
