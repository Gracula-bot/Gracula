// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Gracula",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Gracula", targets: ["AgentApp"]),
        .library(name: "AppShell", targets: ["AppShell"]),
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "Application", targets: ["Application"]),
        .library(name: "Voice", targets: ["Voice"]),
        .library(name: "LLM", targets: ["LLM"]),
        .library(name: "Tools", targets: ["Tools"]),
        .library(name: "Automation", targets: ["Automation"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "AgentSecurity", targets: ["AgentSecurity"]),
        .library(name: "Shared", targets: ["Shared"])
    ],
    targets: [
        .executableTarget(
            name: "AgentApp",
            dependencies: [
                "AppShell",
                "Application",
                "Domain",
                "Voice",
                "LLM",
                "Tools",
                "Automation",
                "Persistence",
                "AgentSecurity",
                "Shared"
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "AppShell",
            dependencies: ["Application", "Domain", "Shared", "Voice"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "Domain",
            dependencies: [],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "Application",
            dependencies: ["Domain", "Shared"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "Voice",
            dependencies: ["Application", "Domain", "Shared"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "LLM",
            dependencies: ["Application", "Domain", "Shared"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "Tools",
            dependencies: ["Application", "Domain", "Automation", "Persistence", "AgentSecurity", "Shared"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "Automation",
            dependencies: ["Domain", "Shared"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "Persistence",
            dependencies: ["Domain", "Shared"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "AgentSecurity",
            dependencies: ["Domain", "Shared"],
            path: "Sources/Security",
            swiftSettings: swiftSettings
        ),
        .target(
            name: "Shared",
            dependencies: [],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "DomainTests",
            dependencies: ["Domain"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "ApplicationTests",
            dependencies: ["Application", "Domain"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "VoiceTests",
            dependencies: ["Voice"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "LLMTests",
            dependencies: ["LLM"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "ToolsTests",
            dependencies: ["Tools"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "SecurityTests",
            dependencies: ["AgentSecurity"],
            swiftSettings: swiftSettings
        )
    ]
)

private let swiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6)
]
