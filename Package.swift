// swift-tools-version: 6.3

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "DuffyNetworking",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6),
        .macCatalyst(.v13),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "DuffyNetworking",
            targets: ["DuffyNetworking"],
        ),
        .library(
            name: "DuffyNetworkingTestSupport",
            targets: ["DuffyNetworkingTestSupport"],
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-http-types.git", from: "1.6.0"),
        .package(
            url: "https://github.com/pointfreeco/swift-macro-testing",
            from: "0.6.0",
        ),
        .package(
            url: "https://github.com/swiftlang/swift-syntax",
            "600.0.0"..<"604.0.0",
        ),
    ],
    targets: [
        .macro(
            name: "DuffyNetworkingMacros",
            dependencies: [
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            ],
        ),
        .target(
            name: "DuffyNetworking",
            dependencies: [
                "DuffyNetworkingMacros",
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "HTTPTypesFoundation", package: "swift-http-types"),
            ],
        ),
        .target(
            name: "DuffyNetworkingTestSupport",
            dependencies: [
                "DuffyNetworking",
            ],
        ),
        .testTarget(
            name: "DuffyNetworkingTests",
            dependencies: [
                "DuffyNetworking",
                "DuffyNetworkingTestSupport",
                .product(name: "HTTPTypes", package: "swift-http-types"),
            ],
        ),
        .testTarget(
            name: "DuffyNetworkingMacrosTests",
            dependencies: [
                "DuffyNetworkingMacros",
                .product(name: "MacroTesting", package: "swift-macro-testing"),
            ],
        ),
    ],
    swiftLanguageModes: [.v6]
)
