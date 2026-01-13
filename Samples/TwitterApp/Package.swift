// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TwitterClone",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TwitterClone", targets: ["TwitterClone"])
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "TwitterClone",
            dependencies: [
                .product(name: "InsForge", package: "insforge-swift")
            ],
            path: "TwitterClone"
        )
    ]
)
