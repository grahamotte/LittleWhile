// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "App",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "App",
            path: ".",
            exclude: ["App/App.swift", "App/Assets.xcassets", "App/Config", "App/PrivacyInfo.xcprivacy", "App.xcodeproj", "Tests", "TimerActivityWidget"],
            sources: ["App", "Shared"],
        ),
        .testTarget(name: "AppTests", dependencies: ["App"], path: "Tests", exclude: ["Package.swift"]),
    ]
)
