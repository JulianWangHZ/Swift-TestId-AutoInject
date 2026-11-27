// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-testid-autoinject",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "testid-inject", targets: ["testid-inject"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "604.0.0"),
        .package(url: "https://github.com/tuist/XcodeProj.git", from: "9.17.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.0"),
    ],
    targets: [
        .target(
            name: "TestIDCore",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "TestIDSetup",
            dependencies: [.product(name: "XcodeProj", package: "XcodeProj")]
        ),
        .executableTarget(
            name: "testid-inject",
            dependencies: [
                "TestIDCore",
                "TestIDSetup",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "TestIDCoreTests", dependencies: ["TestIDCore"]),
        .testTarget(
            name: "TestIDSetupTests",
            dependencies: ["TestIDSetup", .product(name: "XcodeProj", package: "XcodeProj")],
            resources: [.copy("Fixtures")]
        ),
    ]
)
