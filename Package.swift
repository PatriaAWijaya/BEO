// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BEO",
    platforms: [.macOS("14.4")],
    targets: [
        .executableTarget(name: "BEO", path: "Sources/Cicada"),
        .executableTarget(name: "BEOIcon", path: "Sources/CicadaIcon"),
        .testTarget(name: "BEOTests", dependencies: ["BEO"], path: "Tests/CicadaTests"),
    ],
    swiftLanguageModes: [.v5]
)
