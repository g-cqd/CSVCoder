import CSVCoder
import Foundation

// NYC Taxi Trip Record - DuckDB benchmark dataset (headerless CSV)
// Schema: id, vendor, pickup_datetime, dropoff_datetime, store_and_fwd_flag,
//         passenger_count, pickup_longitude, pickup_latitude, dropoff_longitude, dropoff_latitude,
//         rate_code_id, trip_distance, fare_amount, extra, mta_tax, tip_amount, tolls_amount,
//         ehail_fee, improvement_surcharge, total_amount, payment_type, ...
struct TaxiTrip: Codable, Sendable {
    let id: Int
    let vendor: String
    let pickupDatetime: String
    let dropoffDatetime: String
    let storeAndFwdFlag: Int?
    let passengerCount: Int?
    let pickupLongitude: Double?
    let pickupLatitude: Double?
    let dropoffLongitude: Double?
    let dropoffLatitude: Double?
    let rateCodeId: Int?
    let tripDistance: Double?
    let fareAmount: Double?
    let extra: Double?
    let mtaTax: Double?
    let tipAmount: Double?
    let tollsAmount: Double?
    let ehailFee: Double?
    let improvementSurcharge: Double?
    let totalAmount: Double?
}

@main
struct LargeFileBenchmark {
    // DuckDB's NYC Taxi dataset - each file is ~1.8GB compressed, ~8GB uncompressed, 20M rows
    static let datasetURL = URL(string: "https://blobs.duckdb.org/data/nyc-taxi-dataset/trips_xaa.csv.gz")!

    static func main() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let gzipPath = tempDir.appendingPathComponent("trips_xaa.csv.gz")
        let csvPath = tempDir.appendingPathComponent("trips_xaa.csv")

        // Check if we already have the CSV
        if !FileManager.default.fileExists(atPath: csvPath.path) {
            // Download if needed
            if !FileManager.default.fileExists(atPath: gzipPath.path) {
                print("Downloading NYC Taxi dataset (~1.8GB compressed)...")
                print("Source: \(datasetURL)")
                let startDownload = Date()
                try await downloadFile(from: datasetURL, to: gzipPath)
                let downloadTime = Date().timeIntervalSince(startDownload)
                let gzipSize = try FileManager.default.attributesOfItem(atPath: gzipPath.path)[.size] as! Int64
                print("Downloaded \(gzipSize / 1_000_000) MB in \(String(format: "%.1f", downloadTime))s")
            }

            // Decompress
            print("Decompressing...")
            let startDecompress = Date()
            try decompressGzip(from: gzipPath, to: csvPath)
            let decompressTime = Date().timeIntervalSince(startDecompress)
            print("Decompressed in \(String(format: "%.1f", decompressTime))s")
        }

        let fileSize = try FileManager.default.attributesOfItem(atPath: csvPath.path)[.size] as! Int64
        print()
        print("=== NYC Taxi Dataset Benchmark ===")
        print("File: \(csvPath.lastPathComponent)")
        print("Size: \(fileSize / 1_000_000_000) GB (\(fileSize / 1_000_000) MB)")
        print()

        // Count rows for reference
        print("Counting rows...")
        let rowCount = try countRows(in: csvPath)
        print("Total rows: \(formatNumber(rowCount))")
        print()

        // Configure decoder for headerless CSV with index mapping
        let config = CSVDecoder.Configuration(
            hasHeaders: false,
            indexMapping: [
                0: "id",
                1: "vendor",
                2: "pickupDatetime",
                3: "dropoffDatetime",
                4: "storeAndFwdFlag",
                5: "passengerCount",
                6: "pickupLongitude",
                7: "pickupLatitude",
                8: "dropoffLongitude",
                9: "dropoffLatitude",
                10: "rateCodeId",
                11: "tripDistance",
                12: "fareAmount",
                13: "extra",
                14: "mtaTax",
                15: "tipAmount",
                16: "tollsAmount",
                17: "ehailFee",
                18: "improvementSurcharge",
                19: "totalAmount"
            ]
        )
        let decoder = CSVDecoder(configuration: config)

        // Benchmark 1: Streaming decode
        print("=== Streaming Decode ===")
        var streamCount = 0
        let streamStart = Date()
        for try await _ in decoder.decode(TaxiTrip.self, from: csvPath) {
            streamCount += 1
            if streamCount % 5_000_000 == 0 {
                let elapsed = Date().timeIntervalSince(streamStart)
                let rate = Double(streamCount) / elapsed
                print("  \(formatNumber(streamCount)) rows (\(String(format: "%.0f", rate)) rows/s)...")
            }
        }
        let streamTime = Date().timeIntervalSince(streamStart)
        let streamMBps = Double(fileSize) / streamTime / 1_000_000
        let streamRowsPerSec = Double(streamCount) / streamTime
        print("Result: \(formatNumber(streamCount)) rows in \(String(format: "%.2f", streamTime))s")
        print("Throughput: \(String(format: "%.1f", streamMBps)) MB/s, \(formatNumber(Int(streamRowsPerSec))) rows/s")
        print()

        // Benchmark 2: Parallel decode
        print("=== Parallel Decode ===")
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let parallelConfig = CSVDecoder.ParallelConfiguration(
            parallelism: cores,
            chunkSize: 50_000_000,  // 50 MB chunks
            preserveOrder: false
        )

        let parallelStart = Date()
        let parallelResults = try await decoder.decodeParallel(
            [TaxiTrip].self,
            from: csvPath,
            parallelConfig: parallelConfig
        )
        let parallelTime = Date().timeIntervalSince(parallelStart)
        let parallelMBps = Double(fileSize) / parallelTime / 1_000_000
        let parallelRowsPerSec = Double(parallelResults.count) / parallelTime
        print("Result: \(formatNumber(parallelResults.count)) rows in \(String(format: "%.2f", parallelTime))s")
        print("Throughput: \(String(format: "%.1f", parallelMBps)) MB/s, \(formatNumber(Int(parallelRowsPerSec))) rows/s")
        print("Speedup vs streaming: \(String(format: "%.2f", streamTime / parallelTime))x (\(cores) cores)")
        print()

        // Benchmark 3: Parallel batched streaming
        print("=== Parallel Batched Streaming ===")
        var batchedCount = 0
        var batchCount = 0
        let batchedStart = Date()
        for try await batch in decoder.decodeParallelBatched(
            TaxiTrip.self,
            from: csvPath,
            parallelConfig: parallelConfig
        ) {
            batchedCount += batch.count
            batchCount += 1
        }
        let batchedTime = Date().timeIntervalSince(batchedStart)
        let batchedMBps = Double(fileSize) / batchedTime / 1_000_000
        print("Result: \(formatNumber(batchedCount)) rows in \(batchCount) batches")
        print("Time: \(String(format: "%.2f", batchedTime))s")
        print("Throughput: \(String(format: "%.1f", batchedMBps)) MB/s")
        print()

        // Summary
        print("=== Summary ===")
        print("┌─────────────────────────┬────────────┬─────────────┬─────────────┐")
        print("│ Method                  │ Time       │ MB/s        │ Rows/s      │")
        print("├─────────────────────────┼────────────┼─────────────┼─────────────┤")
        print(String(format: "│ Streaming               │ %7.2fs   │ %8.1f    │ %10s  │",
                     streamTime, streamMBps, formatNumber(Int(streamRowsPerSec))))
        print(String(format: "│ Parallel (%2d cores)     │ %7.2fs   │ %8.1f    │ %10s  │",
                     cores, parallelTime, parallelMBps, formatNumber(Int(parallelRowsPerSec))))
        print(String(format: "│ Parallel Batched        │ %7.2fs   │ %8.1f    │             │",
                     batchedTime, batchedMBps))
        print("└─────────────────────────┴────────────┴─────────────┴─────────────┘")
        print()

        // Cleanup prompt
        print("CSV file kept at: \(csvPath.path)")
        print("Delete with: rm \"\(csvPath.path)\" \"\(gzipPath.path)\"")
    }

    static func downloadFile(from url: URL, to destination: URL) async throws {
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "Download", code: 1, userInfo: [NSLocalizedDescriptionKey: "Download failed"])
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
    }

    static func decompressGzip(from source: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
        process.arguments = ["-k", "-c", source.path]

        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let outputFile = try FileHandle(forWritingTo: destination)

        process.standardOutput = outputFile
        try process.run()
        process.waitUntilExit()
        try outputFile.close()
    }

    static func countRows(in url: URL) throws -> Int {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        var count = 0
        data.withUnsafeBytes { buffer in
            let bytes = buffer.bindMemory(to: UInt8.self)
            for byte in bytes {
                if byte == 0x0A { count += 1 }
            }
        }
        return count - 1  // Subtract header
    }

    static func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
