import Foundation

/// System hardware and environment information for benchmark context
struct HardwareInfo: Sendable {
    static let current: HardwareInfo = {
        let processInfo = ProcessInfo.processInfo

        // CPU Model
        var cpuModel = "Unknown"
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        if size > 0 {
            var buffer = [UInt8](repeating: 0, count: size)
            sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
            if let nullIndex = buffer.firstIndex(of: 0) {
                cpuModel = String(decoding: buffer[..<nullIndex], as: UTF8.self)
            } else {
                cpuModel = String(decoding: buffer, as: UTF8.self)
            }
        }

        // Performance cores
        var perfCores: Int32 = 0
        var perfCoresSize = MemoryLayout<Int32>.size
        sysctlbyname("hw.perflevel0.physicalcpu", &perfCores, &perfCoresSize, nil, 0)

        // Efficiency cores
        var effCores: Int32 = 0
        var effCoresSize = MemoryLayout<Int32>.size
        sysctlbyname("hw.perflevel1.physicalcpu", &effCores, &effCoresSize, nil, 0)

        // Swift version from compiler
        #if swift(>=6.2)
            let swiftVer = "6.2+"
        #elseif swift(>=6.1)
            let swiftVer = "6.1"
        #elseif swift(>=6.0)
            let swiftVer = "6.0"
        #else
            let swiftVer = "5.x"
        #endif

        // Build configuration
        #if DEBUG
            let buildConfig = "Debug"
        #else
            let buildConfig = "Release"
        #endif

        return HardwareInfo(
            cpuModel: cpuModel.trimmingCharacters(in: .whitespaces),
            cpuCores: processInfo.activeProcessorCount,
            cpuPerformanceCores: Int(perfCores),
            cpuEfficiencyCores: Int(effCores),
            physicalMemoryGB: Double(processInfo.physicalMemory) / 1_073_741_824,
            osVersion: processInfo.operatingSystemVersionString,
            swiftVersion: swiftVer,
            buildConfiguration: buildConfig,
        )
    }()

    let cpuModel: String
    let cpuCores: Int
    let cpuPerformanceCores: Int
    let cpuEfficiencyCores: Int
    let physicalMemoryGB: Double
    let osVersion: String
    let swiftVersion: String
    let buildConfiguration: String

    func printHeader() {
        let separator = String(repeating: "═", count: 72)
        print(separator)
        print("                    CSVCoder Benchmark Suite")
        print(separator)
        print()
        print("Hardware:")
        print("  CPU:      \(cpuModel)")
        if cpuPerformanceCores > 0 || cpuEfficiencyCores > 0 {
            print("  Cores:    \(cpuCores) total (\(cpuPerformanceCores)P + \(cpuEfficiencyCores)E)")
        } else {
            print("  Cores:    \(cpuCores)")
        }
        print("  Memory:   \(String(format: "%.0f", physicalMemoryGB)) GB")
        print()
        print("Software:")
        print("  OS:       \(osVersion)")
        print("  Swift:    \(swiftVersion)")
        print("  Build:    \(buildConfiguration)")
        print()
        print(separator)
        print()
    }

    func markdownSummary() -> String {
        var lines: [String] = []
        lines.append("**Benchmark Environment:**")
        lines.append("- CPU: \(cpuModel)")
        if cpuPerformanceCores > 0 || cpuEfficiencyCores > 0 {
            lines.append("- Cores: \(cpuCores) (\(cpuPerformanceCores) performance + \(cpuEfficiencyCores) efficiency)")
        } else {
            lines.append("- Cores: \(cpuCores)")
        }
        lines.append("- Memory: \(String(format: "%.0f", physicalMemoryGB)) GB")
        lines.append("- OS: \(osVersion)")
        lines.append("- Swift: \(swiftVersion)")
        lines.append("- Build: \(buildConfiguration)")
        return lines.joined(separator: "\n")
    }

    func jsonSummary() -> String {
        """
        {
          "cpu_model": "\(cpuModel)",
          "cpu_cores": \(cpuCores),
          "cpu_performance_cores": \(cpuPerformanceCores),
          "cpu_efficiency_cores": \(cpuEfficiencyCores),
          "memory_gb": \(String(format: "%.1f", physicalMemoryGB)),
          "os_version": "\(osVersion)",
          "swift_version": "\(swiftVersion)",
          "build_configuration": "\(buildConfiguration)"
        }
        """
    }
}
