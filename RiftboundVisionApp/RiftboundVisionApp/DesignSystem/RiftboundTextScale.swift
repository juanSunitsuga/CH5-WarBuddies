import SwiftUI

/// How large the app draws its text, as an explicit app preference rather
/// than a system one.
///
/// **Why this exists at all, rather than Dynamic Type.** On iOS the whole
/// job would be `Font.custom(_:size:relativeTo:)` plus the system's text
/// size slider, and the app would inherit accessibility sizing for free.
/// On macOS both halves of that are inert: text renders at the same point
/// size at every `DynamicTypeSize`, and that holds for `relativeTo:` custom
/// fonts *and* for semantic styles like `.body`. That was measured on this
/// machine before this file was written, not assumed — rendering the same
/// string at `.xSmall` through `.accessibility5` produced byte-identical
/// dimensions every time. `.dynamicTypeSize(…)` compiles here and does
/// nothing, which is the dangerous kind of wrong: the accessible-looking
/// code ships and no text ever grows.
///
/// So "larger text" on this platform has to be a preference the app owns
/// and applies itself, which is exactly what Mail, Notes and Xcode each
/// ship their own control for.
enum RiftboundTextSize: String, CaseIterable, Identifiable, Sendable {
    case standard
    case large
    case larger
    case largest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "Standard"
        case .large: return "Large"
        case .larger: return "Larger"
        case .largest: return "Largest"
        }
    }

    /// Multiplier applied to the board's own point sizes.
    ///
    /// Stops at 1.5 rather than iOS's ~2.4x ceiling because this window has
    /// a hard floor of 1160×675 and a fixed-width control column: past
    /// roughly 1.5 the score numerals and the turn buttons stop fitting
    /// beside each other, and a setting that visibly breaks the layout is
    /// worse than one that stops short of it. 1.5 on 15pt body is 22.5pt,
    /// which is a genuinely large size to read a table across.
    var scale: CGFloat {
        switch self {
        case .standard: return 1.0
        case .large: return 1.15
        case .larger: return 1.3
        case .largest: return 1.5
        }
    }

    /// The next size up, or `nil` at the ceiling — drives ⌘+ and lets the
    /// menu item disable itself rather than silently doing nothing.
    var larger: RiftboundTextSize? {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self), index + 1 < all.count else { return nil }
        return all[index + 1]
    }

    /// The next size down, or `nil` at the floor. Drives ⌘−.
    var smaller: RiftboundTextSize? {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self), index > 0 else { return nil }
        return all[index - 1]
    }
}

// MARK: - Environment

private struct RiftboundTextScaleKey: EnvironmentKey {
    /// 1.0, not the stored preference: an `EnvironmentKey` default has to
    /// be a constant, and a view rendered outside the app (a preview, a
    /// snapshot test) should draw at the board's own sizes.
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    /// Multiplier every `riftFont`/`riftIcon` applies. Injected once at the
    /// window root; nothing else should set it.
    var riftTextScale: CGFloat {
        get { self[RiftboundTextScaleKey.self] }
        set { self[RiftboundTextScaleKey.self] = newValue }
    }
}

// MARK: - Type roles

/// The board's four type roles, as a value a view can ask for rather than
/// a `Font` constant it bakes in.
///
/// This replaces the `static let body`/`heading`/… constants that used to
/// live on `RiftboundFont`. That indirection is the entire point: a
/// `Font` resolved at file scope is fixed forever, so any call site still
/// holding one would quietly opt out of the text size setting. Roles are
/// resolved per-view, at render time, against the current scale.
enum RiftFontRole: Equatable, Sendable {
    /// 15pt Regular — running copy, phase blurbs, attribute values.
    case body
    /// 15pt SemiBold — captions that label something ("Current Turn").
    case subheading
    /// 15pt Bold — section titles, card names, button labels.
    case heading
    /// 50pt Bold — "Iconics 2" on the board: the turn banner.
    case iconic2
    /// 80pt Bold — "Iconics" on the board: the score numerals.
    case iconic
    /// A size the board doesn't name. For the few places that predate the
    /// four roles above and sit at their own size — they still scale, they
    /// just don't pretend to be one of the named roles.
    case custom(CGFloat, Font.Weight)

    var baseSize: CGFloat {
        switch self {
        case .body, .subheading, .heading: return 15
        case .iconic2: return 50
        case .iconic: return 80
        case .custom(let size, _): return size
        }
    }

    var weight: Font.Weight {
        switch self {
        case .body: return .regular
        case .subheading: return .semibold
        case .heading, .iconic2, .iconic: return .bold
        case .custom(_, let weight): return weight
        }
    }

    /// Display type takes a gentler curve than running copy.
    ///
    /// The score numerals are already 80pt; at a flat 1.5 they'd be 120pt
    /// and two of them stop fitting side by side in a 372pt column. They're
    /// also the text least in need of the help — someone who can't read
    /// 15pt body can already read an 80pt numeral. So the roles that exist
    /// to be *big* scale at 45% of the rate the roles that exist to be
    /// *read* do.
    private var isDisplay: Bool {
        switch self {
        case .iconic, .iconic2: return true
        case .body, .subheading, .heading, .custom: return false
        }
    }

    func font(scale: CGFloat) -> Font {
        let effective = isDisplay ? 1 + (scale - 1) * 0.45 : scale
        return RiftboundFont.sora(baseSize * effective, weight)
    }
}

// MARK: - Modifiers

private struct RiftFontModifier: ViewModifier {
    let role: RiftFontRole
    @Environment(\.riftTextScale) private var scale

    func body(content: Content) -> some View {
        content.font(role.font(scale: scale))
    }
}

/// Scales an SF Symbol alongside the text it sits with.
///
/// Symbols need a *system* font — handing one a Sora face renders the
/// substitution glyph — so this can't just go through `RiftFontRole`.
/// Icons scale for the same reason the text does: a 12pt chevron beside
/// 22pt body reads as a rendering bug, and the button around it stops
/// being a comfortable click target.
private struct RiftIconModifier: ViewModifier {
    let size: CGFloat
    let weight: Font.Weight
    @Environment(\.riftTextScale) private var scale

    func body(content: Content) -> some View {
        content.font(.system(size: size * scale, weight: weight))
    }
}

extension View {
    /// The board's type, at whatever size the player has asked for.
    /// Use this everywhere instead of `.font(…)`.
    func riftFont(_ role: RiftFontRole) -> some View {
        modifier(RiftFontModifier(role: role))
    }

    /// An SF Symbol that grows with the text setting.
    func riftIcon(size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(RiftIconModifier(size: size, weight: weight))
    }
}

extension Text {
    /// `Text`-returning font application, for the one shape the view
    /// modifier above can't serve: two differently-weighted runs joined
    /// with `Text + Text` into a single wrapping paragraph. That operator
    /// needs both sides to still *be* `Text`, and a `ViewModifier` erases
    /// them to `some View`.
    ///
    /// The scale is a parameter rather than an `@Environment` read because
    /// a `Text` extension isn't a view body and has no environment to read
    /// from. Callers hold `@Environment(\.riftTextScale)` themselves and
    /// pass it in — which is why this is deliberately awkward to reach for:
    /// `.riftFont(_:)` is the one to use everywhere else.
    func riftFont(_ role: RiftFontRole, scale: CGFloat) -> Text {
        font(role.font(scale: scale))
    }
}
