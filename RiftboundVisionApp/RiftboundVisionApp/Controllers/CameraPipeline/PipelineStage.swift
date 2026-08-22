//  Pipeline vocabulary and the small concurrency helpers the controller
//  needs, split out of `CameraPipelineController.swift` — none of them are
//  the controller, and none touch its state.

import SwiftUI
import SwiftData
import CoreImage
import AVFoundation
import RiftboundVision
import RiftboundExpertSystem
import RiftboundTextProcessing

/// One stage of the CV → Expert System pipeline, in dependency order —
/// matches the 4-stage pipeline documented in the root README. Each
/// stage needs the one before it enabled to produce anything worth
/// consuming, which is what the settings overlay's cascade behavior
/// enforces: turning a stage off also turns off everything after it.
enum PipelineStage: Int, CaseIterable, Identifiable {
    case detection = 1
    case objectTracking = 2
    case nlpTranslation = 3
    case expertSystem = 4

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .detection: return "① YOLO Detection"
        case .objectTracking: return "② Object Tracking + Zones"
        case .nlpTranslation: return "③ NLP Translation"
        case .expertSystem: return "④ Expert System"
        }
    }

    /// Whether this stage is actually implemented in the app's live
    /// per-frame loop right now. All four are wired: ③/④ run inside
    /// `GameEngine.process`, which calls the NLP translator
    /// (`ExpertSystemTranslatorAdapter`) and then the Expert System's
    /// validator/applier/Cleanup in sequence. Because ③ and ④ live behind
    /// that single call, toggling ③ off stops the whole engine — there's
    /// no way to run the Expert System on actions the translator never
    /// produced, which is exactly the cascade the settings panel models.
    var isWired: Bool { true }
}

/// One-slot, lock-guarded hand-off for the NLP translator's explanation of
/// an event it declined to turn into an action. The translator runs inside
/// `GameEngine.process` off the main actor, while the UI reads on it, so
/// the value can't simply live on `CameraPipelineController`.
/// Carries a value across a concurrency boundary Swift can't verify.
/// Used only where the single-writer, in-order contract makes the crossing
/// safe in fact — see `CameraPipelineController.detect(in:)`.
struct UncheckedBox<Value>: @unchecked Sendable {
    let value: Value
}

final class TranslationNoteBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    func set(_ newValue: String?) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }

    /// Reads and clears in one atomic step, so a note is attached to
    /// exactly one instruction.
    func take() -> String? {
        lock.lock()
        defer { lock.unlock() }
        let current = value
        value = nil
        return current
    }
}

/// Drives camera → detector and publishes what the live overlay needs to
/// render. This is deliberately app-shell code (lives here, not in the
/// `RiftboundVision` library) — it exists to make the detection pipeline's
/// current state visible on screen.
///
/// Detection architecture matches `feature/riftbound-scanner-prototype`'s
/// `DetectionCoordinator` on purpose: poll the latest frame on a fixed
/// interval and republish a fresh, unfiltered-by-identity array every
/// time — no `TrackedObjectID`, no zone history, no occlusion tolerance.
/// Each poll is independent, so results can flicker frame to frame the
/// way raw model output does; that's the tradeoff for not carrying any
/// tracking state that could itself go stale or wrong. Card recognition
/// is a fresh `cardDatabase` lookup per detection too, not cached.
///
/// A *second*, independent consumer reads the same polled detections for
/// game-state purposes: `expertSystemAdapter` runs its own internal
/// `ObjectTracker`/`ZoneMapper`/`TemporalEventDetector` (see
/// `ExpertSystemAdapter`) to turn them into `ObservedTableEvent`s. This is
/// deliberately not the same code path as the live overlay above — the
/// overlay wants "what's visible right now," the Expert System wants
/// "what changed, debounced and identity-stable." Reverting the overlay
/// back to tracked mode to get that would have undone the whole point of
/// the stateless redesign; running two consumers off the same detections
/// keeps both needs met without forcing one architecture to serve both.
///
/// The playmat overlay (`calibration`) starts centered on the first frame
/// and does nothing useful until the user drags its corners onto their
/// actual physical mat (see `isCalibrating`). It's purely visual for the
/// live-detection overlay above (which scans the full frame, matching the
/// prototype), but it IS what `expertSystemAdapter`'s `ZoneMapper` is
/// built from — dragging the corners into place is what makes Hand/Base/
/// Battlefield resolve to real zones for game-state ingestion instead of
/// `.unknown`.
