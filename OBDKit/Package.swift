// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OBDKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OBDKit", targets: ["OBDKit"]),
        .executable(name: "obdcli", targets: ["obdcli"]),
    ],
    targets: [
        .target(name: "OBDKit", swiftSettings: [.swiftLanguageMode(.v6)]),
        .executableTarget(name: "obdcli", dependencies: ["OBDKit"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "OBDKitTests", dependencies: ["OBDKit"], swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)
