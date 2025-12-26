// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CSVCoder",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .watchOS(.v11),
        .tvOS(.v18),
        .visionOS(.v2)
    ],
    products: [
        .library(
            name: "CSVCoder",
            targets: ["CSVCoder"]
        )
    ],
    targets: [
        .target(
            name: "CSVCoder",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "CSVCoderTests",
            dependencies: ["CSVCoder"]
        )
    ]
)
