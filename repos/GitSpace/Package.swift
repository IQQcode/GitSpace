// swift-tools-version:6.0
// GitSpace 多模块工程（TechStack §9）。
// 依赖方向单向：App → GSFeatures → (GSGitEngine, GSIndex, GSDesignKit) → GSInfra。
// GSGitEngine / GSIndex 不 import SwiftUI。
import PackageDescription

let package = Package(
    name: "GitSpace",
    defaultLocalization: "zh-CN",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "GitSpaceApp", targets: ["GitSpaceApp"])
    ],
    targets: [
        .target(
            name: "GSInfra",
            path: "Packages/GSInfra/Sources/GSInfra"
        ),
        .target(
            name: "GSDesignKit",
            path: "Packages/GSDesignKit/Sources/GSDesignKit"
        ),
        .target(
            name: "GSGitEngine",
            dependencies: ["GSInfra"],
            path: "Packages/GSGitEngine/Sources/GSGitEngine"
        ),
        .target(
            name: "GSIndex",
            dependencies: ["GSGitEngine"],
            path: "Packages/GSIndex/Sources/GSIndex"
        ),
        .target(
            name: "GSFeatures",
            dependencies: ["GSGitEngine", "GSIndex", "GSDesignKit", "GSInfra"],
            path: "Packages/GSFeatures/Sources/GSFeatures"
        ),
        .executableTarget(
            name: "GitSpaceApp",
            dependencies: ["GSFeatures", "GSGitEngine", "GSIndex", "GSDesignKit", "GSInfra"],
            path: "App/Sources/GitSpaceApp"
        ),
        .target(
            name: "GSTestSupport",
            dependencies: ["GSGitEngine", "GSIndex"],
            path: "Packages/GSTestSupport/Sources/GSTestSupport"
        ),
        .testTarget(
            name: "GSGitEngineTests",
            dependencies: ["GSGitEngine", "GSTestSupport"],
            path: "Tests/GSGitEngineTests"
        ),
        .testTarget(
            name: "GSIndexTests",
            dependencies: ["GSIndex", "GSTestSupport"],
            path: "Tests/GSIndexTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
