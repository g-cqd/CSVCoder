//
//  PulledRowSource.swift
//  CSVCoder
//
//  Decodes rows only when the consumer asks for them.
//

import Foundation
import Synchronization

/// Decodes rows from a CSV file one pull at a time, for `AsyncThrowingStream(unfolding:)`.
///
/// A pull runs the parser inline on the caller's task, so the source never reads ahead of its
/// consumer: memory is bounded by one row (or one batch), a slow consumer cannot lose rows, and an
/// abandoned stream leaves no task decoding in the background.
///
/// Thread safety: all state sits behind one lock. The stream calls ``next()`` serially, so the
/// lock is never contended in practice.
final class PulledRowSource<T: Decodable & Sendable>: Sendable {
    // MARK: Lifecycle

    init(url: URL, configuration: CSVDecoder.Configuration) {
        self.configuration = configuration
        state = Mutex(State(url: url, processor: StreamingRowProcessor<T>(configuration: configuration)))
    }

    // MARK: Internal

    /// Decodes the next value.
    ///
    /// - Returns: The next value, or `nil` at end of input and after any earlier error.
    /// - Throws: The file-open error on the first call, or the parse or decode error of the row
    ///   that failed. Rows before it have already been returned.
    /// - Complexity: O(row size) per call.
    func next() throws -> T? {
        try state.withLock { try $0.next(configuration: configuration) }
    }

    /// Decodes up to `limit` values.
    ///
    /// - Parameter limit: The most values to return; at least 1.
    /// - Returns: A non-empty batch, or `nil` at end of input.
    /// - Throws: As ``next()``. When an error follows rows already decoded for this batch, those
    ///   rows are returned first and the error is thrown by the next call.
    func nextBatch(limit: Int) throws -> [T]? {
        try state.withLock { state in
            var batch: [T] = []
            batch.reserveCapacity(limit)
            do {
                while batch.count < limit, let value = try state.next(configuration: configuration) {
                    batch.append(value)
                }
            } catch {
                guard !batch.isEmpty else { throw error }
                state.deferredError = error
            }
            return batch.isEmpty ? nil : batch
        }
    }

    // MARK: Private

    private struct State {
        var url: URL?
        var producer: CSVRowStreamProducer?
        var processor: StreamingRowProcessor<T>
        var finished = false
        var deferredError: (any Error)?

        mutating func next(configuration: CSVDecoder.Configuration) throws -> T? {
            if let error = deferredError {
                deferredError = nil
                throw error
            }
            guard !finished else { return nil }
            do {
                if producer == nil, let url {
                    producer = try CSVRowStreamProducer(url: url, configuration: configuration)
                    self.url = nil
                }
                while let row = try producer?.nextRow() {
                    if let value = try processor.process(row) { return value }
                }
                finished = true
                return nil
            } catch {
                finished = true
                throw error
            }
        }
    }

    private let configuration: CSVDecoder.Configuration
    private let state: Mutex<State>
}
