// swift-tools-version:5.9
import PackageDescription

// Dieses Paket enthält nur die Kern-Pipeline (ohne UI), damit sie mit `swift test` auf dem Mac
// getestet werden kann. Die Apps (iOS + macOS) binden dieselben Quelldateien direkt ein
// (siehe project.yml).
let package = Package(
    name: "AnamorphicCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "AnamorphicCore", targets: ["AnamorphicCore"])],
    targets: [
        .target(name: "AnamorphicCore", path: "Sources/Core"),
        .testTarget(name: "AnamorphicCoreTests", dependencies: ["AnamorphicCore"], path: "Tests/AnamorphicCoreTests"),
    ]
)
