import SwiftUI

/// The accessibility settings, as menu items.
///
/// A `View` nested inside `RiftboundAccessibilityCommands`' group rather
/// than items written directly into that `Commands` body, because these
/// rows have to *react* to the `@AppStorage` values they read — a
/// checkmark that doesn't move when you pick a different voice is worse
/// than no checkmark. `@AppStorage` is a `DynamicProperty`, and a `View`
/// is the context those are actually guaranteed to track in; that's also
/// why the commands struct takes `textSize` as a `@Binding` from the app
/// instead of reading the same key itself.
///
/// Being a `View` also means these same rows can be dropped into any
/// ordinary `Menu` — the toolbar's Help menu carried them once and may
/// again — without being rewritten as a second copy able to drift.
struct AccessibilityMenuContent: View {
    @AppStorage("riftboundTextSize") private var textSize: RiftboundTextSize = .standard
    @AppStorage(RiftboundSpeechDefaults.isEnabled) private var speaksInstructions = false
    @AppStorage(RiftboundSpeechDefaults.rate) private var speechRate: RiftboundSpeechRate = .normal
    @AppStorage(RiftboundSpeechDefaults.voice) private var speechVoice = ""

    var body: some View {
        // Buttons rather than a `Picker`. A `Picker` in a macOS menu drew
        // its label and never opened — the setting was visible and
        // unreachable — so the checkmark is drawn by hand instead.
        Menu("Text Size") {
            ForEach(RiftboundTextSize.allCases) { size in
                checkableButton(size.title, isOn: size == textSize) { textSize = size }
            }
        }

        Divider()

        checkableButton("Speak Instructions", isOn: speaksInstructions) {
            speaksInstructions.toggle()
            if speaksInstructions {
                // Say something the moment it's switched on. A speech
                // setting that stays silent until the game next changes
                // state is indistinguishable from one that doesn't work,
                // and this is also the only way to hear the current voice
                // and rate before committing to them.
                sample("Spoken instructions are on.")
            } else {
                // Stop mid-sentence rather than letting the current line
                // finish — "off" that keeps talking isn't off.
                SpokenInstructions.shared.stop()
            }
        }

        Menu("Speaking Rate") {
            ForEach(RiftboundSpeechRate.allCases) { rate in
                checkableButton(rate.title, isOn: rate == speechRate) {
                    speechRate = rate
                    sample("This is how fast I'll talk.")
                }
            }
        }
        .disabled(!speaksInstructions)

        Menu("Voice") {
            checkableButton("System Default", isOn: speechVoice.isEmpty) {
                speechVoice = ""
                sample("This is the system default voice.")
            }
            Divider()
            // Resolved once rather than per row: `displayName` compares each
            // voice against the whole list to decide whether it needs its
            // region, so rebuilding the list inside the loop would make it
            // quadratic over something that can't change while the menu is open.
            let voices = SpokenInstructions.selectableVoices
            ForEach(voices, id: \.identifier) { voice in
                let name = SpokenInstructions.displayName(for: voice, among: voices)
                checkableButton(name, isOn: speechVoice == voice.identifier) {
                    speechVoice = voice.identifier
                    // Spoken in the voice just chosen, so the sample is the
                    // answer to "what does this one sound like".
                    sample("Hello, I'm \(voice.name).")
                }
            }
        }
        .disabled(!speaksInstructions)
    }

    /// A menu row that shows a checkmark when it's the current value.
    private func checkableButton(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if isOn {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    /// Speaks a sample using whatever the settings now say.
    ///
    /// `respectingVoiceOver: false` because this one is a direct answer to
    /// a button the player just pressed. Everywhere else the app stays
    /// quiet under VoiceOver to avoid two voices reading one line, but a
    /// sample that silently does nothing would read as a broken control.
    private func sample(_ text: String) {
        SpokenInstructions.shared.speak(
            text,
            rate: speechRate,
            voiceIdentifier: speechVoice,
            respectingVoiceOver: false
        )
    }
}
