// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodeFM",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "CodeFM",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("WebKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Carbon"),
            ]
        )
    ]
)
