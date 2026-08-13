import SwiftUI
import AppKit

/// Draws the Riftbound playmat's zone outlines over the camera feed — the
/// "overlay is a Riftbound playmat" piece. In `isEditable` mode, 4 corner
/// handles let the user drag the template into alignment with their
/// physical mat; that's the entire calibration UI, matching the
/// "calibrated once, not detected by ML" approach used throughout this
/// layer.
/// The bundle holding this package's own resources. `Bundle.module` is
/// only synthesized inside the target that declares the resources, so a
/// test target can't reach the border-art PNGs without this — see
/// `PlaymatArtworkFitTests`, which measures them.
enum RiftboundVisionResources {
    static let bundle = Bundle.module
}

public struct PlaymatOverlayView: View {
    @Binding private var calibration: PlaymatCalibration
    private let isEditable: Bool
    private let showLabels: Bool
    /// Which zone layout to draw — defaults to the single-player mat
    /// (`RiftboundPlaymatTemplate.singlePlayerZones()`), the one
    /// currently in active use. Pass `.twoPlayerZones` to go back to the
    /// shared-mat layout.
    private let template: [PlaymatZoneTemplate]

    public init(
        calibration: Binding<PlaymatCalibration>,
        isEditable: Bool,
        showLabels: Bool = true,
        template: [PlaymatZoneTemplate] = RiftboundPlaymatTemplate.singlePlayerZones()
    ) {
        self._calibration = calibration
        self.isEditable = isEditable
        self.showLabels = showLabels
        self.template = template
    }

    /// The "RiftChamps" mockup's hand-drawn gold border frames — not
    /// shape-locked art in principle (each is just a sketchy-line texture
    /// stretched to whatever box it's drawn into), but stretching one
    /// *far* past its own native aspect visibly smears its corner accents
    /// (confirmed against a real render: Rectangle 1 — a narrow,
    /// near-square 121×164 texture — stretched across the full-width Hand
    /// zone turned its corner strokes into long vertical streaks). So the
    /// mapping is by actual zone shape, not a single default:
    ///   - Rectangle 2 (394×164, landscape): Battlefield
    ///   - Rectangle 3 (520×164, wider landscape): Base and Rune Area —
    ///     both wide rows the same general proportions as Base
    ///   - Rectangle 4 (645×164, widest): Hand — wider than either of the
    ///     above, and the zone most prone to the stretching artifact
    ///   - Rectangle 1 (121×164, narrow/near-square): everything else
    ///     (Legend, Champion, Main Deck, Rune Deck, Trash) — zones that
    ///     are actually close to this texture's own native aspect
    private static let battlefieldFrame = loadFrame("Rectangle 2")
    private static let baseFrame = loadFrame("Rectangle 3")
    private static let handFrame = loadFrame("Rectangle 4")
    private static let defaultFrame = loadFrame("Rectangle 1")

    /// Prefers the host app's asset catalog (`Assets.xcassets`), falling
    /// back to this package's own bundled copy. `NSImage(named:)` searches
    /// the *main* bundle, so in `RiftboundVisionApp` this picks up the
    /// catalog entry; in tests and previews — where there is no app
    /// catalog — it falls through to `Bundle.module`, which is why the
    /// package keeps its copies rather than deleting them.
    private static func loadFrame(_ name: String) -> Image {
        if let catalogImage = NSImage(named: name) {
            return Image(nsImage: catalogImage)
        }
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
              let nsImage = NSImage(contentsOf: url) else {
            // Shouldn't happen — these are bundled resources, not
            // user-supplied data — but a missing/renamed asset shouldn't
            // crash the calibration overlay; fall back to a visible
            // placeholder instead.
            return Image(systemName: "questionmark.square.dashed")
        }
        return Image(nsImage: nsImage)
    }

    private func frame(for zone: Zone) -> Image {
        switch zone {
        case .battlefield: return Self.battlefieldFrame
        case .base, .runeArea: return Self.baseFrame
        case .player1Hand, .player2Hand: return Self.handFrame
        default: return Self.defaultFrame
        }
    }

    public var body: some View {
        ZStack {
            Canvas { context, _ in
                for zoneTemplate in template {
                    let points = zoneTemplate.normalizedPolygon.map(calibration.map)
                    // Draw a subtle light-beige filled background for the
                    // zone, matching the lighter playmat look in the
                    // reference image, then draw the textured border frame
                    // on top.
                    let rect = boundingRect(of: points)
                    context.draw(frame(for: zoneTemplate.zone), in: rect)

                    if showLabels, let centroid = centroid(of: points) {
                        // Draw a white outline (offsets) and dark center
                        // text so labels read like the reference image.
                        let text = Text(label(for: zoneTemplate)).font(.system(size: 24, weight: .bold))
                        for offset in [CGPoint(x: -1.5, y: -1.5), CGPoint(x: 1.5, y: -1.5), CGPoint(x: -1.5, y: 1.5), CGPoint(x: 1.5, y: 1.5)] {
                            context.draw(text.foregroundStyle(.white), at: CGPoint(x: centroid.x + offset.x, y: centroid.y + offset.y))
                        }
                        context.draw(text.foregroundStyle(Color(red: 0.12, green: 0.10, blue: 0.08)), at: centroid)
                    }
                }

                // Intentionally remove the bright yellow outer boundary
                // stroke used for debugging; the reference overlay is
                // visually quieter.
            }
            .allowsHitTesting(false)

            if isEditable {
                handle(.topLeft)
                handle(.topRight)
                handle(.bottomRight)
                handle(.bottomLeft)
                moveHandle
            }
        }
    }

    /// Which corner a handle drives. Dragging one resizes the rectangle
    /// with the *opposite* corner pinned, so the mat only ever gets wider
    /// or taller — it can never be sheared into a parallelogram.
    private enum Corner {
        case topLeft, topRight, bottomRight, bottomLeft
    }

    /// Corner drags used to set that corner's raw location, which let the
    /// four points form any quadrilateral at all. One nudge and the mat
    /// went crooked, every zone inside it sheared with it, and the
    /// calibrated regions stopped matching what the camera saw — the
    /// overlay "disorienting" on every move. Resizing an axis-aligned
    /// rectangle instead keeps the grid square by construction.
    ///
    /// This gives up free-quad perspective correction for a camera mounted
    /// at an angle. `PlaymatCalibration.map` still interpolates all four
    /// corners, so restoring it later is a UI change, not a model one.
    private func handle(_ corner: Corner) -> some View {
        let position = point(for: corner)
        return Circle()
            .fill(Color.yellow)
            .overlay(Circle().stroke(Color.black, lineWidth: 1))
            .frame(width: 18, height: 18)
            .position(position)
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    resize(corner: corner, to: value.location)
                }
            )
    }

    /// Drags the whole mat without changing its size — separate from the
    /// corners so repositioning can't accidentally reshape it.
    private var moveHandle: some View {
        let rect = currentRect
        return Circle()
            .fill(Color.yellow.opacity(0.85))
            .overlay(Image(systemName: "arrow.up.and.down.and.arrow.left.and.right").font(.system(size: 11, weight: .bold)).foregroundStyle(.black))
            .frame(width: 26, height: 26)
            .position(x: rect.midX, y: rect.midY)
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    let dx = value.location.x - rect.midX
                    let dy = value.location.y - rect.midY
                    apply(rect.offsetBy(dx: dx, dy: dy))
                }
            )
    }

    private var currentRect: CGRect {
        let xs = [calibration.topLeft.x, calibration.topRight.x, calibration.bottomRight.x, calibration.bottomLeft.x]
        let ys = [calibration.topLeft.y, calibration.topRight.y, calibration.bottomRight.y, calibration.bottomLeft.y]
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0, maxY = ys.max() ?? 0
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func point(for corner: Corner) -> CGPoint {
        let rect = currentRect
        switch corner {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        }
    }

    private func resize(corner: Corner, to location: CGPoint) {
        let rect = currentRect
        // A minimum keeps a fast drag past the opposite edge from
        // inverting the mat (which would mirror every zone).
        let minimumSize: CGFloat = 40
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY

        switch corner {
        case .topLeft:
            minX = min(location.x, maxX - minimumSize)
            minY = min(location.y, maxY - minimumSize)
        case .topRight:
            maxX = max(location.x, minX + minimumSize)
            minY = min(location.y, maxY - minimumSize)
        case .bottomRight:
            maxX = max(location.x, minX + minimumSize)
            maxY = max(location.y, minY + minimumSize)
        case .bottomLeft:
            minX = min(location.x, maxX - minimumSize)
            maxY = max(location.y, minY + minimumSize)
        }

        apply(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
    }

    private func apply(_ rect: CGRect) {
        calibration = PlaymatCalibration(
            topLeft: CGPoint(x: rect.minX, y: rect.minY),
            topRight: CGPoint(x: rect.maxX, y: rect.minY),
            bottomRight: CGPoint(x: rect.maxX, y: rect.maxY),
            bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        )
    }

    private func label(for template: PlaymatZoneTemplate) -> String {
        // `Zone.player1Hand`/`.player2Hand`'s raw value already spells out
        // which seat — showing it via `rawValue` would double up with the
        // "(P1)"/"(P2)" suffix below ("player1Hand (P1)"). Every other
        // zone case is seat-agnostic, so only this one needs the override.
        var text: String
        switch template.zone {
        case .player1Hand, .player2Hand: text = "hand"
        default: text = template.zone.rawValue
        }
        if let slot = template.battlefieldSlot {
            text += " #\(slot)"
        }
        switch template.owner {
        case .player1: return "\(text) (P1)"
        case .player2: return "\(text) (P2)"
        case nil: return text
        }
    }

    private func centroid(of points: [CGPoint]) -> CGPoint? {
        guard !points.isEmpty else { return nil }
        let x = points.map(\.x).reduce(0, +) / CGFloat(points.count)
        let y = points.map(\.y).reduce(0, +) / CGFloat(points.count)
        return CGPoint(x: x, y: y)
    }

    private func boundingRect(of points: [CGPoint]) -> CGRect {
        guard !points.isEmpty else { return .zero }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let minX = xs.min() ?? 0
        let minY = ys.min() ?? 0
        return CGRect(x: minX, y: minY, width: (xs.max() ?? 0) - minX, height: (ys.max() ?? 0) - minY)
    }
}
