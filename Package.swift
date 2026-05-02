// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Skillbox",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Skillbox", targets: ["Skillbox"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "Skillbox",
            dependencies: ["Yams"],
            path: "Sources/Skillbox",
            exclude: ["Resources/Info.plist.template", "Resources/AppIcon.svg"]
        ),
    ]
)
