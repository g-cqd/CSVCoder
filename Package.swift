// swift-tools-version: 6.3

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
        .package(url: "https://github.com/Aemi-Studio/aemi.git", revision: "bd5e4cf4441ca3ed1b424935142586ccaac0f835"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.5.0"),
        .package(url: "https://github.com/google/swift-benchmark", from: "0.1.2"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.1"..<"700.0.0"),
    ],
    targets: [
        .target(
            name: "CSVCoder",
            dependencies: [
                "CSVCoderMacros",
                .product(name: "AemiKernel", package: "aemi"),
                .product(name: "AemiKernels", package: "aemi"),
            ]
        ),

        .macro(
            name: "CSVCoderMacros",
            dependencies: [
                .product(name: "AemiMacroSupport", package: "aemi"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
            ]
        ),

        .target(
            name: "CSVCoderTestFixtures",
            dependencies: []
        ),

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
