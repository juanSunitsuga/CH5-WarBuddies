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
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(RiftboundPalette.regularText)
                Text("Card Library")
                    .font(RiftboundFont.heading)
                    .foregroundStyle(RiftboundPalette.regularText)
            }
            .frame(height: RiftboundLayout.stripCardHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open the card library")
    }
}
