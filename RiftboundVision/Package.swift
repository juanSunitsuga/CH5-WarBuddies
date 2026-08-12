// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RiftboundVision",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // A library, not an app — the runnable macOS app shell (camera
        // permission, Info.plist, app icon) lives in the sibling
        // RiftboundVisionApp.xcodeproj, which depends on this package.
        // This target stays a pure library of tracking/event/adapter
        // logic so it's usable from a real Xcode app target, testable on
        // its own, and never needs its own bundle identity.
        .library(name: "RiftboundVision", targets: ["RiftboundVision"])
    ],
    dependencies: [
        // The existing Expert System — kept as a separate package on
        // purpose. This target must never redefine Riftbound rules,
        // legality, or card effects; it only produces `ObservedTableEvent`s
        // for the Expert System to interpret.
        .package(path: "../RiftboundEngine")
    ],
    targets: [
        .target(
            name: "RiftboundVision",
            dependencies: [
                .product(name: "RiftboundExpertSystem", package: "RiftboundEngine")
            ],
            resources: [
                // Hand-drawn gold border frames for PlaymatOverlayView's
                // zone boxes (the "RiftChamps" mockup look) — three
                // variants, not because each is locked to one shape, but
                // because that's the mapping the mockup specifies: Rectangle
                // 2 for Battlefield, Rectangle 3 for Base, Rectangle 1 for
                // every other zone, each stretched to its own zone's size.
                .copy("Resources/Rectangle 1.png"),
                .copy("Resources/Rectangle 2.png"),
                .copy("Resources/Rectangle 3.png")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "RiftboundVisionTests",
            dependencies: [
                "RiftboundVision",
                .product(name: "RiftboundExpertSystem", package: "RiftboundEngine")
            ],
            resources: [
                .copy("Fixtures/annie_trimmed.json")
            ]
        )
    ]
)
