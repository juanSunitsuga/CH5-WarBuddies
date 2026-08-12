import SwiftUI
import AppKit

/// Draws the Riftbound playmat's zone outlines over the camera feed — the
/// "overlay is a Riftbound playmat" piece. In `isEditable` mode, 4 corner
/// handles let the user drag the template into alignment with their
/// physical mat; that's the entire calibration UI, matching the
/// "calibrated once, not detected by ML" approach used throughout this
/// layer.
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

    private static func loadFrame(_ name: String) -> Image {
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
                    // The border art is an axis-aligned rectangle texture;
                    // `boundingRect` is the same simplification the
                    // detector's own region-of-interest already makes
                    // elsewhere in this layer — a calibrated quad that's
                    // reasonably close to a real rectangle (which dragging
                    // 4 corners onto a physical mat's corners naturally
                    // produces) doesn't need a true quad-warp for this.
                    context.draw(frame(for: zoneTemplate.zone), in: boundingRect(of: points))

                    if showLabels, let centroid = centroid(of: points) {
                        // `GraphicsContext.draw` needs a plain `Text` —
                        // `.shadow` (and most other view modifiers) widen
                        // it to `some View`, which doesn't fit that
                        // overload. Fake a legible outline instead by
                        // drawing the same text in black, offset a couple
                        // points in each direction, underneath the white
                        // text — keeps it readable over any background
                        // color the zone happens to be drawn in.
                        let text = Text(label(for: zoneTemplate)).font(.system(size: 28, weight: .bold))
                        for offset in [CGPoint(x: -1.5, y: -1.5), CGPoint(x: 1.5, y: -1.5), CGPoint(x: -1.5, y: 1.5), CGPoint(x: 1.5, y: 1.5)] {
                            context.draw(text.foregroundStyle(.black), at: CGPoint(x: centroid.x + offset.x, y: centroid.y + offset.y))
                        }
                        context.draw(text.foregroundStyle(.white), at: centroid)
                    }
                }

                var boundary = Path()
                boundary.addLines(calibration.boundingPolygon)
                boundary.closeSubpath()
                context.stroke(boundary, with: .color(.yellow), lineWidth: 2.5)
            }
            .allowsHitTesting(false)

            if isEditable {
                handle(\.topLeft)
                handle(\.topRight)
                handle(\.bottomRight)
                handle(\.bottomLeft)
            }
        }
    }

    private func handle(_ keyPath: WritableKeyPath<PlaymatCalibration, CGPoint>) -> some View {
        Circle()
            .fill(Color.yellow)
            .overlay(Circle().stroke(Color.black, lineWidth: 1))
            .frame(width: 18, height: 18)
            .position(calibration[keyPath: keyPath])
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    calibration[keyPath: keyPath] = value.location
                }
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
