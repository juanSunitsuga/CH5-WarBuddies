import SwiftUI

/// "Text Size" in the View menu, with the ⌘+ / ⌘− / ⌘0 shortcuts every
/// other Mac app uses for the same job.
///
/// In the menu bar rather than only inside the app's own settings popover
/// because that's where a Mac user looks for it, and because a menu
/// command is the only form of this control VoiceOver and Full Keyboard
/// Access can reach without a mouse — which matters more than usual for a
/// setting whose whole audience is people who need the interface to meet
/// them halfway.
struct RiftboundTextSizeCommands: Commands {
    @Binding var textSize: RiftboundTextSize

    var body: some Commands {
        // `.toolbar` is the View menu's own group, so this lands there
        // rather than in a menu of its own — text size is a view concern
        // and doesn't warrant its own top-level menu.
        CommandGroup(after: .toolbar) {
            // Buttons rather than a `Picker`, matching `DiagnosticsMenu` —
            // a `Picker` in a menu drew an inert row there, and there's no
            // reason to think this context is different enough to risk it.
            // Drawing the checkmark by hand is the whole cost.
            Menu("Text Size") {
                ForEach(RiftboundTextSize.allCases) { size in
                    Button {
                        textSize = size
                    } label: {
                        if size == textSize {
                            Label(size.title, systemImage: "checkmark")
                        } else {
                            Text(size.title)
                        }
                    }
                }
            }

            Button("Larger Text") {
                if let larger = textSize.larger { textSize = larger }
            }
            .keyboardShortcut("+", modifiers: .command)
            // Disabled at the ceiling rather than silently doing nothing,
            // so the menu says whether there's anywhere left to go.
            .disabled(textSize.larger == nil)

            Button("Smaller Text") {
                if let smaller = textSize.smaller { textSize = smaller }
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(textSize.smaller == nil)

            Button("Actual Size") {
                textSize = .standard
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(textSize == .standard)

            Divider()
        }
    }
}
