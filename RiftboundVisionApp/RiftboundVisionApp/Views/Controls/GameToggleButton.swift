import SwiftUI

/// Starts and stops `CameraPipelineController`'s pipeline. Used to live as a
/// toolbar item beside the title bar; moved to the foot of the control
/// column so it's the last control in the stack that already holds every
/// other phase and score action, rather than sitting apart from them above
/// the camera.
///
/// Full-width rather than `RiftPrimaryButtonStyle`/`RiftSecondaryButtonStyle`
/// as-is: those size to their label, which is right for a row of buttons
/// sharing space but would leave this one hugging "Start Game" in the
/// middle of an otherwise-empty column. The fill recipe (corner radius,
/// padding, font) is still the shared one — only the width differs.
///
/// Stop Game reuses `RiftSecondaryButtonStyle`'s grey fill rather than a
/// solid red — the same quiet-grey the bottom bar already uses for a
/// disabled/secondary action — with `dangerButton` on the text only, so the
/// warning reads as a colour accent instead of a full alarm fill.
///
/// The fill is `disabledHighlightOverlay` at the board's own 50% dim
/// (`disabledComponentOpacity`) — matching how Back/End Turn actually look
/// while disabled — even though this button stays live. Only the fill
/// opacity is touched, not `riftComponentDisabled`: that dims the whole
/// component including the label, which would mute the red this is trying
/// to keep bright.
///
/// The fill is real Liquid Glass (`.glassEffect`, macOS 26+), tinted with
/// `fillColor` rather than drawn as a flat rectangle.
struct GameToggleButton: View {
    let isRunning: Bool
    let isCameraRunning: Bool
    let onToggle: () -> Void

    /// The camera must be live to start the pipeline, but Stop always has
    /// to be pressable — a running pipeline can't be trapped by the camera
    /// going away underneath it.
    private var isEnabled: Bool { isRunning || isCameraRunning }

    var body: some View {
        Button(action: onToggle) {
            Text(isRunning ? "Stop Game" : "Start Game")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(GameToggleButtonStyle(isRunning: isRunning, isEnabled: isEnabled))
    }
}

/// `PrimitiveButtonStyle`, not `ButtonStyle` — see `RiftButtonBody` in
/// `RiftboundTheme.swift` for the full reasoning. Short version: a real
/// `Button`'s `configuration.isPressed` can flip true and back to false
/// within one SwiftUI update on a fast, light tap, which sometimes skipped
/// the "pressed" render entirely — a slow deliberate click bounced, a quick
/// tap didn't. `PrimitiveButtonStyle` takes over the tap gesture so the
/// bounce runs as two *scheduled* phases instead, guaranteed to both render
/// regardless of how fast the physical tap was.
private struct GameToggleButtonStyle: PrimitiveButtonStyle {
    let isRunning: Bool
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        GameToggleButtonBody(configuration: configuration, isRunning: isRunning, isEnabled: isEnabled)
    }
}

private struct GameToggleButtonBody: View {
    let configuration: PrimitiveButtonStyleConfiguration
    let isRunning: Bool
    let isEnabled: Bool
    @State private var isHovering = false
    @State private var pulse: CGFloat = 1

    private var fillColor: Color {
        guard isEnabled else { return RiftboundPalette.disabledHighlightOverlay }
        guard isRunning else { return RiftboundPalette.primaryButton }
        return RiftboundPalette.disabledHighlightOverlay.opacity(RiftboundPalette.disabledComponentOpacity)
    }

    // Smaller magnitudes than `RiftButtonBody`'s: this button is full-width,
    // so the same percentage scale moves its edges by a lot more in
    // absolute pixels and risks visibly clipping against the column's
    // padding at the same intensity as a compact Back/Next button.
    private var hoverScale: CGFloat {
        guard isEnabled, isHovering else { return 1 }
        return 1.04
    }

    var body: some View {
        configuration.label
            .font(RiftboundFont.heading)
            .foregroundStyle(isRunning && isEnabled ? RiftboundPalette.dangerButton : RiftboundPalette.regularText)
            .padding(.vertical, 9)
            .glassEffect(
                .regular.tint(fillColor).interactive(),
                in: RoundedRectangle(cornerRadius: RiftboundLayout.buttonCornerRadius, style: .continuous)
            )
            // `bounce()` changes `pulse` in the same update `trigger()`
            // flips `isRunning` in, and `.animation(_:value:)` doesn't
            // scope itself to only the value it watches — it applies its
            // curve to *every* animatable change in that commit. Without
            // this, the bouncy spring meant for the scale was also
            // grabbing the label/fill colour swap, so Start Game visibly
            // crossfaded through Stop Game's red on the way to its own
            // bounce instead of just changing. Scoping the override to
            // *this* subtree, below `.scaleEffect`, keeps the snap local
            // to color/text without touching the scale's own animation.
            .transaction(value: isRunning) { $0.animation = nil }
            .scaleEffect(pulse * hoverScale)
            .animation(.bouncy(duration: 0.32, extraBounce: 0.25), value: isHovering)
            // The second phase of `bounce()` is the "click" moment — a
            // spring that overshoots on the way back rather than snapping
            // straight to size. Settles faster and overshoots less than
            // the hover spring above, and kept identical to
            // `RiftButtonBody`'s click spring: this sits in the same
            // column as the buttons using that style, so a different
            // settle here would read as two kinds of button rather than
            // one family.
            .animation(.bouncy(duration: 0.34, extraBounce: 0.24), value: pulse)
            .onHover { isHovering = isEnabled && $0 }
            .contentShape(Rectangle())
            .onTapGesture {
                guard isEnabled else { return }
                bounce()
                configuration.trigger()
            }
            .riftComponentDisabled(!isEnabled)
    }

    /// Two scheduled phases, not one animation keyed off a live gesture
    /// state — see the type's doc comment. `asyncAfter` guarantees the down
    /// phase gets its own render before the up phase starts.
    private func bounce() {
        // Already shallower than the compact buttons' original dip, for
        // the full-width reason in `hoverScale`'s note above — now the
        // same 0.93 they settled on too, so the whole column clicks alike.
        pulse = 0.93
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            pulse = 1
        }
    }
}
