//
//  CSVMacros.swift
//  CSVCoder
//
//  Public macro declarations for CSVCoder.
//

/// Declares that a struct represents a single CSV row, generating the
/// boilerplate needed for headerless decoding and ordered encoding.
///
/// The macro expands to:
/// - `CodingKeys` enum with `CaseIterable` conformance (if not already
///   present, so the column order is enumerable)
/// - `typealias CSVCodingKeys = CodingKeys` (the bridge protocol's
///   associated type)
/// - Conformance to ``CSVRowDecodable`` and ``CSVRowEncodable`` via
///   extensions
///
/// ## Usage
///
/// ```swift
/// @CSVRow
/// struct Person: Codable {
///     let name: String
///     let age: Int
///     let email: String?
/// }
/// ```
///
/// expands to:
///
/// ```swift
/// struct Person: Codable {
///     let name: String
///     let age: Int
///     let email: String?
///
///     enum CodingKeys: String, CodingKey, CaseIterable {
///         case name
///         case age
///         case email
///     }
///     typealias CSVCodingKeys = CodingKeys
/// }
///
/// extension Person: CSVRowDecodable {}
/// extension Person: CSVRowEncodable {}
/// ```
///
/// ## With Custom Column Names
///
/// Use ``CSVColumn(_:)`` to map a property to a different CSV column name:
///
/// ```swift
/// @CSVRow
/// struct Product: Codable {
///     let id: Int
///
///     @CSVColumn("product_name")
///     let name: String
///
///     @CSVColumn("unit_price")
///     let price: Double
/// }
/// ```
///
/// ## Headerless CSV Decoding
///
/// Once a type carries `@CSVRow`, it can be decoded from headerless CSV:
///
/// ```swift
/// let config = CSVDecoder.Configuration(hasHeaders: false)
/// let decoder = CSVDecoder(configuration: config)
/// let people = try decoder.decode([Person].self, from: csv)
/// // Column order is determined by the property declaration order.
/// ```
@attached(member, names: named(CodingKeys), named(CSVCodingKeys))
@attached(
    extension,
    conformances: CSVRowDecodable,
    CSVRowEncodable,
    CSVDirectDecodable,
    names: named(init(csvRow:columnIndices:configuration:rowIndex:))
)
public macro CSVRow() = #externalMacro(module: "CSVCoderMacros", type: "CSVRowMacro")

/// Specifies a custom CSV column name for a property.
///
/// Use this macro with ``CSVRow()`` to map a property to a different column
/// name in the CSV file.
///
/// ## Usage
///
/// ```swift
/// @CSVRow
/// struct Transaction: Codable {
///     let id: UUID
///
///     @CSVColumn("transaction_date")
///     let date: Date
///
///     @CSVColumn("amount_usd")
///     let amount: Decimal
/// }
/// ```
///
/// The generated `CodingKeys` will include custom raw values:
///
/// ```swift
/// enum CodingKeys: String, CodingKey, CaseIterable {
///     case id
///     case date = "transaction_date"
///     case amount = "amount_usd"
/// }
/// ```
///
/// - Parameter name: The CSV column name to use for this property.
@attached(peer)
public macro CSVColumn(_ name: String) = #externalMacro(module: "CSVCoderMacros", type: "CSVColumnMacro")
