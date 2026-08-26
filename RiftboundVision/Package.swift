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
                // Hand-drawn border frames for PlaymatOverlayView's zone
                // boxes, plus the corner grab handle. One frame per zone
                // shape — see the table on PlaymatOverlayView for which
                // asset is which zone, since the designer's names don't
                // say. SVG rather than PNG: these are scaled to whatever
                // the calibrated quad turns out to be, and NSImage reads
                // SVG directly on macOS.
                //
                // The app target has its own catalog copies; these exist
                // so previews and tests, which have no app bundle to read
                // a catalog from, still draw real art.
                .copy("Resources/Rectangle 1.svg"),
                .copy("Resources/Rectangle 2.svg"),
                .copy("Resources/Rectangle 3.svg"),
                .copy("Resources/Rectangle 4.svg"),
                .copy("Resources/Rectangle 5.svg"),
                .copy("Resources/Rectangle 6.svg"),
                .copy("Resources/Rectangle 7.svg"),
                .copy("Resources/Ellipse.svg"),
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
