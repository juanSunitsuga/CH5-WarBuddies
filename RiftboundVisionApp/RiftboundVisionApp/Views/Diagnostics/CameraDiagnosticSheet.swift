import SwiftUI
import AppKit

/// The camera device dump, for "Continuity Camera works elsewhere but
/// this app can't see it".
struct CameraDiagnosticSheet: View {
    let report: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Camera Diagnostic")
                .riftFont(.heading)
                .foregroundStyle(RiftboundPalette.regularText)
            ScrollView {
                // Monospaced on purpose — this is a device dump, and
                // column alignment is the point. Sora is a proportional
                // face, so the theme scale doesn't apply here.
                Text(report)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(RiftboundPalette.regularText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Copy") {
                    if true {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(report, forType: .string)
                    }
                }
                .buttonStyle(RiftSecondaryButtonStyle())
                Spacer()
                Button("Close") { onClose() }
                    .buttonStyle(RiftPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 600, minHeight: 400)
        .background(RiftboundPalette.mainBackground)
    }
}
