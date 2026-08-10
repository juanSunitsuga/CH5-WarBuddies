import SwiftUI
import RiftboundVision

/// Draws a highlight ring around every Rune `pendingPlay` says the player
/// still needs to exhaust — red while Ready, green the instant its
/// observed rotation reads Exhausted (a frame before
/// `CameraPipelineController` clears `pendingPlay` once *all* of them are).
/// Positions come straight from `objects` (the live snapshot), so the
/// rings track the physical Runes in real time as the camera sees them.
struct ExhaustPromptOverlayView: View {
    let pendingPlay: CameraPipelineController.PendingCardPlay
    let objects: [TrackedObject]

    private static let exhaustedRotationThreshold: CGFloat = .pi / 4

    private var requiredObjects: [TrackedObject] {
        pendingPlay.requiredRuneIDs.compactMap { id in objects.first { $0.id == id } }
    }

    var body: some View {
        ForEach(requiredObjects, id: \.id) { object in
            let isExhausted = object.rotation >= Self.exhaustedRotationThreshold
            RoundedRectangle(cornerRadius: 6)
                .stroke(isExhausted ? Color.green : Color.red, lineWidth: 4)
                .frame(width: object.boundingBox.width + 12, height: object.boundingBox.height + 12)
                .position(x: object.boundingBox.midX, y: object.boundingBox.midY)
                .shadow(color: isExhausted ? .green : .red, radius: 6)
        }
    }
}

/// The banner telling the player what to do — "Exhaust 3/5 Runes to play
/// Annie - Fiery" — with a way to back out. Separate from the ring
/// overlay above so `ContentView` can position it (top of screen) while
/// the rings live inside the scaled/positioned camera-space overlay stack.
struct ExhaustPromptBanner: View {
    let cardName: String
    let progress: (done: Int, total: Int)
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.fill")
            Text("Exhaust \(progress.done)/\(progress.total) Runes to play \(cardName)")
                .font(.headline)
            Button("Cancel", action: onCancel)
        }
        .padding(10)
        .background(.black.opacity(0.85))
        .foregroundStyle(.white)
        .cornerRadius(8)
    }
}
