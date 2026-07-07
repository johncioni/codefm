// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodeFM",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "CodeFM",
            path: ".",
            exclude: [
                "Package.swift",
                "README.md",
                "Tests",
                "Scripts",
                "docs",
                "build",
                "Resources/AppIcon.icns",
                "Resources/AppIcon.png",
                "Resources/CodeFM.entitlements",
                "Resources/Info.plist",
            ],
            sources: ["Sources"],
            resources: [.copy("Resources/streams.json")],
            linkerSettings: [
                .linkedFramework("WebKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Carbon"),
            ]
        ),
        .testTarget(
            name: "CodeFMTests",
            dependencies: ["CodeFM"],
            path: "Tests/CodeFMTests"
        )
    ]
)
