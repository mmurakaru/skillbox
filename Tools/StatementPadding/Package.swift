// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StatementPadding",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "statement-padding", targets: ["statement-padding"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "604.0.0")
    ],
    targets: [
        .target(
            name: "StatementPaddingRules",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        ),
        .executableTarget(name: "statement-padding", dependencies: ["StatementPaddingRules"]),
        .testTarget(name: "StatementPaddingRulesTests", dependencies: ["StatementPaddingRules"]),
    ]
)
