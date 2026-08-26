import SwiftUI

/// The accessibility settings in the View menu: text size, and whether
/// BonBon reads his instructions out loud.
///
/// In the menu bar rather than only inside the app's own toolbar menu
/// because that's where a Mac user looks for these, and because a menu
/// command is the only form of them Full Keyboard Access can reach without
/// a mouse — which matters more than usual for settings whose whole
/// audience is people who need the interface to meet them halfway.
///
/// The items themselves live in `AccessibilityMenuContent`, shared with the
/// in-app Help menu. Only the ⌘+/⌘−/⌘0 shortcuts are declared here: a
/// `keyboardShortcut` belongs to a real menu-bar command, and duplicating
/// it into the toolbar copy would register the same chord twice.
struct RiftboundAccessibilityCommands: Commands {
    @Binding var textSize: RiftboundTextSize

    var body: some Commands {
        // `.toolbar` is the View menu's own group, so this lands there
        // rather than in a menu of its own — these are view concerns and
        // don't warrant a top-level menu.
        CommandGroup(after: .toolbar) {
            AccessibilityMenuContent()

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
