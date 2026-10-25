// swift-tools-version: 5.10
import PackageDescription

// Lógica pura do Gravador (sem Core Audio/AppKit), testável com `swift test`.
let package = Package(
    name: "GravadorCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GravadorCore", targets: ["GravadorCore"]),
    ],
    targets: [
        .target(name: "GravadorCore"),
        .testTarget(name: "GravadorCoreTests", dependencies: ["GravadorCore"]),
    ]
)
