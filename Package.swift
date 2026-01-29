// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "InsForge",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .tvOS(.v13),
        .watchOS(.v6),
        .visionOS(.v1)
    ],
    products: [
        // Main product that includes all modules
        .library(
            name: "InsForge",
            targets: ["InsForge"]
        ),
        // Individual module products for granular imports
        .library(
            name: "InsForgeAuth",
            targets: ["InsForgeAuth"]
        ),
        .library(
            name: "InsForgeDatabase",
            targets: ["InsForgeDatabase"]
        ),
        .library(
            name: "InsForgeStorage",
            targets: ["InsForgeStorage"]
        ),
        .library(
            name: "InsForgeFunctions",
            targets: ["InsForgeFunctions"]
        ),
        .library(
            name: "InsForgeAI",
            targets: ["InsForgeAI"]
        ),
        .library(
            name: "InsForgeRealtime",
            targets: ["InsForgeRealtime"]
        ),
    ],
    dependencies: [
        // Socket.IO client for Realtime
        .package(url: "https://github.com/socketio/socket.io-client-swift.git", from: "16.0.0"),
        // Swift DocC Plugin for documentation generation
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"),
        // SwiftLog for structured logging
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        // Core helpers and utilities
        .target(
            name: "InsForgeCore",
            dependencies: [
                .product(name: "Logging", package: "swift-log")
            ],
            path: "Sources/Core"
        ),

        // Authentication module
        .target(
            name: "InsForgeAuth",
            dependencies: ["InsForgeCore"],
            path: "Sources/Auth"
        ),

        // Database module (PostgREST-style)
        .target(
            name: "InsForgeDatabase",
            dependencies: ["InsForgeCore"],
            path: "Sources/Database"
        ),

        // Storage module (S3-style)
        .target(
            name: "InsForgeStorage",
            dependencies: ["InsForgeCore"],
            path: "Sources/Storage"
        ),

        // Functions module (serverless)
        .target(
            name: "InsForgeFunctions",
            dependencies: ["InsForgeCore"],
            path: "Sources/Functions"
        ),

        // AI module (chat and image generation)
        .target(
            name: "InsForgeAI",
            dependencies: ["InsForgeCore"],
            path: "Sources/AI"
        ),

        // Realtime module (pub/sub)
        .target(
            name: "InsForgeRealtime",
            dependencies: [
                "InsForgeCore",
                "InsForgeAuth",
                .product(name: "SocketIO", package: "socket.io-client-swift")
            ],
            path: "Sources/Realtime"
        ),

        // Main facade client
        .target(
            name: "InsForge",
            dependencies: [
                "InsForgeCore",
                "InsForgeAuth",
                "InsForgeDatabase",
                "InsForgeStorage",
                "InsForgeFunctions",
                "InsForgeAI",
                "InsForgeRealtime"
            ],
            path: "Sources/InsForge"
        ),

        // Test helper target (shared test utilities)
        .target(
            name: "TestHelper",
            dependencies: ["InsForge"],
            path: "Tests/TestHelper"
        ),

        // Test targets
        .testTarget(
            name: "InsForgeTests",
            dependencies: ["InsForge", "TestHelper"],
            path: "Tests/InsForgeTests"
        ),
        .testTarget(
            name: "InsForgeAuthTests",
            dependencies: ["InsForge", "InsForgeAuth", "TestHelper"],
            path: "Tests/InsForgeAuthTests"
        ),
        .testTarget(
            name: "InsForgeDatabaseTests",
            dependencies: ["InsForge", "InsForgeDatabase", "TestHelper"],
            path: "Tests/InsForgeDatabaseTests"
        ),
        .testTarget(
            name: "InsForgeStorageTests",
            dependencies: ["InsForge", "InsForgeStorage", "TestHelper"],
            path: "Tests/InsForgeStorageTests"
        ),
        .testTarget(
            name: "InsForgeFunctionsTests",
            dependencies: ["InsForge", "InsForgeFunctions", "TestHelper"],
            path: "Tests/InsForgeFunctionsTests"
        ),
        .testTarget(
            name: "InsForgeAITests",
            dependencies: ["InsForge", "InsForgeAI", "TestHelper"],
            path: "Tests/InsForgeAITests"
        ),
        .testTarget(
            name: "InsForgeRealtimeTests",
            dependencies: ["InsForge", "InsForgeRealtime", "TestHelper"],
            path: "Tests/InsForgeRealtimeTests"
        ),
    ]
)
