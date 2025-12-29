//
//  AsyncCSVWriter.swift
//  CSVCoder
//
//  Actor-isolated async file writer with buffered output.
//

import Foundation

/// Actor-isolated async CSV file writer with buffered output.
actor AsyncCSVWriter {
    // MARK: Lifecycle

    /// Creates an async writer for the given file URL.
    /// - Parameters:
    ///   - url: The file URL to write to.
    ///   - bufferCapacity: Size of internal buffer in bytes (default 64KB).
    init(url: URL, bufferCapacity: Int = 65536) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
        buffer = []
        buffer.reserveCapacity(bufferCapacity)
        self.bufferCapacity = bufferCapacity
    }

    deinit {
        try? handle.close()
    }

    // MARK: Internal

    /// Total bytes written to file (including buffered).
    var totalBytesWritten: Int { _totalBytesWritten }

    /// Writes a complete row to the buffer.
    func writeRow(_ bytes: [UInt8]) async throws {
        _totalBytesWritten += bytes.count
        buffer.append(contentsOf: bytes)
        if buffer.count >= bufferCapacity {
            try await flush()
        }
    }

    /// Writes bytes to the buffer, flushing if capacity is reached.
    func write(_ bytes: some Sequence<UInt8>) async throws {
        for byte in bytes {
            buffer.append(byte)
            _totalBytesWritten += 1
            if buffer.count >= bufferCapacity {
                try await flush()
            }
        }
    }

    /// Writes a string as UTF-8 bytes.
    func write(_ string: String) async throws {
        try await write(string.utf8)
    }

    /// Flushes the buffer to disk.
    func flush() async throws {
        guard !buffer.isEmpty else { return }
        let data = Data(buffer)
        try handle.write(contentsOf: data)
        buffer.removeAll(keepingCapacity: true)
    }

    /// Finishes writing and closes the file.
    func close() async throws {
        try await flush()
        try handle.close()
    }

    // MARK: Private

    private let handle: FileHandle
    private var buffer: [UInt8]
    private let bufferCapacity: Int
    private var _totalBytesWritten: Int = 0
}
