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
