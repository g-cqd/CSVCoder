//
//  BufferedCSVWriter.swift
//  CSVCoder
//
//  Buffered file writing for efficient CSV output.
//  Accumulates bytes in memory and flushes in optimal-sized chunks.
//

import Foundation

// MARK: - BufferedCSVWriter

/// A buffered writer for efficient CSV file output.
///
/// Accumulates bytes in a buffer and writes in optimal-sized chunks.
struct BufferedCSVWriter: ~Copyable {
    // MARK: Lifecycle

    /// Creates a buffered writer for the given file handle.
    /// - Parameters:
    ///   - handle: The file handle to write to.
    ///   - bufferSize: The buffer size in bytes. Default is 64KB.
    init(handle: FileHandle, bufferSize: Int = 65536) {
        self.handle = handle
        bufferCapacity = bufferSize
        buffer = []
        buffer.reserveCapacity(bufferSize)
    }

    // MARK: Internal

    /// Writes bytes to the buffer, flushing if necessary.
    ///
    /// Optimized for contiguous collections using batch append.
    mutating func write(_ bytes: some Sequence<UInt8>) throws {
        // Fast path for contiguous collections
        if let contiguous = bytes as? [UInt8] {
            try write(contentsOf: contiguous)
            return
        }
        if let contiguous = bytes as? ContiguousArray<UInt8> {
            try writeContiguous(contiguous)
            return
        }

        // Fallback for non-contiguous sequences
        for byte in bytes {
            buffer.append(byte)
            if buffer.count >= bufferCapacity {
                try flush()
            }
        }
    }

    /// Writes a string as UTF-8 bytes.
    mutating func write(_ string: String) throws {
        try write(string.utf8)
    }

    /// Writes a single byte.
    mutating func write(_ byte: UInt8) throws {
        buffer.append(byte)
        if buffer.count >= bufferCapacity {
            try flush()
        }
    }

    /// Writes a contiguous buffer of bytes.
    mutating func write(contentsOf bytes: [UInt8]) throws {
        // If the incoming data is larger than buffer capacity, write directly
        if bytes.count >= bufferCapacity {
            try flush()
            try handle.write(contentsOf: Data(bytes))
            return
        }

        // If adding these bytes would overflow, flush first
        if buffer.count + bytes.count > bufferCapacity {
            try flush()
        }

        buffer.append(contentsOf: bytes)
    }

    /// Flushes any buffered data to the file.
    mutating func flush() throws {
        guard !buffer.isEmpty else { return }
        try handle.write(contentsOf: Data(buffer))
        buffer.removeAll(keepingCapacity: true)
    }

    /// Closes the writer, flushing any remaining data.
    consuming func close() throws {
        try flush()
        try handle.close()
    }

    // MARK: Private

    private var buffer: [UInt8]
    private let handle: FileHandle
    private let bufferCapacity: Int

    /// Writes a contiguous collection efficiently.
    @inline(__always)
    private mutating func writeContiguous<C: RandomAccessCollection>(_ bytes: C) throws where C.Element == UInt8 {
        let count = bytes.count
        guard count > 0 else { return }

        // If incoming data is larger than buffer, write directly
        if count >= bufferCapacity {
            try flush()
            try handle.write(contentsOf: Data(bytes))
            return
        }

        // If adding would overflow, flush first
        if buffer.count + count > bufferCapacity {
            try flush()
        }

        buffer.append(contentsOf: bytes)
    }
}
