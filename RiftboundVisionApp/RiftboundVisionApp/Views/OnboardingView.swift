import SwiftUI

/// The welcome sheet: what BonBon is, an annotated tour of the window, and
/// the one caveat a player has to know before trusting anything it says.
///
/// Shown once on first launch and reachable afterwards from the toolbar's
/// Help menu. "Once" is deliberate — this is orientation, not a warning
/// that needs repeating, and a modal that greets you every launch is a
/// modal people learn to dismiss without reading, including the times it
/// matters.
///
/// The tour itself is one exported image rather than a stack of views
/// pointing at real controls. It's a picture *of* the app, so anything
/// built out of live views would be a second, drifting copy of the layout —
/// and the callout arrows only make sense against the composition they were
/// drawn over. The cost is that it needs re-exporting when the layout
/// changes, which is the honest trade.
///
/// **Why the PNG and not `Frame 131`.** That SVG — now an image set in
/// the asset catalogue alongside this PNG — is
/// the same design and renders sharper — its title and disclaimer are real
/// vector paths and the screenshot it embeds is 1512×1037, against this
/// PNG's 882×584 overall. It is not used because **it is missing all four
/// callout labels**: its content stops at x≈874 of an 882-wide viewBox, so
/// "Playmat", "Score Input", "Card Library" and "Track Steps" and their
/// descriptions are simply absent, and every arrow points at nothing. A
/// crisper picture that has lost its labels is worse than a soft one that
/// explains itself.
///
/// If that layer gets re-exported, `Frame 131` is the better asset and
/// this should switch to it — note that it also contains the heading and the
/// disclaimer, so `header` and `disclaimer` below would become duplicates
/// and should go at the same time.
struct OnboardingView: View {
    /// Dismisses the sheet. Held by the caller so the "seen it" flag and
    /// the presentation live in one place rather than being written from
    /// inside here.
    let onDismiss: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                Image("OnboardingGuide")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 28)
                    .accessibilityLabel(
                        """
                        A guide to the app window. The playmat overlay in the middle: \
                        match your camera to it. The score panel top right: track both \
                        players' points. The card library below it: tap a card on camera \
                        or search to see its details. The row along the bottom: your \
                        steps through a turn.
                        """
                    )

                disclaimer
                    .padding(.top, 24)

                Button("Start Playing") { onDismiss() }
                    .buttonStyle(RiftPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .padding(.top, 24)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(36)
        }
        .frame(width: 900, height: 760)
        .background(RiftboundPalette.mainBackground)
    }

    /// Title on the left, Close on the right — the same shape and the same
    /// Escape shortcut `CardDetailView` uses, so the two dismissable
    /// surfaces in the app behave identically rather than each inventing
    /// their own way out.
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Play with BonBon!")
                    .font(RiftboundFont.iconic2)
                    .foregroundStyle(RiftboundPalette.iconicText)
                    .fixedSize()

                Text("Learn Riftbound with me and your opponent!")
                    .font(RiftboundFont.heading)
                    .foregroundStyle(RiftboundPalette.regularText)
            }

            Spacer(minLength: 16)

            Button("Close", action: onDismiss)
                .buttonStyle(RiftSecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)
        }
    }

    /// Kept at the bottom and kept plain. BonBon reads cards with a vision
    /// model that is wrong sometimes, and a player who believes an
    /// incorrect verdict mid-game has a worse time than one who was told to
    /// check. Softening this would be the wrong kind of polish.
    private var disclaimer: some View {
        (
            Text("Disclaimer: ").font(RiftboundFont.heading)
            + Text("BonBon's card detection skill may be inaccurate, do double-check it first.")
                .font(RiftboundFont.body)
        )
        .foregroundStyle(RiftboundPalette.regularText)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    OnboardingView(onDismiss: {})
}
