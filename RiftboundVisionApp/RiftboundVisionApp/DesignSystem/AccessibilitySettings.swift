import SwiftUI

/// The player's accessibility choices, kept in one place.
///
/// macOS has no Dynamic Type control of its own the way iOS does — the
/// system setting is per-app on iOS and simply absent here — so a game meant
/// to be read from across a table has to offer its own. That is what
/// `textSize` is: not a preference for people who like big text, but the
/// difference between a card's ability being legible at arm's length and
/// not.
///
/// Stored in `@AppStorage` rather than `@State` because an accessibility
/// choice that resets when the window closes is worse than not offering it:
/// someone who needs it needs it every session, and having to re-find the
/// setting each time is its own barrier.
struct AccessibilitySettings {
    @AppStorage("accessibility.textSize") var textSize: TextSize = .standard
    @AppStorage("accessibility.reduceMotion") var reduceMotion: Bool = false

    init() {}
}

/// How much larger than the design's own scale to draw text.
///
/// Backed by SwiftUI's `DynamicTypeSize` rather than a raw multiplier,
/// because `Font.custom(_:size:relativeTo:)` already knows how to scale
/// against it. That means every existing `RiftboundFont` call site scales
/// without being touched — the alternative was threading a multiplier
/// through several hundred `.font(...)` calls, which is how one gets missed
/// and a single label stays small.
enum TextSize: String, CaseIterable, Identifiable {
    case standard
    case large
    case larger
    case largest

    var id: String { rawValue }

    /// What the control says.
    var title: String {
        switch self {
        case .standard: return "Standard"
        case .large:    return "Large"
        case .larger:   return "Larger"
        case .largest:  return "Largest"
        }
    }

    /// Roughly how much bigger, for the player rather than for the compiler.
    var subtitle: String {
        switch self {
        case .standard: return "The size the game is designed at."
        case .large:    return "About a fifth larger."
        case .larger:   return "About half again."
        case .largest:  return "As large as the layout takes."
        }
    }

    /// Deliberately stops at `.accessibility1` rather than running to
    /// `.accessibility5`. This is a fixed-width control column beside a
    /// camera picture, and past this point the layout stops being a layout —
    /// the phase pips wrap, the score numerals collide, and a player is
    /// worse off than at a size they can actually read *and* navigate. An
    /// honest ceiling beats a setting that technically exists and produces
    /// an unusable screen.
    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .standard: return .large          // SwiftUI's own default
        case .large:    return .xLarge
        case .larger:   return .xxLarge
        case .largest:  return .accessibility1
        }
    }
}
