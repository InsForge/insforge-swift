// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TodoApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TodoApp", targets: ["TodoApp"])
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "TodoApp",
            dependencies: [
                .product(name: "InsForge", package: "insforge-swift")
            ],
            path: "Sources"
        )
    ]
)
