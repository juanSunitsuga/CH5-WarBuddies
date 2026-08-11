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
                // NOT .process(): SwiftPM's Core ML codegen collides when a
                // single target processes more than one .mlpackage (their
                // internal files - Manifest.json, model.mlmodel,
                // weights/weight.bin - all share the same relative names,
                // and the codegen step dedupes by that name across the
                // whole target instead of per-package). Copying them
                // verbatim and loading via `MLModel(contentsOf:)` at
                // runtime (see `MiniLMEmbedderService`/
                // `CardTypeClassifierService`) sidesteps that entirely.
                .copy("Resources/MiniLMEmbedder.mlpackage"),
                .copy("Resources/RiftboundCardTypeClassifier.mlpackage"),
                // Copy SQLite database directly into module bundle
                .copy("Resources/RiftboundCardDatabase.db")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        // Separate from the library target on purpose - a `.library`
        // product can't contain an executable (a `main.swift`), which is
        // what this file is: a standalone CLI smoke test for
        // `ActionTranslatingEngine`, not part of the library's own API.
        .executableTarget(
            name: "RiftboundTextProcessingDemo",
            dependencies: ["RiftboundTextProcessing"],
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
