//
//  RiftboundTheme.swift
//  RiftboundVisionApp
//
//  Created by Anthony Martin Hasurungan on 19/08/26.
//

import SwiftUI
import CoreText

/// The single source of truth for how this app looks — every colour,
/// every type size and every shared control style traced back to the
/// "Color Scheme and Typography" board and the V3 hi-fi mockup.
///
/// Before this file existed the palette was scattered as inline
/// `Color(red:green:blue:)` triples across `GameStateBar`, `ScoreTracker`
/// and `DetectedCardsPanel` — three literals that were all *meant* to be
/// the same panel blue and weren't quite. Naming the tokens is what makes
/// "match the reference" a checkable claim rather than an eyeball one.

// MARK: - Palette

/// Every swatch on the design board, named the way the board names it.
/// Nothing here is invented: if a colour isn't on the board it isn't in
/// this enum, which is what keeps a stray shade from creeping back in.
///
/// The values themselves live in `Assets.xcassets/Palette`, one colour set
/// per swatch, so the board can be re-pointed in Xcode's colour editor
/// without a code change — and so the swatches show up where a designer
/// looks for them. This enum is now purely the *naming* layer: it says
/// which role each swatch plays, which is the part that belongs in code.
enum RiftboundPalette {
    /// #10415E — the board's one blue. The window, and every panel that
    /// isn't explicitly recessed.
    static let mainBackground = Color("MainBackground")
    /// #0A496A — recessed surfaces: the control column, the score
    /// panels, the settings sheet.
    ///
    /// A swatch of its own, not `Scrim` over `mainBackground` as it was
    /// before the board grew one. The translucent version composited with
    /// whatever it happened to be drawn on, so the "same" recessed
    /// surface came out a different colour over the navy than it did over
    /// a panel — and being a darkening of the main colour, it could only
    /// ever read as *shadow*. An opaque swatch is one value everywhere
    /// and can sit slightly cooler than `mainBackground` rather than
    /// merely darker.
    static let secondaryBackground = Color("SecondaryBackground")
    /// #10415E — shadow/stroke for elements, and the dark text on a lit
    /// gold pip. Shares the blue with `mainBackground`: the board no longer
    /// carries a separate element shadow, and the panels that used one are
    /// bounded by `elementStroke` instead.
    static let elementShadow = Color("MainBackground")
    /// #A36F18 — primary buttons, the Player/Opponent caption bar, the −/+
    /// stepper strip.
    static let primaryButton = Color("PrimaryButton")
    /// #CEA73F — highlight overlay. Score numerals' backing, the active
    /// phase pip, the selected detection box.
    static let highlightOverlay = Color("HighlightOverlay")
    /// #D5A250 — playmat overlay. The zone frames drawn over the camera
    /// feed, and a recognized card's detection box.
    static let playmatOverlay = Color("PlaymatOverlay")
    /// #D9BC87 — element stroke. Card-art borders, panel outlines.
    static let elementStroke = Color("ElementStroke")
    /// #FFF2D6 — the display numerals and titles. The board carries one
    /// cream, so this and `regularText` are the same swatch; they stay
    /// separately named because they are separate roles and only one of
    /// them would move if the board grew a second cream.
    static let iconicText = Color("RegularText")
    /// #FFF2D6 — regular text. Everything at 15pt.
    static let regularText = Color("RegularText")
    /// #545454 — disabled highlight overlay. A disabled button's fill, a
    /// disabled phase pip.
    static let disabledHighlightOverlay = Color("DisabledHighlightOverlay")
    /// #CBCBCB — disabled element stroke.
    static let disabledElementStroke = Color("DisabledElementStroke")
    /// #A32A1D — not on the board; there is no "stop/destructive" swatch in
    /// the mockup or the palette board. Matched to `primaryButton`'s
    /// brightness (red channel 0xA3) so it still reads as part of the same
    /// warm palette rather than a system alert red. Used as the *text*
    /// colour on `GameToggleButton`'s Stop Game state — the fill there
    /// stays the ordinary grey, so this is a colour accent, not an alarm.
    static let dangerButton = Color("DangerButton")
    /// #FFFFFF — pure white. For labels that sit on a filled control
    /// rather than on the board: the phase pips' letters, and the
    /// developer overlays drawn straight onto the camera picture, which
    /// have to stay legible over an arbitrary photograph.
    ///
    /// Text *on the board* is `regularText`'s cream. The distinction is
    /// the point — cream over the pips' #A36F18 reads as stained rather
    /// than as a label.
    static let pureWhite = Color("PureWhite")
    /// #000000 at 20% — the board's only darkening value. Recessed fills
    /// and the plate behind overlay text.
    static let scrim = Color("Scrim")
    /// #000000 at 55% — not on the board. `scrim` reads correctly for a
    /// recessed panel behind text, but the guided tour needs the *rest of
    /// the window* to visibly stop being the thing in focus while one
    /// region is spotlit; 20% didn't read as "the app just dimmed," it
    /// read as a faint tint. Same black `scrim` already uses, more of it,
    /// for the one place the board's single darkening value wasn't dark
    /// enough — see `TourSpotlightOverlay` in `AppTour.swift`.
    static let tourScrim = Color("TourScrim")

    /// The board carries the last two swatches twice, once at full and
    /// once at 50%. That second pair isn't a different colour, it's the
    /// same colour under the opacity rule below — so it's expressed as the
    /// rule, not as two more constants that could drift.
    static let disabledComponentOpacity: Double = 0.5
}

// MARK: - Typography

/// Sora, at the sizes the board specifies and no others.
///
/// The board gives four roles: body, subheading and heading all sit at
/// 15pt and are told apart by weight alone; "Iconics 2" is 50pt and
/// "Iconics" is 80pt. That's deliberately a very short scale, so any
/// `.font(.title)`/`.font(.caption)` left in a view is a deviation, not a
/// judgement call — which is why those are all gone from the UI now.
///
/// The roles themselves live on `RiftFontRole`, and views ask for them
/// with `.riftFont(.body)` rather than a baked-in `Font` constant. This
/// type is now just the *face loader* — the part that turns a size and a
/// weight into a real Sora face. There are deliberately no `static let`
/// role constants here any more: a `Font` resolved at file scope can't see
/// the player's text size setting, so every call site holding one would
/// have silently opted out of it. See `RiftboundTextScale.swift`.
enum RiftboundFont {
    /// Static instances are registered under their PostScript names.
    /// `Font.custom("Sora", …).weight(…)` would *look* tidier but silently
    /// resolves to Regular for every weight when the family is shipped as
    /// separate static faces, which is exactly what happened before this
    /// was pinned per-face.
    private static func face(_ weight: Font.Weight) -> String {
        switch weight {
        case .regular, .light, .thin, .ultraLight: return "Sora-Regular"
        case .medium, .semibold: return "Sora-SemiBold"
        case .heavy, .black: return "Sora-ExtraBold"
        default: return "Sora-Bold"
        }
    }

    /// Falls back to the system rounded face if Sora didn't register — a
    /// preview or a unit test has no app bundle to load it from, and a
    /// missing font should mean "slightly wrong type", not a blank screen.
    static func sora(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard RiftboundFontLoader.isSoraAvailable else {
            return .system(size: size, weight: weight, design: .rounded)
        }
        return .custom(face(weight), size: size)
    }
}

/// Registers the bundled Sora faces with Core Text.
///
/// `ATSApplicationFontsPath` in Info.plist already does this for the built
/// app, but it does nothing for SwiftUI previews, which load the view
/// without the app's bundle layout. Registering again is harmless — Core
/// Text reports "already registered" and we ignore it — and it means the
/// canvas shows the real type instead of the fallback.
enum RiftboundFontLoader {
    /// The four bundled faces, by PostScript name.
    private static let faceNames = ["Sora-Regular", "Sora-SemiBold", "Sora-Bold", "Sora-ExtraBold"]

    /// Registration happens *inside* this initializer rather than in a
    /// separate method that assigns to a `static var`.
    ///
    /// Under Swift 6's strict concurrency a mutable static is nonisolated
    /// global shared state and won't compile. A `static let` is fine:
    /// it's immutable, `Bool` is `Sendable`, and Swift runs the
    /// initializer exactly once via `swift_once`, which is also the
    /// run-once guarantee font registration wants anyway.
    static let isSoraAvailable: Bool = {
        let urls = bundledFontURLs()
        for url in urls {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                // "Already registered" is expected and harmless when
                // `ATSApplicationFontsPath` also picked the file up.
                print("ℹ️ Sora: \(url.lastPathComponent) — \(error?.takeRetainedValue().localizedDescription ?? "not registered")")
            }
        }

        let available = faceNames.allSatisfy(isRegistered)
        if available {
            print("✅ Sora registered (\(urls.count) file\(urls.count == 1 ? "" : "s")).")
        } else {
            print("""
            ⚠️ Sora NOT available — falling back to the system face.
               Found \(urls.count) .ttf file(s) in the bundle.
               Bundle resources: \(Bundle.main.resourceURL?.path ?? "nil")
            """)
        }
        return available
    }()

    /// Every `.ttf` in the app bundle, however it was copied in.
    ///
    /// Three lookups because the answer depends on how the `Fonts` folder
    /// was added to the Xcode project, which isn't something this code can
    /// see or control:
    ///
    ///  - **Folder reference** (blue folder) → `Contents/Resources/Fonts/`,
    ///    which is what `ATSApplicationFontsPath = Fonts` expects.
    ///  - **Synchronized group or plain group** (the default when you drag
    ///    a folder in) → Xcode *flattens* it, so the faces land loose in
    ///    `Contents/Resources/` and the `Fonts` subdirectory never exists.
    ///    `ATSApplicationFontsPath` then points at nothing and silently
    ///    registers nothing.
    ///
    /// Rather than depend on getting the project setting right, this looks
    /// in both places and then walks the bundle as a last resort. Font
    /// loading failing quietly and leaving the whole app in a fallback
    /// face is worth a few extra file lookups at launch.
    private static func bundledFontURLs() -> [URL] {
        if let inFolder = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts"), !inFolder.isEmpty {
            return inFolder
        }
        if let flattened = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil), !flattened.isEmpty {
            return flattened
        }
        guard let root = Bundle.main.resourceURL,
              let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension.lowercased() == "ttf" }
    }

    /// Core Text never *fails* to make a font — it substitutes a default
    /// face for an unknown name — so the only way to tell "Sora loaded"
    /// from "you're looking at Helvetica" is to ask the resolved font what
    /// it actually is.
    private static func isRegistered(_ postScriptName: String) -> Bool {
        let descriptor = CTFontDescriptorCreateWithNameAndSize(postScriptName as CFString, 15)
        let font = CTFontCreateWithFontDescriptor(descriptor, 15, nil)
        return (CTFontCopyPostScriptName(font) as String) == postScriptName
    }

    /// Forces the registration above to run now rather than lazily on the
    /// first `RiftboundFont` lookup. Called from the app's `init` so the
    /// first frame already has the real faces — otherwise it renders in
    /// the fallback and snaps on the next redraw.
    static func registerBundledFonts() {
        _ = isSoraAvailable
    }
}

// MARK: - The disabled rule

extension View {
    /// The board's one explicit interaction rule, written down once:
    /// "Only reduce opacity by 50% if the WHOLE COMPONENT (button, phase
    /// description) is disabled, not just part of it."
    ///
    /// So dimming is applied at the container — a phase card, a button —
    /// and never to a label or icon inside a container that is itself
    /// still live. Where only *part* of something is inactive (an
    /// upcoming phase pip inside an active card) the disabled *colours*
    /// are used at full opacity instead.
    @ViewBuilder
    func riftComponentDisabled(_ isDisabled: Bool) -> some View {
        opacity(isDisabled ? RiftboundPalette.disabledComponentOpacity : 1)
            .allowsHitTesting(!isDisabled)
    }
}

// MARK: - Shared controls

/// Solid gold action — "Next" while it's the live step, "Start Turn",
/// "End Turn". Disabled swaps the fill to #545454 *and* dims the whole
/// button, which is the rule above applied to a component that genuinely
/// is entirely off.
struct RiftPrimaryButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RiftButtonBody(configuration: configuration, emphasis: .filled(RiftboundPalette.primaryButton))
    }
}

/// How much weight a button carries. Passed to the shared body rather
/// than each style rebuilding a label — see `RiftButtonBody`.
private enum RiftButtonEmphasis {
    case filled(Color)
    /// Outline and text in `primaryButton` over untinted glass, no fill.
    /// For the subordinate half of a pair where both buttons are live and
    /// equally pressable — the distinction has to survive *both* being
    /// enabled, which is exactly what a second filled colour can't do
    /// here: the only other fill in the palette is the one disabled
    /// already uses.
    ///
    /// Deliberately the *same* colour as its filled partner rather than
    /// `elementStroke`'s lighter gold. Borrowing the fill colour makes
    /// the pair read as one control in two weights — outlined and filled
    /// — where a second, lighter gold read as a third kind of button and
    /// put the quiet one at *higher* contrast than the loud one.
    case outlined
}

/// The quieter of the two buttons in the bottom row. The mockup pairs a
/// gold button with a grey one and swaps which is which depending on what
/// the step actually wants you to press, so this is a real style rather
/// than "the primary one, disabled".
struct RiftSecondaryButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RiftButtonBody(configuration: configuration, emphasis: .filled(RiftboundPalette.disabledHighlightOverlay))
    }
}

/// Outlined in `primaryButton`, the same colour its filled partner uses
/// as a fill — the quiet half of a live pair.
///
/// Use this, not `RiftSecondaryButtonStyle`, whenever the quieter button
/// can also be *disabled*. That style's enabled fill is
/// `disabledHighlightOverlay`, the same colour disabled paints with, so
/// the two states differ only by the 50% dim — on Back, which disables
/// itself at the first phase of a turn, "quieter" and "unavailable" would
/// have been near-indistinguishable. An outline is unmistakably neither.
struct RiftOutlineButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RiftButtonBody(configuration: configuration, emphasis: .outlined)
    }
}

/// Shared body for both button styles.
///
/// This is a nested `View` rather than the style building the label
/// directly, because `@Environment(\.isEnabled)` read from inside a
/// `ButtonStyle` struct does not track — `makeBody` isn't a view body, so
/// the value is captured once and a button that later becomes disabled
/// keeps drawing itself gold. Reading it from a real `View` is what makes
/// the disabled fill and the 50% dim actually follow `.disabled(…)`.
///
/// The fill is real Liquid Glass (`.glassEffect`, macOS 26+), tinted with
/// the button's own colour rather than drawn as a flat `RoundedRectangle`.
///
/// `PrimitiveButtonStyle`, not `ButtonStyle`: a light, fast click on a real
/// `Button` could flip `configuration.isPressed` true and back to false
/// within the same SwiftUI update, so the "pressed" frame this used to
/// drive the bounce off of sometimes never actually got rendered — a slow,
/// deliberate press-and-hold showed the animation, a quick tap didn't.
/// `PrimitiveButtonStyle` hands over the whole gesture, so the bounce is
/// driven by `pulse`, a plain `@State` stepped through two *scheduled*
/// phases (down, then a spring back up after a fixed delay) every time
/// `onTapGesture` fires — which is guaranteed to happen exactly once per
/// completed tap, at a pace this code controls rather than however fast
/// the click physically was.
private struct RiftButtonBody: View {
    let configuration: PrimitiveButtonStyleConfiguration
    let emphasis: RiftButtonEmphasis
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false
    @State private var pulse: CGFloat = 1

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: RiftboundLayout.buttonCornerRadius, style: .continuous)
    }

    /// `nil` means draw no tint at all — the outlined style's glass stays
    /// untinted so the board shows through it.
    private var fill: Color? {
        // Disabled looks the same whichever style asked for it. Two
        // different "off" appearances would be two things to learn for a
        // state that means one thing.
        guard isEnabled else { return RiftboundPalette.disabledHighlightOverlay }
        switch emphasis {
        case .filled(let color): return color
        case .outlined: return nil
        }
    }

    private var isOutlined: Bool {
        guard isEnabled, case .outlined = emphasis else { return false }
        return true
    }

    var body: some View {
        configuration.label
            .riftFont(.heading)
            .foregroundStyle(isOutlined ? RiftboundPalette.primaryButton : RiftboundPalette.regularText)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .glassEffect(glass, in: shape)
            .overlay {
                if isOutlined {
                    shape.stroke(RiftboundPalette.primaryButton, lineWidth: 1.5)
                }
            }
            // Some callers relabel the same button as a direct result of
            // clicking it — Next becomes End Turn once the click it just
            // handled lands the phase on `.action`. That label swap and
            // `bounce()`'s `pulse` change land in the same update, and
            // `.animation(_:value:)` doesn't scope itself to only the value
            // it names — it grabs *every* animatable change in that commit.
            // Unscoped like the label change was, the bouncy spring meant
            // for the scale visibly crossfaded "Next" through "End Turn"
            // instead of just relabelling. This unconditional override
            // (below, applied to the styled label; `.scaleEffect` stays
            // outside it) forces the label/fill to always snap, regardless
            // of which external value caused the change — unlike
            // `GameToggleButton`'s equivalent fix, this body doesn't know
            // which value a given caller's label depends on to name it.
            .transaction { $0.animation = nil }
            .scaleEffect(pulse * (isHovering && isEnabled ? 1.08 : 1))
            .animation(.bouncy(duration: 0.32, extraBounce: 0.25), value: isHovering)
            // The second phase of `bounce()` is what reads as the "click"
            // — a spring that overshoots past full size on the way back
            // rather than snapping straight to it. Deliberately settles
            // faster and overshoots less than the hover spring above:
            // hover is ambient and can afford to be playful, but a click
            // is acknowledging something the player just did, and a long
            // wobble there reads as the button still deciding.
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

    /// Untinted for the outlined style, tinted for everything else.
    /// Split out because the two build different `Glass` values and an
    /// inline conditional inside `.glassEffect(_:in:)` reads as though
    /// the *shape* changes too, which it doesn't.
    private var glass: Glass {
        guard let fill else { return .regular.interactive() }
        return .regular.tint(fill).interactive()
    }

    /// Two scheduled phases, not one animation keyed off a live gesture
    /// state — see the type's doc comment for why. `asyncAfter` is what
    /// guarantees the down phase gets its own render before the up phase
    /// starts, regardless of how fast the tap that triggered this was.
    private func bounce() {
        // A shallower dip than the 0.88 this started at. The spring's
        // overshoot scales off how far it has to travel back, so easing
        // the dip tones the whole bounce down along with the timing
        // above — the two have to move together or the shorter spring
        // just makes the same large travel look abrupt.
        pulse = 0.93
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            pulse = 1
        }
    }
}

/// The "Auto-detect" switch. AppKit's stock switch is system-blue and
/// can't be tinted through `.toggleStyle(.switch)`, so it read as the one
/// piece of foreign chrome on the screen; this draws the mockup's gold
/// pill with the knob on the *trailing* side when on, matching the
/// reference.
struct RiftSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 10) {
                configuration.label
                Capsule()
                    .fill(configuration.isOn ? RiftboundPalette.highlightOverlay : RiftboundPalette.disabledHighlightOverlay)
                    .overlay(
                        Capsule().stroke(
                            configuration.isOn ? RiftboundPalette.elementStroke : RiftboundPalette.disabledElementStroke,
                            lineWidth: 1
                        )
                    )
                    // Knob on the **trailing** side when on.
                    //
                    // This was inverted, and the inversion was invisible in
                    // a still: gold fill said "on" while the knob sat left,
                    // which every switch on the platform reads as "off".
                    // The two halves of the control disagreed, so the state
                    // could only be worked out by toggling it and watching.
                    // Fill and knob now both mean the same thing.
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(RiftboundPalette.regularText)
                            .padding(2)
                    }
                    .frame(width: 42, height: 22)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The outlined container the bottom row is built from — "Start of Turn
/// Phases", "Do Your Turn!", "End Turn" are all this shape.
struct RiftPanelCard<Content: View>: View {
    var isActive: Bool
    /// Where the content sits once the card has been stretched to the
    /// row's height. The two wide cards hang their content from the top;
    /// "End Turn" is a single centred label.
    var alignment: Alignment = .topLeading
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            // `maxHeight: .infinity` *before* the background is what makes
            // all three cards in a row the same height — the fill and
            // stroke are drawn around the stretched frame, not around each
            // card's own content. Applying it outside instead leaves the
            // outline hugging the text, which is why "End Turn" came out
            // as a short box next to two tall ones.
            .frame(maxHeight: .infinity, alignment: alignment)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isActive ? RiftboundPalette.elementShadow.opacity(0.55) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isActive ? RiftboundPalette.elementStroke : RiftboundPalette.disabledElementStroke.opacity(0.55),
                        lineWidth: 1
                    )
            )
    }
}

/// The thin rule that links the three cards into one left-to-right flow in
/// the mockup. Decorative, so it's hidden from accessibility.
struct RiftFlowConnector: View {
    /// Long between cards, short between the A/B/C/D pips.
    var length: CGFloat = 22

    var body: some View {
        Rectangle()
            .fill(RiftboundPalette.disabledElementStroke.opacity(0.45))
            .frame(width: length, height: 1)
            .accessibilityHidden(true)
    }
}

// MARK: - Named artwork

/// The SVG set that shipped with the reference, addressed by name in one
/// place so a rename in the catalog is a single-line fix rather than a
/// hunt through string literals.
/// Shared measurements, so "the same width" is one number rather than the
/// same number typed in three places.
///
/// The card strip, the camera stage and the mascot panel are three bands of
/// one column and must line up down both edges. They were each carrying
/// their own padding, which is how they drifted apart — the strip ran wider
/// than the camera it sat above.
enum RiftboundLayout {
    /// Horizontal inset for every band in the left column. One value, read
    /// by all three.
    static let columnInset: CGFloat = 24
    /// Vertical rhythm between those bands.
    static let bandSpacing: CGFloat = 12
    /// The control column's width. Fixed rather than proportional: it holds
    /// a fixed set of controls at a fixed type size, so letting it stretch
    /// only ever added empty space beside them.
    static let controlColumnWidth: CGFloat = 372
    /// Padding inside the control column's sections.
    static let controlColumnInset: CGFloat = 20

    /// Thumbnail size in the table strip.
    static let stripCardWidth: CGFloat = 96
    static let stripCardHeight: CGFloat = 134
    /// Width of the detail that opens beside a selected card. Derived from
    /// `stripCardWidth` rather than its own arbitrary number — a fixed 260
    /// (nearly 3x a thumbnail's 96) made the expanded slot balloon out of
    /// proportion with the rest of the row instead of reading as part of
    /// the same grid of cards.
    static let stripDetailWidth: CGFloat = stripCardWidth * 2

    static let cornerRadius: CGFloat = 8
    static let hairline: CGFloat = 2
    /// Corner radius shared by every `Rift*ButtonStyle` fill.
    static let buttonCornerRadius: CGFloat = 6
    /// Two lines of `RiftboundFont.body` at 15pt. The phase blurb runs one
    /// line for four of the five phases and two for Action ("Play cards
    /// from hand. Conquer and combat the battlefield with your units.") —
    /// without a reserved floor, Back/Next/End Turn shifted down a line's
    /// height only while the Action Phase was showing, which reads as the
    /// whole panel twitching every time a turn reaches it.
    static let phaseBlurbMinHeight: CGFloat = 44

    /// The "Type"/"Cost"/"Ability" label column in a card's attribute
    /// list. One number rather than a literal in each row, because the
    /// inline strip panel and the Card Library page both draw the list and
    /// a drifting label width is the kind of difference that only shows up
    /// when you happen to see the two side by side.
    /// An extra blank line's worth of space, added *on top of* a stack's
    /// own spacing where a sidebar section changes subject — between the
    /// sentence explaining a panel and the controls it explains.
    ///
    /// Roughly one line of 15pt body text. Expressed as padding rather
    /// than by widening the stack's `spacing`, because it applies at one
    /// seam rather than between every pair of rows.
    static let paragraphBreak: CGFloat = 18

    static let cardAttributeLabelWidth: CGFloat = 62
    /// The keyword pill in a card's Ability line ("ASSAULT"). Tighter than
    /// `buttonCornerRadius` on purpose: at chip height a button's radius
    /// rounds most of the shape away and it stops reading as a printed
    /// keyword box.
    static let keywordChipCornerRadius: CGFloat = 4
}

enum RiftboundArt {
    static let ready = "Ready"
    static let exhaustOrPay = "Exhaust or Pay"
    static let recycleARune = "Recycle a Rune"
    static let draw = "Draw"
    /// The resize handle for the playmat overlay.
    ///
    /// Unlike the four above — multi-colour game symbols that carry their
    /// own art — this is a single-colour control glyph, so its image set is
    /// marked `template` rather than `original`. That means it takes
    /// `.foregroundStyle(…)` like an SF Symbol does and can sit in the
    /// palette with everything else, instead of being locked to the white
    /// the SVG happens to be filled with. Use `.renderingMode(.original)`
    /// at a call site that really does want it white regardless.
    static let resizeOverlay = "ResizeOverlay"

    static func unit(active: Bool) -> String { active ? "Unit (Active)" : "Unit (Disabled)" }
    static func spell(active: Bool) -> String { active ? "Spell (Active)" : "Spell (Disabled)" }
    static func battlefield(active: Bool) -> String { active ? "Battlefield (Active)" : "Battlefield (Disabled)" }
}
