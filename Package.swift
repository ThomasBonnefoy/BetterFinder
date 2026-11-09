// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BetterFinder",
    platforms: [.macOS(.v26)],
    targets: [
        // Pure logic: file listing, sorting, navigation history, path parsing.
        .target(name: "BetterFinderCore"),
        // The app itself (SwiftUI window, AppKit file list).
        .executableTarget(
            name: "BetterFinder",
            dependencies: ["BetterFinderCore"]
        ),
    ]
)
