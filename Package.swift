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
    ],
    targets: [
        // Core helpers and utilities
        .target(
            name: "InsForgeCore",
            dependencies: [],
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

        // Test targets
        .testTarget(
            name: "InsForgeTests",
            dependencies: ["InsForge"],
            path: "Tests/InsForgeTests"
        ),
        .testTarget(
            name: "InsForgeAuthTests",
            dependencies: ["InsForgeAuth"],
            path: "Tests/InsForgeAuthTests"
        ),
        .testTarget(
            name: "InsForgeDatabaseTests",
            dependencies: ["InsForgeDatabase"],
            path: "Tests/InsForgeDatabaseTests"
        ),
        .testTarget(
            name: "InsForgeStorageTests",
            dependencies: ["InsForgeStorage"],
            path: "Tests/InsForgeStorageTests"
        ),
        .testTarget(
            name: "InsForgeFunctionsTests",
            dependencies: ["InsForgeFunctions"],
            path: "Tests/InsForgeFunctionsTests"
        ),
        .testTarget(
            name: "InsForgeAITests",
            dependencies: ["InsForgeAI"],
            path: "Tests/InsForgeAITests"
        ),
        .testTarget(
            name: "InsForgeRealtimeTests",
            dependencies: ["InsForgeRealtime"],
            path: "Tests/InsForgeRealtimeTests"
        ),
    ]
)
