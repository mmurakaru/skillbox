// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Skillbox",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Skillbox", targets: ["Skillbox"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "Skillbox",
            dependencies: [
                "Yams",
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            path: "Sources/Skillbox",
            exclude: ["Resources/Info.plist.template", "Resources/AppIcon.svg"]
        ),
        .testTarget(
            name: "SkillboxTests",
            dependencies: ["Skillbox"],
            path: "Tests/SkillboxTests"
        ),
    ]
)
