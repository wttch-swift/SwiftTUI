// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TUIDemo",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        // 命令行 SwiftUI 引擎
        .library(name: "TerminalUI", targets: ["TerminalUI"]),
    ],
    targets: [
        // 公共值类型，不依赖渲染器或声明式 View。
        .target(
            name: "TerminalUIFoundation",
            exclude: ["README.md"]
        ),

        // 最小 Combine 反应式核心，不依赖任何 TerminalUI target。
        .target(
            name: "WttchCombine",
            exclude: ["README.md"]
        ),

        // 包内渲染实现。未声明为 product，外部客户端不能直接依赖。
        .target(
            name: "TerminalUICore",
            dependencies: ["TerminalUIFoundation"],
            exclude: ["README.md"]
        ),

        // SwiftUI 风格的声明层，不包含 LayoutNode 或 Canvas。
        .target(
            name: "TerminalUIView",
            dependencies: ["TerminalUIFoundation"],
            exclude: ["README.md"]
        ),

        // 声明式 View 到布局节点的包内适配与布局算法。
        .target(
            name: "TerminalUILayout",
            dependencies: ["TerminalUIFoundation", "TerminalUICore", "TerminalUIView"],
            exclude: ["README.md"]
        ),

        // 遍历 LayoutNode 并驱动 Core Canvas，不提供客户端 API。
        .target(
            name: "TerminalUIRender",
            dependencies: [
                "TerminalUIFoundation",
                "TerminalUICore",
                "TerminalUIView",
                "TerminalUILayout",
            ],
            exclude: ["README.md"]
        ),

        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        // TerminalUI 是一个独立的库，提供命令行界面组件和渲染功能
        .target(
            name: "TerminalUI",
            dependencies: [
                "TerminalUIFoundation",
                "WttchCombine",
                "TerminalUICore",
                "TerminalUIView",
                "TerminalUILayout",
                "TerminalUIRender",
            ],
            exclude: ["README.md"]
        ),

        .executableTarget(
            name: "TUIDemo",
            dependencies: ["TerminalUI"],
            exclude: ["README.md"]
        ),
        .testTarget(
            name: "TUIDemoTests",
            dependencies: [
                "TerminalUI",
                "TerminalUICore",
                "TerminalUIView",
                "TerminalUILayout",
                "TerminalUIRender",
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
