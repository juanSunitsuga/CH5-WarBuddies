// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RiftboundExpertSystem",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "RiftboundExpertSystem",
            targets: ["RiftboundExpertSystem"]
        )
    ],
    targets: [
        .target(
            name: "RiftboundExpertSystem",
            resources: [
                // The knowledge base. Rules as data is the whole point of
                // `RuleBase`/`RuleEngine`: shipped as a resource so a rule
                // can be corrected without recompiling the engine.
                .process("Resources/RuleBase.json")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "RiftboundExpertSystemTests",
            dependencies: ["RiftboundExpertSystem"]
        )
    ]
)
