import SwiftUI
import SwiftData
import AppKit
import RiftboundVision

/// The actual wiring is `CameraPipelineController` — this view just binds
/// to it. Everything here is "live": press Start and you'll see the real
/// camera feed with every current detection boxed and labeled, on a
/// fixed poll cadence rather than every frame (see the controller's doc
/// comment — this matches `feature/riftbound-scanner-prototype`'s
/// architecture: no per-object tracking, no persistent identity).
///
/// The V3 layout is the same three-part split it always was — header,
/// camera + right column, bottom bar — with one structural change: the
/// camera feed is now locked to 16:9 and inset inside a gold
/// `elementStroke` frame, with the window's `mainBackground` visible
/// around it. Without the aspect lock the stage took whatever rectangle
/// the split view left it and the feed letterboxed itself inside, so the
/// frame ended up enclosing two large slabs of empty space rather than
/// the picture.
struct ContentView: View {
    @StateObject private var pipeline: CameraPipelineController
    @State private var isShowingPipelineSettings = false
    @State private var isShowingOnboarding = false
    /// Whether the welcome sheet has already been shown. Persisted, so it
    /// greets a new player once and then stays out of the way — a modal
    /// that appears every launch is one people learn to dismiss without
    /// reading. It stays reachable from the Help menu.
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    /// The card being inspected. Lives here rather than in the panel so the
    /// camera view and the sidebar agree on what's selected — tapping a box
    /// is what usually sets it.
    @State private var selectedCard: CardPrinting?
    /// How wide the camera picture actually draws — see `CameraStageWidthKey`.
    @State private var cameraStageWidth: CGFloat = 0
    @State private var isShowingCardLibrary = false

    /// `modelContext` is optional so SwiftUI previews (and the no-arg
    /// `ContentView()` used in `#Preview`) still work without a container —
    /// persistence just no-ops when it's absent.
    init(modelContext: ModelContext? = nil) {
        _pipeline = StateObject(wrappedValue: CameraPipelineController(modelContext: modelContext))
    }

    var body: some View {
        // Top bar across the full width, then two columns beneath it.
        //
        // `GameStateBar` and the bottom bar both live *inside* the left
        // column rather than spanning the window: that's what puts the
        // Score panel level with the turn banner, and lets the sidebar run
        // unbroken to the bottom edge.
        // Left column is the board — the cards on the table, the camera,
        // and what BonBon is saying about it. Right column is everything
        // the player operates. Nothing that is only *shown* sits on the
        // right, and nothing you press sits on the left.
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: RiftboundLayout.bandSpacing) {
                TableCardStrip(
                    cards: pipeline.cardsOnTable,
                    selection: $selectedCard,
                    onOpenLibrary: { isShowingCardLibrary = true },
                    description: { pipeline.description(for: $0) }
                )
                CameraStageView(pipeline: pipeline, selectedCard: $selectedCard)
                MascotInstructionPanel(
                    instructions: pipeline.instructions,
                    progress: pipeline.phaseProgress,
                    misplacedCards: pipeline.misplacedCards,
                    needsCalibration: pipeline.needsCalibration,
                    inactiveStage: pipeline.inactivePipelineNotice,
                    validatesPlayerMoves: pipeline.gameState.phase.validatesPlayerMoves,
                    selectedCard: selectedCard,
                    activeBonuses: pipeline.activeDamageBonuses,
                    // Before a Legend is seen the app doesn't know whose
                    // deck it's looking at, and says so instead of
                    // narrating a phase it can't scope. Occupies the
                    // fallback slot rather than a new rank: it is what
                    // there is to say when nothing else is happening, not
                    // an alert.
                    fallback: pipeline.isPipelineRunning
                        ? (pipeline.activeDeckName == nil
                            ? "Show me your Legend first."
                            : RiftboundPhaseCopy.blurb(for: pipeline.gameState.phase))
                        : "Ready to play?"
                )
                // Matched to the camera's *drawn* width, not to the
                // column's inset. The camera is aspect-fit, so at a short
                // window it draws narrower than the column and a band
                // using the same inset overhung it on both sides. `nil`
                // until the first measurement arrives, which falls back to
                // the old full-width behaviour for one layout pass.
                .frame(width: cameraStageWidth > 0 ? cameraStageWidth : nil)
                .padding(.bottom, RiftboundLayout.columnInset)
            }
            .onPreferenceChange(CameraStageWidthKey.self) { cameraStageWidth = $0 }

            TurnControlColumn(
                gameState: $pipeline.gameState,
                isAutoAdvancing: $pipeline.isAutoDetectingPhase,
                playerScore: $pipeline.playerScore,
                opponentScore: $pipeline.opponentScore
            )
        }
        .background(RiftboundPalette.mainBackground)
        .frame(minWidth: 1160, minHeight: 675)
        // `ToolbarItem` with no placement — `.automatic`, which on macOS
        // trails the window title. That is the whole reason the title bar
        // is left visible (see the app entry point): it's what gives these
        // an edge to sit against.
        .toolbar {
            ToolbarItem { CameraSourceMenu(pipeline: pipeline) }
            ToolbarItem {
                // Drag the 4 corner handles onto the physical mat's actual
                // corners as seen by the camera — a visual reference layer
                // only, not consulted by detection.
                Toggle(isOn: $pipeline.isCalibrating) {
                    Label("Calibrate Playmat", systemImage: "square.dashed")
                }
                .toggleStyle(.button)
            }
            ToolbarItem {
                DiagnosticsMenu(
                    pipeline: pipeline,
                    isShowingPipelineSettings: $isShowingPipelineSettings,
                    onShowOnboarding: { isShowingOnboarding = true }
                )
            }
            ToolbarItem {
                // Starts the *pipeline*, not the camera — the feed is
                // already live so the mat can be calibrated first.
                Button(pipeline.isPipelineRunning ? "Stop" : "Start Game") {
                    pipeline.isPipelineRunning ? pipeline.stopPipeline() : pipeline.startPipeline()
                }
                .disabled(!pipeline.isCameraRunning)
            }
        }
        .onAppear {
            pipeline.refreshAvailableCameras()
            // First launch only. Set before presenting rather than on
            // dismiss, so a player who closes the window with the sheet
            // still open isn't greeted by it again next time.
            if !hasSeenOnboarding {
                hasSeenOnboarding = true
                isShowingOnboarding = true
            }
        }
        .sheet(isPresented: $isShowingOnboarding) {
            OnboardingView { isShowingOnboarding = false }
        }
        .sheet(isPresented: $isShowingCardLibrary) {
            CardLibrarySheet(
                database: pipeline.cardDatabase,
                selection: $selectedCard,
                onClose: { isShowingCardLibrary = false }
            )
        }
        // Bring the camera up as soon as the window opens, prompting for
        // access the first time. Calibration needs a live picture, and
        // aligning the mat after starting detection is what put cards in
        // the wrong zones.
        .task { await pipeline.openCamera() }
        // Release the camera when the window goes away. Without this the
        // capture session — and the OS camera indicator — stayed live for
        // the rest of the process's life.
        .onDisappear { pipeline.closeCamera() }
        .sheet(isPresented: Binding(
            get: { pipeline.debugReport != nil },
            set: { if !$0 { pipeline.debugReport = nil } }
        )) {
            CameraDiagnosticSheet(report: pipeline.debugReport ?? "") {
                pipeline.debugReport = nil
            }
        }
    }


    // MARK: - Camera stage

}

#Preview {
    ContentView()
}
