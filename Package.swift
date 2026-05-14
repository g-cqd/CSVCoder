// swift-tools-version: 6.2

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "CSVCoder",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .watchOS(.v11),
        .tvOS(.v18),
        .visionOS(.v2),
    ],
    products: [
        .library(
            name: "CSVCoder",
            targets: ["CSVCoder"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.3"),
        .package(url: "https://github.com/google/swift-benchmark", from: "0.1.2"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.1" ..< "700.0.0"),
    ],
    targets: [
        // Main library
        .target(
            name: "CSVCoder",
            dependencies: ["CSVCoderMacros"]
        ),

        // Macro implementation (compiler plugin)
        .macro(
            name: "CSVCoderMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
            ]
        ),

        // Shared test fixtures
        .target(
            name: "CSVCoderTestFixtures",
            dependencies: []
        ),

        // Tests
        .testTarget(
            name: "CSVCoderTests",
            dependencies: ["CSVCoder", "CSVCoderTestFixtures"]
        ),
        .testTarget(
            name: "CSVCoderMacrosTests",
            dependencies: [
                "CSVCoderMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),

        // Benchmarks
        .executableTarget(
            name: "CSVCoderBenchmarks",
            dependencies: [
                "CSVCoder",
                "CSVCoderTestFixtures",
                .product(name: "Benchmark", package: "swift-benchmark"),
            ]
        ),
    ]
)
