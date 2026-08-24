import AVFoundation
import AppKit
import SwiftUI

/// How fast BonBon talks.
///
/// Three named steps rather than a slider: this is set from a menu, where
/// a continuous control has nothing to drag, and "a bit faster" is the
/// only granularity anyone actually wants from a speech rate.
///
/// The values sit close to `AVSpeechUtteranceDefaultSpeechRate` (0.5) on
/// purpose. The API's range runs 0…1, but the top of it is unintelligible
/// — 1.0 is not "fast", it's noise — so the useful band is narrow and
/// these three points are inside it.
enum RiftboundSpeechRate: String, CaseIterable, Identifiable, Sendable {
    case slow
    case normal
    case fast

    var id: String { rawValue }

    var title: String {
        switch self {
        case .slow: return "Slow"
        case .normal: return "Normal"
        case .fast: return "Fast"
        }
    }

    var value: Float {
        switch self {
        case .slow: return 0.42
        case .normal: return AVSpeechUtteranceDefaultSpeechRate
        case .fast: return 0.58
        }
    }
}

/// Speaks the app's current instruction out loud.
///
/// **Why this exists next to the VoiceOver work rather than instead of
/// it.** VoiceOver reads whatever the cursor is on, for someone navigating
/// the interface. This is for someone whose eyes are on the *table* — the
/// whole premise of the app is that the game is a physical object in front
/// of you, so the moment BonBon has something to say is exactly the moment
/// you are least likely to be looking at the screen. It works whether or
/// not VoiceOver is running, and needs no screen reader to be useful.
///
/// It deliberately says nothing when VoiceOver *is* running: VoiceOver
/// already announces the same sentence (see `MascotInstructionPanel`), and
/// two voices reading one line over each other is worse than either alone.
@MainActor
final class SpokenInstructions: ObservableObject {
    /// One synthesizer for the app. Shared rather than per-view so that
    /// "stop what you were saying and say this instead" is possible at
    /// all — two synthesizers can only talk over each other.
    static let shared = SpokenInstructions()

    private let synthesizer = AVSpeechSynthesizer()

    private init() {}

    /// The voices worth offering, best-first.
    ///
    /// macOS reports 41 English voices here, 19 of which are the legacy
    /// novelty set — Boing, Bubbles, Zarvox, Bad News. They're real
    /// voices and they all "work", but a settings menu that lists them
    /// beside Samantha is a menu nobody can pick from, so the whole
    /// `com.apple.speech.synthesis.voice` family is dropped. Anyone who
    /// genuinely wants Zarvox can set it as the system Spoken Content
    /// voice, and System Default below will pick it up.
    static var selectableVoices: [AVSpeechSynthesisVoice] {
        let language = String(Locale.preferredLanguages.first?.prefix(2) ?? "en")
        var seen = Set<String>()
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language) }
            .filter { !$0.identifier.contains("com.apple.speech.synthesis.voice") }
            // The same name ships per-region (an en-US Flo and an en-GB
            // Flo), which reads as a duplicated row in a menu.
            .filter { seen.insert("\($0.name)|\($0.language)").inserted }
            .sorted { ($0.quality.rawValue, $1.name) > ($1.quality.rawValue, $0.name) }
    }

    /// What to call `voice` in the menu.
    ///
    /// Several voices ship one name per region — there is an en-US Eddy and
    /// an en-GB Eddy — so the bare name would print twice with no way to
    /// tell which row is which, or to know what picking either would sound
    /// like. The region is appended only where a name actually repeats,
    /// since "Samantha (United States)" is noise when there is only one
    /// Samantha.
    static func displayName(for voice: AVSpeechSynthesisVoice, among voices: [AVSpeechSynthesisVoice]) -> String {
        guard voices.count(where: { $0.name == voice.name }) > 1 else { return voice.name }
        let regionCode = String(voice.language.suffix(2))
        let region = Locale.current.localizedString(forRegionCode: regionCode) ?? voice.language
        return "\(voice.name) (\(region))"
    }

    /// Says `text`, cutting off whatever was already being said.
    ///
    /// Interrupting rather than queueing is the important part. Instructions
    /// supersede each other — by the time a queued one is reached the board
    /// has moved on, and the player is being told to do something they
    /// already did. That's the same reason the panel ages its verdicts out
    /// on screen; speech has to obey it too or it becomes the one part of
    /// the app confidently narrating the past.
    ///
    /// - Parameter respectingVoiceOver: when `true` (the default), says
    ///   nothing while VoiceOver is running, since VoiceOver is already
    ///   announcing the same sentence. Passed `false` by the settings menu,
    ///   whose sample has to be audible to be worth anything.
    func speak(
        _ text: String,
        rate: RiftboundSpeechRate,
        voiceIdentifier: String?,
        respectingVoiceOver: Bool = true
    ) {
        guard !text.isEmpty else { return }
        if respectingVoiceOver, NSWorkspace.shared.isVoiceOverEnabled { return }

        synthesizer.stopSpeaking(at: .immediate)

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate.value
        // `nil` is meaningful, not a fallback: it tells AVFoundation to use
        // whatever the player chose in System Settings › Accessibility ›
        // Spoken Content. Defaulting to that rather than to a voice this
        // app picked means someone who has already set a preferred voice
        // system-wide doesn't have to set it a second time here.
        if let voiceIdentifier, !voiceIdentifier.isEmpty {
            utterance.voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier)
        }
        synthesizer.speak(utterance)
    }

    /// Cuts speech off — used when the feature is switched off mid-sentence,
    /// so turning it off actually stops it rather than letting the current
    /// line finish.
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}

// MARK: - Settings keys

/// The `@AppStorage` keys the speech settings live under, in one place so
/// the menu, the panel that speaks, and any future reader can't disagree
/// about the spelling of a string.
enum RiftboundSpeechDefaults {
    static let isEnabled = "riftboundSpeaksInstructions"
    static let rate = "riftboundSpeechRate"
    /// Empty string means "system default voice" — see `speak`.
    static let voice = "riftboundSpeechVoice"
}
