import SwiftUI

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

    public var body: some View {
        ZStack {
            Canvas { context, _ in
                for zoneTemplate in template {
                    let points = zoneTemplate.normalizedPolygon.map(calibration.map)
                    var path = Path()
                    path.addLines(points)
                    path.closeSubpath()
                    context.stroke(path, with: .color(color(for: zoneTemplate.zone)), lineWidth: 1.5)

                    if showLabels, let centroid = centroid(of: points) {
                        context.draw(
                            Text(label(for: zoneTemplate)).font(.system(size: 10)).foregroundStyle(.white),
                            at: centroid
                        )
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
        var text = template.zone.rawValue
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

    private func color(for zone: Zone) -> Color {
        switch zone {
        case .battlefield: return .red
        case .base: return .green
        case .runeArea: return .purple
        case .runeDeck: return .purple.opacity(0.6)
        case .trash: return .gray
        case .mainDeck: return .blue
        case .legend: return .orange
        case .champion: return .yellow
        case .player1Hand, .player2Hand, .unknown: return .white
        }
    }
}
