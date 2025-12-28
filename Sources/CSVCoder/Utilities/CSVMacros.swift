//
//  CSVMacros.swift
//  CSVCoder
//
//  Public macro declarations for CSVCoder.
//

/// Automatically generates `CSVIndexedDecodable` and `CSVIndexedEncodable` conformance.
///
/// This macro eliminates boilerplate by generating:
/// - `CodingKeys` enum with `CaseIterable` conformance (if not already present)
/// - `typealias CSVCodingKeys = CodingKeys`
/// - Protocol conformance extensions
///
/// ## Usage
///
/// ```swift
/// @CSVIndexed
/// struct Person: Codable {
///     let name: String
///     let age: Int
///     let email: String?
/// }
/// ```
///
/// This expands to:
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
/// extension Person: CSVIndexedDecodable {}
/// extension Person: CSVIndexedEncodable {}
/// ```
///
/// ## With Custom Column Names
///
/// Use `@CSVColumn` to map properties to different CSV column names:
///
/// ```swift
/// @CSVIndexed
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
/// Once a type conforms to `CSVIndexedDecodable`, it can be decoded from headerless CSV:
///
/// ```swift
/// let config = CSVDecoder.Configuration(hasHeaders: false)
/// let decoder = CSVDecoder(configuration: config)
/// let people = try decoder.decode([Person].self, from: csv)
/// // Column order is determined by CodingKeys case order
/// ```
@attached(member, names: named(CodingKeys), named(CSVCodingKeys))
@attached(extension, conformances: CSVIndexedDecodable, CSVIndexedEncodable)
public macro CSVIndexed() = #externalMacro(module: "CSVCoderMacros", type: "CSVIndexedMacro")

/// Specifies a custom CSV column name for a property.
///
/// Use this macro with `@CSVIndexed` to map a property to a different column name in the CSV file.
///
/// ## Usage
///
/// ```swift
/// @CSVIndexed
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
