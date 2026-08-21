import SwiftUI
import RiftboundVision

/// The camera feed, its overlays, and the detection badge.
///
/// Pulled out of `ContentView`, which had grown to own the window layout,
/// the toolbar, the diagnostics sheet *and* every pixel of this — four
/// reasons to change in one file. This one has a single reason: how the
/// live picture is drawn.
///
/// The gold frame is applied *outside* the `GeometryReader` so the overlay
/// maths is untouched by it — the scale correction refers to the feed's own
/// bounds, not the frame's.
struct CameraStageView: View {
    @ObservedObject var pipeline: CameraPipelineController
    /// Shared with the card strip: tapping a detection box selects the same
    /// card the strip highlights.
    @Binding var selectedCard: CardPrinting?

    /// The framed camera area. The frame is drawn *outside* the
    /// `GeometryReader` so the overlay maths below is untouched by it —
    /// the scale correction still refers to the feed's own bounds, not the
    /// frame's.
    var body: some View {
        cameraFeed
            // Every camera this app targets (built-in, Continuity, USB)
            // delivers 16:9, so the frame can simply *be* that shape
            // rather than boxing a letterboxed picture.
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(RiftboundPalette.elementStroke, lineWidth: 2)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Same inset the strip and the mascot band use, so the three
            // line up down both edges (`RiftboundLayout.columnInset`).
            .padding(.horizontal, RiftboundLayout.columnInset)
    }

    private var cameraFeed: some View {
        GeometryReader { proxy in
                ZStack {
                    // Was `Color.black`. The letterbox around an
                    // aspect-fit feed is a large area of the window, and
                    // pure black is the one shade on screen that belongs
                    // to no part of the palette — it read as a hole.
                    // `elementShadow` is the board's own darkest value.
                    RiftboundPalette.elementShadow

                    if let backgroundImage = pipeline.backgroundImage {
                        Image(decorative: backgroundImage, scale: 1, orientation: .up)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Text(pipeline.isCameraRunning ? "Waiting for camera frames…" : "Opening camera…")
                            .font(RiftboundFont.body)
                            .foregroundStyle(RiftboundPalette.regularText.opacity(0.6))
                    }

                    // Both overlays draw in the raw pixel coordinates of
                    // `pipeline.frameSize`/`pipeline.calibration` (the
                    // camera frame's native size), but the image above is
                    // displayed aspect-fit inside whatever the window's
                    // current size is — without this correction, boxes
                    // and the zone reference layer drift away from what
                    // they're labeling as soon as the window isn't
                    // exactly the camera's native resolution.
                    let scale = fitScale(container: proxy.size, content: pipeline.frameSize)

                    PlaymatOverlayView(calibration: $pipeline.calibration, isEditable: pipeline.isCalibrating)
                        .frame(width: pipeline.frameSize.width, height: pipeline.frameSize.height)
                        .scaleEffect(scale)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)

                    // Interactive: tapping a card's box selects it, which
                    // is how the sidebar is driven now.
                    LiveDetectionOverlayView(
                        detections: pipeline.detections,
                        cardDatabase: pipeline.cardDatabase,
                        selectedPrintingID: selectedCard?.id,
                        onSelect: { selectedCard = $0 }
                    )
                        .frame(width: pipeline.frameSize.width, height: pipeline.frameSize.height)
                        .scaleEffect(scale)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)

                    // Above the detection boxes: the tracker's centroids
                    // and their stable IDs. This is the layer that shows
                    // whether a card keeps its identity across a pickup —
                    // the boxes below look the same either way.
                    TrackedObjectOverlayView(objects: pipeline.trackedObjects)
                        .frame(width: pipeline.frameSize.width, height: pipeline.frameSize.height)
                        .scaleEffect(scale)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                        .allowsHitTesting(false)

                    VStack {
                        detectionCountBadge
                        Spacer()
                    }
                    .padding(.top, 12)

                    if let errorMessage = pipeline.errorMessage {
                        VStack {
                            Spacer()
                            Text(errorMessage)
                                .font(RiftboundFont.body)
                                .foregroundStyle(RiftboundPalette.regularText)
                                .padding(10)
                                .background(RiftboundPalette.primaryButton, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .padding()
                        }
                    }
                }
            }
    }

    private var detectionCountBadge: some View {
        HStack(spacing: 8) {
            Text(pipeline.detections.isEmpty ? "No cards detected" : "\(pipeline.detections.count) card\(pipeline.detections.count == 1 ? "" : "s") detected")
            // Visible proof the reconnected Object Tracking + Area of
            // Region pipeline (expertSystemAdapter) is actually producing
            // events, not just structurally wired — see
            // CameraPipelineController.observedEvents' doc comment.
            if !pipeline.observedEvents.isEmpty {
                Text("· \(pipeline.observedEvents.count) table event\(pipeline.observedEvents.count == 1 ? "" : "s")")
                    .foregroundStyle(RiftboundPalette.regularText.opacity(0.6))
            }
            // The measured detection rate, not a configured one — this is
            // what the machine actually sustains.
            if pipeline.detectionsPerSecond > 0 {
                Text("· \(pipeline.detectionsPerSecond, specifier: "%.0f") fps")
                    .foregroundStyle(RiftboundPalette.regularText.opacity(0.6))
            }
        }
        .font(RiftboundFont.body)
        .foregroundStyle(RiftboundPalette.regularText)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(RiftboundPalette.elementShadow.opacity(0.85), in: Capsule())
        .overlay(Capsule().stroke(RiftboundPalette.elementStroke.opacity(0.7), lineWidth: 1))
    }

    /// Aspect-fit scale factor, matching `.aspectRatio(contentMode: .fit)`
    /// above — kept in lockstep so the overlay always sits exactly over
    /// the displayed video image, not the raw window bounds.
    private func fitScale(container: CGSize, content: CGSize) -> CGFloat {
        guard content.width > 0, content.height > 0 else { return 1 }
        return min(container.width / content.width, container.height / content.height)
    }
}
