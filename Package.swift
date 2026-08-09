// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PathShelf",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "PathShelf", targets: ["PathShelfApp"]),
        .executable(name: "ContractTests", targets: ["ContractTests"]),
        .executable(name: "ServiceContractTests", targets: ["ServiceContractTests"]),
        .executable(name: "PanelContractTests", targets: ["PanelContractTests"]),
        .executable(name: "EventContractTests", targets: ["EventContractTests"]),
        .executable(name: "ProcessMetricsProbe", targets: ["ProcessMetricsProbe"]),
        .library(
            name: "PathShelfCore",
            targets: ["FileAccess", "SettingsFeature", "PanelFeature", "FileOperations", "PreviewFeature"]
        )
    ],
    targets: [
        .executableTarget(
            name: "PathShelfApp",
            dependencies: [
                "FileAccess",
                "SettingsFeature",
                "PanelFeature",
                "FileOperations",
                "PreviewFeature"
            ],
            path: "Sources/AppShell"
        ),
        .target(
            name: "FileAccess",
            path: "Sources/FileAccess",
            linkerSettings: [
                .linkedFramework("CoreServices")
            ]
        ),
        .target(
            name: "SettingsFeature",
            dependencies: ["FileAccess", "PanelFeature"],
            path: "Sources/SettingsFeature"
        ),
        .target(
            name: "PanelFeature",
            dependencies: ["FileAccess", "FileOperations", "PreviewFeature"],
            path: "Sources/PanelFeature",
            linkerSettings: [
                .linkedFramework("ApplicationServices")
            ]
        ),
        .target(
            name: "FileOperations",
            path: "Sources/FileOperations"
        ),
        .target(
            name: "PreviewFeature",
            path: "Sources/PreviewFeature"
        ),
        .executableTarget(
            name: "ContractTests",
            dependencies: ["FileAccess", "SettingsFeature", "PanelFeature"],
            path: "Sources/ContractTests"
        ),
        .executableTarget(
            name: "ServiceContractTests",
            dependencies: ["FileOperations", "PreviewFeature"],
            path: "Sources/ServiceContractTests"
        ),
        .executableTarget(
            name: "PanelContractTests",
            dependencies: ["FileAccess", "FileOperations", "PanelFeature", "PreviewFeature"],
            path: "Sources/PanelContractTests"
        ),
        .executableTarget(
            name: "EventContractTests",
            dependencies: ["FileAccess", "FileOperations", "PanelFeature", "PreviewFeature"],
            path: "Sources/EventContractTests"
        ),
        .executableTarget(
            name: "ProcessMetricsProbe",
            path: "Sources/ProcessMetricsProbe"
        )
    ]
)
