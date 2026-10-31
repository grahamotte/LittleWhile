// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LittleWhile",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "LittleWhileCore",
            path: ".",
            exclude: ["App/App.swift", "App/Assets.xcassets", "App/Config", "App/DebugHooks.swift", "App/PrivacyInfo.xcprivacy", "App.xcodeproj", "Tests", "TimerActivityWidget"],
            sources: ["App", "Shared"],
            swiftSettings: [.define("APP_DEV"), .swiftLanguageMode(.v5)],
        ),
        .testTarget(
            name: "LittleWhileCoreTests",
            dependencies: ["LittleWhileCore"],
            path: "Tests",
            exclude: ["Package.swift"],
            swiftSettings: [.swiftLanguageMode(.v5)],
        ),
    ]
)
