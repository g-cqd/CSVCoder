//
//  TestModels.swift
//  CSVCoderTestFixtures
//
//  Shared test models used by both benchmarks and tests.
//

import Foundation

// MARK: - Order

/// Real-world model: E-commerce order
public struct Order: Codable, Sendable, Equatable {
    public let orderId: String
    public let customerId: Int
    public let customerName: String
    public let email: String
    public let productId: Int
    public let productName: String
    public let quantity: Int
    public let unitPrice: Double
    public let discount: Double?
    public let taxRate: Double
    public let shippingCost: Double
    public let totalAmount: Double
    public let currency: String
    public let paymentMethod: String
    public let orderDate: String
    public let shipDate: String?
    public let status: String
    public let notes: String?

    public init(
        orderId: String,
        customerId: Int,
        customerName: String,
        email: String,
        productId: Int,
        productName: String,
        quantity: Int,
        unitPrice: Double,
        discount: Double?,
        taxRate: Double,
        shippingCost: Double,
        totalAmount: Double,
        currency: String,
        paymentMethod: String,
        orderDate: String,
        shipDate: String?,
        status: String,
        notes: String?
    ) {
        self.orderId = orderId
        self.customerId = customerId
        self.customerName = customerName
        self.email = email
        self.productId = productId
        self.productName = productName
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.discount = discount
        self.taxRate = taxRate
        self.shippingCost = shippingCost
        self.totalAmount = totalAmount
        self.currency = currency
        self.paymentMethod = paymentMethod
        self.orderDate = orderDate
        self.shipDate = shipDate
        self.status = status
        self.notes = notes
    }
}

// MARK: - Transaction

/// Real-world model: Financial transaction
public struct Transaction: Codable, Sendable, Equatable {
    public let transactionId: String
    public let accountFrom: String
    public let accountTo: String
    public let amount: Double
    public let currency: String
    public let exchangeRate: Double?
    public let fee: Double
    public let timestamp: String
    public let category: String
    public let description: String
    public let reference: String?
    public let status: String
    public let processedBy: String?

    public init(
        transactionId: String,
        accountFrom: String,
        accountTo: String,
        amount: Double,
        currency: String,
        exchangeRate: Double?,
        fee: Double,
        timestamp: String,
        category: String,
        description: String,
        reference: String?,
        status: String,
        processedBy: String?
    ) {
        self.transactionId = transactionId
        self.accountFrom = accountFrom
        self.accountTo = accountTo
        self.amount = amount
        self.currency = currency
        self.exchangeRate = exchangeRate
        self.fee = fee
        self.timestamp = timestamp
        self.category = category
        self.description = description
        self.reference = reference
        self.status = status
        self.processedBy = processedBy
    }
}

// MARK: - LogEntry

/// Real-world model: Server log entry
public struct LogEntry: Codable, Sendable, Equatable {
    public let timestamp: String
    public let level: String
    public let service: String
    public let host: String
    public let requestId: String?
    public let userId: String?
    public let action: String
    public let resource: String
    public let duration: Int?
    public let statusCode: Int?
    public let message: String
    public let metadata: String?

    public init(
        timestamp: String,
        level: String,
        service: String,
        host: String,
        requestId: String?,
        userId: String?,
        action: String,
        resource: String,
        duration: Int?,
        statusCode: Int?,
        message: String,
        metadata: String?
    ) {
        self.timestamp = timestamp
        self.level = level
        self.service = service
        self.host = host
        self.requestId = requestId
        self.userId = userId
        self.action = action
        self.resource = resource
        self.duration = duration
        self.statusCode = statusCode
        self.message = message
        self.metadata = metadata
    }
}
