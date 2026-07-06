// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Tokengotchi",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Tokengotchi", targets: ["Tokengotchi"])
    ],
    dependencies: [
        .package(url: "https://github.com/swhitty/FlyingFox.git", from: "0.15.0")
    ],
    targets: [
        .executableTarget(
            name: "Tokengotchi",
            dependencies: [
                .product(name: "FlyingFox", package: "FlyingFox")
            ],
            path: "Sources/Tokengotchi",
            exclude: ["Resources/Info.plist"],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=minimal"])
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SpriteKit"),
                .linkedFramework("SwiftUI")
            ]
        )
    ]
)
