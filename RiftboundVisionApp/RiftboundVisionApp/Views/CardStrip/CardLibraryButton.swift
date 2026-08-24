import SwiftUI

/// Opens the full catalogue.
///
/// Pinned to the trailing end of the strip rather than scrolling with it:
/// the strip shows what's *on the table*, and this is the way to reach a
/// card that isn't. Somewhere you have to scroll to find would be a strange
/// home for "look at everything".
struct CardLibraryButton: View {
    let action: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(RiftboundPalette.regularText)
            // A real gold pill, not plain text under the icon — the
            // reference draws this as the same button style as "Start
            // Game"/"Next", not a label. Matching that keeps every
            // pressable gold button in the app looking like one family.
            Button("Library", action: action)
                .buttonStyle(RiftPrimaryButtonStyle())
        }
        // `maxHeight: .infinity` rather than a fixed height: the outer
        // `HStack` in `TableCardStrip` is `alignment: .top` (so card
        // thumbnails line up when the strip is full), which left this
        // sitting flush against the top of the taller empty-state row
        // instead of centred in it like the reference.
        .frame(maxHeight: .infinity, alignment: .center)
        .accessibilityLabel("Open the card library")
    }
}
