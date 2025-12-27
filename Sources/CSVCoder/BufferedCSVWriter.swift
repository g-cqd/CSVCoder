//
//  BufferedCSVWriter.swift
//  CSVCoder
//
//  Buffered file writing for efficient CSV output.
//  Accumulates bytes in memory and flushes in optimal-sized chunks.
//

import Foundation

/// A buffered writer for efficient CSV file output.
/// Accumulates bytes in a buffer and writes in optimal-sized chunks.
struct BufferedCSVWriter: ~Copyable {
    private var buffer: [UInt8]
    private let handle: FileHandle
    private let bufferCapacity: Int

    /// Creates a buffered writer for the given file handle.
    /// - Parameters:
    ///   - handle: The file handle to write to.
    ///   - bufferSize: The buffer size in bytes. Default is 64KB.
    init(handle: FileHandle, bufferSize: Int = 65_536) {
        self.handle = handle
        self.bufferCapacity = bufferSize
        self.buffer = []
        self.buffer.reserveCapacity(bufferSize)
    }

    /// Writes bytes to the buffer, flushing if necessary.
    mutating func write(_ bytes: some Sequence<UInt8>) throws {
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
}

/// A row builder for efficient CSV row construction.
/// Builds rows directly into a byte buffer to avoid intermediate String allocations.
struct CSVRowBuilder: Sendable {
    private let delimiter: UInt8
    private let lineEnding: [UInt8]
    private let quote: UInt8 = 0x22

    init(delimiter: Character, lineEnding: CSVEncoder.LineEnding) {
        self.delimiter = delimiter.asciiValue ?? 0x2C
        self.lineEnding = Array(lineEnding.rawValue.utf8)
    }

    /// Builds a row from field values into the output buffer.
    func buildRow(_ fields: [String], into buffer: inout [UInt8]) {
        for (index, field) in fields.enumerated() {
            if index > 0 {
                buffer.append(delimiter)
            }
            appendField(field, to: &buffer)
        }
        buffer.append(contentsOf: lineEnding)
    }

    /// Builds a header row from field names.
    func buildHeader(_ headers: [String], into buffer: inout [UInt8]) {
        buildRow(headers, into: &buffer)
    }

    /// Appends a field value, quoting if necessary.
    private func appendField(_ value: String, to buffer: inout [UInt8]) {
        let utf8 = Array(value.utf8)

        // Check if quoting is needed
        if needsQuoting(utf8) {
            buffer.append(quote)
            for byte in utf8 {
                if byte == quote {
                    buffer.append(quote) // Escape quote by doubling
                }
                buffer.append(byte)
            }
            buffer.append(quote)
        } else {
            buffer.append(contentsOf: utf8)
        }
    }

    /// Checks if a field needs quoting.
    @inline(__always)
    private func needsQuoting(_ bytes: [UInt8]) -> Bool {
        for byte in bytes {
            if byte == delimiter || byte == quote || byte == 0x0A || byte == 0x0D {
                return true
            }
        }
        return false
    }

    /// SIMD-accelerated quoting check for larger fields.
    func needsQuotingSIMD(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 64 else {
            return needsQuoting(bytes)
        }

        return bytes.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return false }
            return SIMDScanner.needsQuoting(buffer: baseAddress, count: buffer.count, delimiter: delimiter)
        }
    }
}

// MARK: - SIMDScanner Extension for Quoting Detection

extension SIMDScanner {
    /// Checks if a field needs quoting using SIMD acceleration.
    @inline(__always)
    static func needsQuoting(
        buffer: UnsafePointer<UInt8>,
        count: Int,
        delimiter: UInt8
    ) -> Bool {
        var offset = 0

        // Process 64 bytes at a time
        while offset + 64 <= count {
            let chunk = SIMD64<UInt8>(
                buffer[offset], buffer[offset+1], buffer[offset+2], buffer[offset+3],
                buffer[offset+4], buffer[offset+5], buffer[offset+6], buffer[offset+7],
                buffer[offset+8], buffer[offset+9], buffer[offset+10], buffer[offset+11],
                buffer[offset+12], buffer[offset+13], buffer[offset+14], buffer[offset+15],
                buffer[offset+16], buffer[offset+17], buffer[offset+18], buffer[offset+19],
                buffer[offset+20], buffer[offset+21], buffer[offset+22], buffer[offset+23],
                buffer[offset+24], buffer[offset+25], buffer[offset+26], buffer[offset+27],
                buffer[offset+28], buffer[offset+29], buffer[offset+30], buffer[offset+31],
                buffer[offset+32], buffer[offset+33], buffer[offset+34], buffer[offset+35],
                buffer[offset+36], buffer[offset+37], buffer[offset+38], buffer[offset+39],
                buffer[offset+40], buffer[offset+41], buffer[offset+42], buffer[offset+43],
                buffer[offset+44], buffer[offset+45], buffer[offset+46], buffer[offset+47],
                buffer[offset+48], buffer[offset+49], buffer[offset+50], buffer[offset+51],
                buffer[offset+52], buffer[offset+53], buffer[offset+54], buffer[offset+55],
                buffer[offset+56], buffer[offset+57], buffer[offset+58], buffer[offset+59],
                buffer[offset+60], buffer[offset+61], buffer[offset+62], buffer[offset+63]
            )

            let quoteVec = SIMD64<UInt8>(repeating: 0x22)
            let delimVec = SIMD64<UInt8>(repeating: delimiter)
            let lfVec = SIMD64<UInt8>(repeating: 0x0A)
            let crVec = SIMD64<UInt8>(repeating: 0x0D)

            let quoteMask = chunk .== quoteVec
            let delimMask = chunk .== delimVec
            let lfMask = chunk .== lfVec
            let crMask = chunk .== crVec

            // Check if any structural character found
            for i in 0..<64 where quoteMask[i] || delimMask[i] || lfMask[i] || crMask[i] {
                return true
            }

            offset += 64
        }

        // Scalar fallback for remainder
        while offset < count {
            let byte = buffer[offset]
            if byte == 0x22 || byte == delimiter || byte == 0x0A || byte == 0x0D {
                return true
            }
            offset += 1
        }

        return false
    }
}
