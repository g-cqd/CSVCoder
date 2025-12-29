//
//  FieldBufferPool.swift
//  CSVCoder
//
//  Thread-safe reusable buffer pool for byte arrays.
//

import Foundation

// MARK: - Field Buffer Pool

/// Thread-safe pool of reusable byte buffers for field decoding.
final class FieldBufferPool: @unchecked Sendable {
    // MARK: Lifecycle

    /// Creates a buffer pool.
    /// - Parameter maxPoolSize: Maximum number of buffers to retain (default 16).
    init(maxPoolSize: Int = 16) {
        self.maxPoolSize = maxPoolSize
    }

    // MARK: Internal

    /// Leases a buffer with at least the specified capacity.
    /// - Parameter capacity: Minimum buffer capacity.
    /// - Returns: A buffer (may be reused or newly allocated).
    func lease(capacity: Int) -> [UInt8] {
        lock.lock()
        defer { lock.unlock() }

        // Find suitable buffer
        if let index = buffers.firstIndex(where: { $0.capacity >= capacity }) {
            return buffers.remove(at: index)
        }

        // No suitable buffer, create new one
        var buffer: [UInt8] = []
        buffer.reserveCapacity(max(capacity, 256))
        return buffer
    }

    /// Returns a buffer to the pool for reuse.
    /// - Parameter buffer: The buffer to return.
    func `return`(_ buffer: inout [UInt8]) {
        lock.lock()
        defer { lock.unlock() }

        if buffers.count < maxPoolSize {
            buffer.removeAll(keepingCapacity: true)
            buffers.append(buffer)
        }
        // If pool is full, buffer is deallocated
    }

    /// Clears all pooled buffers.
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        buffers.removeAll()
    }

    // MARK: Private

    private var buffers: [[UInt8]] = []
    private let lock = NSLock()
    private let maxPoolSize: Int
}
