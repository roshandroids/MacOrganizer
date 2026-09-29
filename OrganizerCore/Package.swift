// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OrganizerCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OrganizerCore", targets: ["OrganizerCore"]),
    ],
    targets: [
        .target(
            name: "OrganizerCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "OrganizerCoreTests",
            dependencies: ["OrganizerCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
