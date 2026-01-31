// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "swift-server-lint",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "swift-server-lint", targets: ["SwiftServerLint"]),
        .library(name: "SwiftServerLintCore", targets: ["SwiftServerLintCore"]),
        .library(name: "SwiftServerLintRules", targets: ["SwiftServerLintRules"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "SwiftServerLint",
            dependencies: [
                "SwiftServerLintCore",
                "SwiftServerLintRules",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
            ]
        ),
        .target(
            name: "SwiftServerLintCore",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "Yams", package: "Yams")
            ]
        ),
        .target(
            name: "SwiftServerLintRules",
            dependencies: [
                "SwiftServerLintCore",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
            ]
        ),
        .testTarget(
            name: "SwiftServerLintRulesTests",
            dependencies: [
                "SwiftServerLintRules",
                "SwiftServerLintCore",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
            ]
        )
    ]
)
