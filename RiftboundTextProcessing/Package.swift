//
//  Package.swift
//  
//
//  Created by I Gusti Ngurah Bagus Ferry Mahayudha on 10/08/26.
//

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RiftboundTextProcessing",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "RiftboundTextProcessing",
            targets: ["RiftboundTextProcessing"]
        )
    ],
    dependencies: [
        .package(path: "../RiftboundEngine")
    ],
    targets: [
        .target(
            name: "RiftboundTextProcessing",
            dependencies: [
                .product(name: "RiftboundExpertSystem", package: "RiftboundEngine")
            ],
            resources: [
                .copy("Resources/RiftboundCardDatabase.db")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "RiftboundTextProcessingTests",
            dependencies: [
                "RiftboundTextProcessing",
                .product(name: "RiftboundExpertSystem", package: "RiftboundEngine")
            ]
        )
    ]
)
