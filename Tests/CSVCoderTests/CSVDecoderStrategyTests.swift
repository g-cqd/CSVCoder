//
//  CSVDecoderStrategyTests.swift
//  CSVCoder
//
//  Tests for date, number, and boolean decoding strategies.
//

import Foundation
import Testing

@testable import CSVCoder

@Suite("CSVDecoder Strategy Tests")
struct CSVDecoderStrategyTests {
    // MARK: - Flexible Date Decoding Tests

    struct DateRecord: Codable {
        let event: String
        let date: Date
    }

    // MARK: - Flexible Number Decoding Tests

    struct PriceRecord: Codable, Equatable {
        let item: String
        let price: Double
    }

    // MARK: - Flexible Boolean Decoding Tests

    struct BoolRecord: Codable {
        let name: String
        let active: Bool
    }

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
            dateDecodingStrategy: .flexibleWithHint(preferred: "dd-MMM-yyyy"),
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([DateRecord].self, from: csv)

        #expect(records.count == 1)
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
                falseValues: ["disabled", "off"],
            ),
        )
        let decoder = CSVDecoder(configuration: config)
        let records = try decoder.decode([BoolRecord].self, from: csv)

        #expect(records.count == 2)
        #expect(records[0].active == true)
        #expect(records[1].active == false)
    }
}
