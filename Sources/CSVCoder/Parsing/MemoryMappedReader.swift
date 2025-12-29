//
//  MemoryMappedReader.swift
//  CSVCoder
//
//  Memory-mapped file reader for efficient large file access.
//  Provides O(1) memory usage regardless of file size.
//

import Foundation

/// Memory-mapped file reader for efficient large file processing.
/// Uses `mmap` under the hood to avoid loading entire file into RAM.
final class MemoryMappedReader: Sendable {
    // MARK: Lifecycle

    /// Initialize with a file URL using memory-mapped I/O.
    /// - Parameter url: File URL to read.
    /// - Throws: Error if file cannot be opened or mapped.
    init(url: URL) throws {
        data = try Data(contentsOf: url, options: .mappedIfSafe)
        _count = data.count
    }

    /// Initialize with existing Data (for in-memory sources).
    /// - Parameter data: Data to wrap.
    init(data: Data) {
        self.data = data
        _count = data.count
    }

    // MARK: Internal

    /// Total byte count of the file.
    var count: Int { _count }

    /// Access a byte at a specific index.
    /// - Parameter index: Byte offset.
    /// - Returns: The byte value at that index.
    subscript(index: Int) -> UInt8 {
        data[index]
    }

    /// Access a range of bytes.
    /// - Parameter range: Range of byte offsets.
    /// - Returns: Data slice for the range.
    subscript(range: Range<Int>) -> Data.SubSequence {
        data[range]
    }

    /// Get raw buffer pointer for high-performance access.
    /// - Parameter body: Closure receiving the buffer pointer.
    /// - Returns: Result of the closure.
    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try data.withUnsafeBytes(body)
    }

    // MARK: Private

    private let data: Data
    private let _count: Int
}
