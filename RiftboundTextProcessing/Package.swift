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
        // Exported library used by the main app shell or sibling Vision targets
        .library(
            name: "RiftboundTextProcessing",
            targets: ["RiftboundTextProcessing"]
        )
    ],
    dependencies: [
        // Sibling package dependency providing core rules & state models
        .package(path: "../RiftboundEngine")
    ],
    targets: [
        .target(
            name: "RiftboundTextProcessing",
            dependencies: [
                .product(name: "RiftboundExpertSystem", package: "RiftboundEngine")
            ],
            resources: [
                // SPM automatically compiles .mlpackage models into binary .mlmodelc
                .process("Resources/MiniLMEmbedder.mlpackage"),
                .process("Resources/RiftboundCardTypeClassifier.mlpackage"),
                // Copy SQLite database directly into module bundle
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
