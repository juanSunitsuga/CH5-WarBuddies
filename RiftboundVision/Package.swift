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
        .package(path: "../RiftboundEngine"),
        // Test-only (see the test target below): the full-pipeline
        // integration test needs the NLP translator, and this test target
        // is the only place all four stages are visible at once. The
        // library target deliberately does NOT depend on it — Vision must
        // never need the NLP layer to do its own job.
        .package(path: "../RiftboundTextProcessing")
    ],
    targets: [
        .target(
            name: "RiftboundVision",
            dependencies: [
                .product(name: "RiftboundExpertSystem", package: "RiftboundEngine")
            ],
            resources: [
                // Hand-drawn gold border frames for PlaymatOverlayView's
                // zone boxes (the "RiftChamps" mockup look) — see
                // PlaymatOverlayView.frame(for:) for which asset goes on
                // which zone and why (each is a stretchable texture, not
                // shape-locked, but stretching one *too* far past its own
                // native aspect visibly smears its corner accents — that's
                // why there are 4 variants, not 1).
                .copy("Resources/Rectangle 1.png"),
                .copy("Resources/Rectangle 2.png"),
                .copy("Resources/Rectangle 3.png"),
                .copy("Resources/Rectangle 4.png"),
                // The board's swatches. A package can't read the app
                // target's Assets.xcassets, so the overlays this module
                // draws over the camera carry their own copy — see
                // PlaymatPalette for why that copy exists and what keeps
                // it honest.
                .process("Resources/Palette.xcassets")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "RiftboundVisionTests",
            dependencies: [
                "RiftboundVision",
                .product(name: "RiftboundExpertSystem", package: "RiftboundEngine"),
                .product(name: "RiftboundTextProcessing", package: "RiftboundTextProcessing")
            ],
            resources: [
                .copy("Fixtures/annie_trimmed.json")
            ]
        )
    ]
)
