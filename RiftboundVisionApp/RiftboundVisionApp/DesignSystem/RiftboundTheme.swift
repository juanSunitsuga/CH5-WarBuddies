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
enum RiftboundPalette {
    /// #1D3145 — shadow/stroke for elements. Also the fill behind the
    /// Unit/Spell/Battlefield chip art, which is drawn on this blue.
    static let elementShadow = Color(hex: 0x1D3145)
    /// #10415E — main background. The window, the header, the bottom bar.
    static let mainBackground = Color(hex: 0x10415E)
    /// #0A496A — secondary background. The right-hand Score/Card Library
    /// column, so it separates from the main field without a divider.
    static let secondaryBackground = Color(hex: 0x0A496A)
    /// #A36F18 — primary buttons. Also the Player/Opponent caption bar and
    /// the −/+ stepper strip, which are the same "solid actionable gold".
    static let primaryButton = Color(hex: 0xA36F18)
    /// #CEA73F — highlight overlay. Score numerals' backing, the active
    /// phase pip, the selected detection box.
    static let highlightOverlay = Color(hex: 0xCEA73F)
    /// #C5A560 — playmat overlay. The zone frames drawn over the camera
    /// feed, and a recognized card's detection box.
    static let playmatOverlay = Color(hex: 0xC5A560)
    /// #D9BC87 — element stroke. Card-art borders, panel card outlines.
    static let elementStroke = Color(hex: 0xD9BC87)
    /// #FFE0AD — iconic text. The 50pt/80pt display numerals and titles.
    static let iconicText = Color(hex: 0xFFE0AD)
    /// #FFF2D6 — regular text. Everything at 15pt.
    static let regularText = Color(hex: 0xFFF2D6)
    /// #545454 — disabled highlight overlay. A disabled button's fill, a
    /// disabled phase pip.
    static let disabledHighlightOverlay = Color(hex: 0x545454)
    /// #CBCBCB — disabled element stroke.
    static let disabledElementStroke = Color(hex: 0xCBCBCB)

    /// The board carries the last two swatches twice, once at full and
    /// once at 50%. That second pair isn't a different colour, it's the
    /// same colour under the opacity rule below — so it's expressed as the
    /// rule, not as two more constants that could drift.
    static let disabledComponentOpacity: Double = 0.5
}

extension Color {
    /// 0xRRGGBB, so a token can be written the way the board writes it and
    /// diffed against it by eye.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - Typography

/// Sora, at the sizes the board specifies and no others.
///
/// The board gives four roles: body, subheading and heading all sit at
/// 15pt and are told apart by weight alone; "Iconics 2" is 50pt and
/// "Iconics" is 80pt. That's deliberately a very short scale, so any
/// `.font(.title)`/`.font(.caption)` left in a view is a deviation, not a
/// judgement call — which is why those are all gone from the UI now.
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

    /// 15pt Regular — running copy, phase blurbs, attribute values.
    static let body = sora(15, .regular)
    /// 15pt SemiBold — captions that label something ("Current Turn").
    static let subheading = sora(15, .semibold)
    /// 15pt Bold — section titles ("Score", "Card Library"), card names,
    /// button labels, attribute labels.
    static let heading = sora(15, .bold)
    /// 50pt Bold — "Iconics 2" on the board: the turn banner.
    static let iconic2 = sora(50, .bold)
    /// 80pt Bold — "Iconics" on the board: the score numerals.
    static let iconic = sora(80, .bold)
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
struct RiftPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RiftButtonBody(configuration: configuration, enabledFill: RiftboundPalette.primaryButton)
    }
}

/// The quieter of the two buttons in the bottom row. The mockup pairs a
/// gold button with a grey one and swaps which is which depending on what
/// the step actually wants you to press, so this is a real style rather
/// than "the primary one, disabled".
struct RiftSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RiftButtonBody(configuration: configuration, enabledFill: RiftboundPalette.disabledHighlightOverlay)
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
private struct RiftButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let enabledFill: Color
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(RiftboundFont.heading)
            .foregroundStyle(RiftboundPalette.regularText)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isEnabled ? enabledFill : RiftboundPalette.disabledHighlightOverlay)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .riftComponentDisabled(!isEnabled)
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
    /// Width of the detail that opens beside a selected card.
    static let stripDetailWidth: CGFloat = 260

    static let cornerRadius: CGFloat = 8
    static let hairline: CGFloat = 2
}

enum RiftboundArt {
    static let ready = "Ready"
    static let exhaustOrPay = "Exhaust or Pay"
    static let recycleARune = "Recycle a Rune"
    static let draw = "Draw"

    static func unit(active: Bool) -> String { active ? "Unit (Active)" : "Unit (Disabled)" }
    static func spell(active: Bool) -> String { active ? "Spell (Active)" : "Spell (Disabled)" }
    static func battlefield(active: Bool) -> String { active ? "Battlefield (Active)" : "Battlefield (Disabled)" }
}
