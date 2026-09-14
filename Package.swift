// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "MondayChan",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MondayChan", targets: ["MondayChan"])],
    dependencies: [
        .package(url: "https://github.com/cocoa-xu/flowing-day-ui.git", exact: "2.6.5")
    ],
    targets: [
        .target(name: "MondayCore"),
        .target(name: "MondayImport", dependencies: ["MondayCore"]),
        .target(name: "MondayMetal", dependencies: ["MondayCore"], exclude: ["Shaders"], plugins: ["CompileMetalShaders"]),
        .plugin(name: "CompileMetalShaders", capability: .buildTool()),
        .executableTarget(name: "MondayChan", dependencies: [
            "MondayCore", "MondayMetal", "MondayImport",
            .product(name: "FlowingDayControls", package: "flowing-day-ui"),
            .product(name: "FlowingDayPreferences", package: "flowing-day-ui")
        ], resources: [.copy("Assets"), .copy("ThirdPartyNotices"), .process("Localization")]),
        .testTarget(name: "MondayImportTests", dependencies: ["MondayImport", "MondayCore"]),
        .testTarget(name: "MondayCoreTests", dependencies: ["MondayCore"]),
        .testTarget(name: "MondayMetalTests", dependencies: ["MondayMetal", "MondayCore"]),
        .testTarget(name: "MondayChanTests", dependencies: ["MondayChan", "MondayCore"])
    ]
)
