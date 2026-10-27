// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MochiIsland",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "MochiIsland", targets: ["MochiIsland"]),
        .executable(name: "MochiHookCLI", targets: ["MochiHookCLI"]),
        .executable(name: "MochiCoreChecks", targets: ["MochiCoreChecks"])
    ],
    targets: [
        .target(name: "MochiCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "MochiIsland",
            dependencies: ["MochiCore"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("WebKit"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .executableTarget(
            name: "MochiHookCLI",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "MochiCoreChecks",
            dependencies: ["MochiCore"],
            path: "Tests/MochiCoreChecks",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
