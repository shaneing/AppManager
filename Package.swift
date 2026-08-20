// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AppManager",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "AppManager",
            targets: ["AppManagerApp"]
        ),
        .library(
            name: "AppManagerCore",
            targets: ["AppManagerCore"]
        ),
        .library(
            name: "AppProxyHook",
            type: .dynamic,
            targets: ["AppProxyHook"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "AppProxyHook",
            dependencies: [],
            path: "Sources/AppProxyHook",
            publicHeadersPath: "include"
        ),
        .target(
            name: "AppManagerCore",
            dependencies: [],
            path: "Sources/AppManagerCore"
        ),
        .executableTarget(
            name: "AppManagerApp",
            dependencies: ["AppManagerCore"],
            path: "Sources/AppManagerApp",
            exclude: [
                "AppManager.entitlements",
                "Info.plist"
            ]
        ),
        .testTarget(
            name: "AppManagerCoreTests",
            dependencies: ["AppManagerCore"],
            path: "Tests/AppManagerCoreTests"
        )
    ]
)
