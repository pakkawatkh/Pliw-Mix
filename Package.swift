// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "pliw-mix",
    platforms: [
        .macOS("14.2")
    ],
    products: [
        .executable(
            name: "pliw-mix",
            targets: ["PliwMix"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "CAtomicBridge",
            path: "Sources/CAtomicBridge",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "PliwMix",
            dependencies: ["CAtomicBridge"],
            path: "Sources/PliwMix"
        ),
        .testTarget(
            name: "PliwMixTests",
            dependencies: ["PliwMix"],
            path: "Tests/PliwMixTests"
        )
    ]
)
