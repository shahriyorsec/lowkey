// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Lowkey",
    platforms: [.macOS(.v15)],
    targets: [.executableTarget(name: "Lowkey", path: "Sources/Lowkey", swiftSettings: [.swiftLanguageMode(.v5)])]
)
