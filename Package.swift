// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StaticBadge",
    platforms: [.macOS(.v12)],
    targets: [
        // 打包进仓库的 libwebp（上游源码 + 一层精简 C 封装）。
        // macOS 的 ImageIO 不能写 WebP，导出必须自带编码器。
        .target(
            name: "CWebP",
            path: "Sources/CWebP",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("."),
                .define("WEBP_USE_THREAD", to: "1"),
            ]
        ),
        .target(
            name: "StaticBadgeCore",
            dependencies: ["CWebP"],
            path: "Sources/StaticBadgeCore"
        ),
        .executableTarget(
            name: "StaticBadge",
            dependencies: ["StaticBadgeCore"],
            path: "Sources/StaticBadge",
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "StaticBadgeCoreTests",
            dependencies: ["StaticBadgeCore"],
            path: "Tests/StaticBadgeCoreTests"
        ),
    ]
)
