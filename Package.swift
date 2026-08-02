// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "DuffyNetworking",
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
    ],
    targets: [
        .target(
            name: "DuffyNetworking",
            dependencies: [
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
    ],
    swiftLanguageModes: [.v6]
)
