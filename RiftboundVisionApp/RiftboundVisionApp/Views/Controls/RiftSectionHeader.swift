import SwiftUI

/// A control-column section title with its collapse chevron.
///
/// One type so the two sections can't drift into two slightly different
/// headers — the same duplication that once had the panel blue defined
/// three times.
struct RiftSectionHeader: View {
    let title: String
    @Binding var isExpanded: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(RiftboundFont.heading)
                .foregroundStyle(RiftboundPalette.regularText)
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(RiftboundPalette.regularText)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse \(title)" : "Expand \(title)")
        }
    }
}
