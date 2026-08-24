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
    @StateObject private var tourCoordinator = TourCoordinator()
    @State private var isShowingOnboarding = false
    /// Whether the guided tour has already auto-started during this run.
    /// Plain `@State`, not `@AppStorage`, and that's the whole point: the
    /// tour is meant to greet the player on *every* launch, so nothing
    /// about it should survive one. This only stops a second `.onAppear`
    /// for the same window restarting a tour already in progress.
    @State private var hasStartedTourThisLaunch = false
    /// The card being inspected. Lives here rather than in the panel so the
    /// camera view and the sidebar agree on what's selected — tapping a box
    /// is what usually sets it.
    @State private var selectedCard: CardPrinting?
    /// How wide the camera picture actually draws — see `CameraStageWidthKey`.
    @State private var cameraStageWidth: CGFloat = 0
    @State private var isShowingCardLibrary = false
    /// Each `.tourPopover` region's on-screen frame, in `tourCoordinateSpace`
    /// — read out of the preference system once here rather than inside
    /// `TourSpotlightOverlay` itself, since that view has no ancestor
    /// relationship to the anchors on the *other* side of the window's
    /// two-column split.
    @State private var tourRegionFrames: [TourRegion: CGRect] = [:]

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
        ZStack {
            // Fills the *whole* `ZStack`, unconditionally — `mainContent`
            // below has its own `.background(mainBackground)`, but that's
            // only sized to `mainContent`'s own natural content height.
            // `TourOverlay`'s `maxHeight: .infinity` (right below) forces
            // this `ZStack` to expand to the full window regardless, so
            // whenever the window is taller than the content actually
            // needs, the gap was covered by neither: not `mainContent`'s
            // background (too small) and not `TourOverlay` (renders
            // `EmptyView()` outside a tour), leaving raw unpainted window
            // backing — black — showing through above the real content.
            RiftboundPalette.mainBackground
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            mainContent
            // A sibling in the same `ZStack`, not `.overlay(...)` on
            // `mainContent` — `.overlay` trusts the modified view's own
            // *resolved* size to still equal the full window by the time
            // the overlay reads it, and in practice that stopped holding:
            // the right column stayed permanently undimmed no matter which
            // step was showing, which only makes sense if the overlay was
            // only ever being sized to (something close to) the left
            // column. Giving both an explicit, unconditional
            // `maxWidth/maxHeight: .infinity` removes the question of
            // which one's size the other is supposed to be inheriting.
            TourOverlay(
                coordinator: tourCoordinator,
                frames: tourRegionFrames,
                onExploreMyself: { tourCoordinator.exploreMyself() },
                onShowMeAround: { tourCoordinator.showMeAround() },
                onSkip: { tourCoordinator.skip() },
                onAdvance: { tourCoordinator.advance() },
                onFinish: { tourCoordinator.finish() }            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // The one ancestor both the left column's and right column's
        // `.tourRegion` anchors, and `TourOverlay` itself, all share — this
        // is what makes `tourCoordinateSpace` resolve to something real
        // rather than an undefined name that silently measures nothing.
        .coordinateSpace(name: tourCoordinateSpace)
        .onPreferenceChange(TourRegionFrameKey.self) { tourRegionFrames = $0 }
        // Kept in sync so the camera-adjustment step's wording reflects
        // whatever the player's actual table looks like right now, not
        // whatever it looked like when the tour started.
        .onChange(of: pipeline.isCameraRunning) { _, isRunning in
            tourCoordinator.isCameraRunning = isRunning
        }
        // Script 8.5 has no Next button — it ends when the player presses
        // the real Start Game it's pointing at. Sent unconditionally; the
        // coordinator ignores it unless that step is the one showing.
        .onChange(of: pipeline.isPipelineRunning) { _, isRunning in
            if isRunning { tourCoordinator.gameDidStart() }
        }
        .frame(minWidth: 1160, minHeight: 675)
        // `ToolbarItem` with no placement — `.automatic`, which on macOS
        // trails the window title. That is the whole reason the title bar
        // is left visible (see the app entry point): it's what gives these
        // an edge to sit against.
        .toolbar {
            // Deliberately *not* carrying `.tourRegion` anchors, though
            // the tour has steps about both. Toolbar content is hosted in
            // the window's title bar, outside the coordinate space
            // `.tourRegion` measures into and outside anything
            // `TourOverlay` can draw over, so an anchor here would report
            // a frame the spotlight could only get wrong. Those two steps
            // are handled by `TourRegion.isTitleBarHosted` instead.
            ToolbarItem { CameraSourceMenu(pipeline: pipeline) }
            ToolbarItem {
                // Drag the 4 corner handles onto the physical mat's actual
                // corners as seen by the camera — a visual reference layer
                // only, not consulted by detection.
                Toggle(isOn: $pipeline.isCalibrating) {
                    Label {
                        Text("Calibrate Playmat")
                    } icon: {
                        // The reference's own resize glyph, in place of the
                        // `square.dashed` SF Symbol that stood in for it.
                        //
                        // Sized explicitly because a custom image renders at
                        // its natural size — 23×22 here — which would sit
                        // noticeably larger than the SF Symbols either side
                        // of it in the same toolbar. The asset is a template
                        // (see `RiftboundArt.resizeOverlay`), so it still
                        // takes the toolbar's own tint and its selected
                        // state, exactly as the symbol did.
                        Image(RiftboundArt.resizeOverlay)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                    }
                }
                .toggleStyle(.button)
            }
            ToolbarItem {
                DiagnosticsMenu(
                    onShowOnboarding: { isShowingOnboarding = true },
                    onShowTour: { tourCoordinator.start() }
                )
            }
        }
        .onAppear {
            pipeline.refreshAvailableCameras()
            // `.onChange(of: pipeline.isCameraRunning)` only fires on
            // later changes — this covers the value it already has by the
            // time the tour might start.
            tourCoordinator.isCameraRunning = pipeline.isCameraRunning
            // Every launch, not just the first — so this deliberately
            // persists nothing. The intro's own "I'll explore myself" is
            // the way past it, and it's one click, which is what makes
            // greeting a returning player each time reasonable rather
            // than nagging.
            //
            // This slot used to auto-present `OnboardingView`. The two
            // shouldn't both fire: they greet the same player about the
            // same app, and a sheet stacked in front of a full-window
            // tour means dismissing one welcome to reach another. The
            // tour supersedes it here and the sheet stays on the Help
            // menu as Quick Guide, which is also where the tour's own
            // skip card tells players to look.
            //
            // The guard is per *launch*, not per appearance: `.onAppear`
            // can fire again for the same view, and without this a
            // re-appear mid-tour would throw the player back to the intro
            // from wherever they'd got to.
            if !hasStartedTourThisLaunch {
                hasStartedTourThisLaunch = true
                tourCoordinator.start()
            }
        }
        .sheet(isPresented: $isShowingOnboarding) {
            OnboardingView { isShowingOnboarding = false }
        }
        .sheet(isPresented: $isShowingCardLibrary) {
            CardLibrarySheet(
                database: pipeline.cardDatabase,
                selection: $selectedCard,
                description: { pipeline.description(for: $0) },
                onClose: { isShowingCardLibrary = false }
            )
        }
        // Bring the camera up as soon as the window opens — but without
        // ever raising the permission dialog here. Calibration needs a
        // live picture, so an already-granted camera starts immediately;
        // a first-run player instead meets the dialog at the tour step
        // below, where BonBon has just explained what it's for.
        .task { await pipeline.openCamera(promptingForAccess: false) }
        // The ask, in context. This is the step whose script reads "Let's
        // adjust the camera, so I can see the game and guide you" — the
        // first point in the app where the dialog answers a question the
        // player has actually been asked.
        //
        // Fires on the step the player *lands* on, so it covers arriving
        // by Next and by any other route into it. `openCamera` returns
        // immediately if the feed is already up, so a player who granted
        // access on a previous launch sees nothing happen here at all.
        .onChange(of: tourCoordinator.currentStep?.region) { _, region in
            guard region == .cameraMenu else { return }
            Task { await pipeline.openCamera() }
        }
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

    /// The board and the operator column — everything that isn't the
    /// tour's own overlay. Split out so `body` can place this and
    /// `TourOverlay` as plain `ZStack` siblings instead of nesting the
    /// overlay inside this view's own modifier chain.
    private var mainContent: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: RiftboundLayout.bandSpacing) {
                TableCardStrip(
                    cards: pipeline.cardsOnTable,
                    selection: $selectedCard,
                    onOpenLibrary: { isShowingCardLibrary = true },
                    description: { pipeline.description(for: $0) }
                )
                // `.tourRegion(.playmat)` is declared *inside*
                // `CameraStageView`, on the aspect-fitted picture rather
                // than out here on the container — see the note at that
                // site.
                CameraStageView(pipeline: pipeline, selectedCard: $selectedCard)
                MascotInstructionPanel(
                    // Everything but `fallback` is state left over from
                    // whatever game last ran. While the pipeline is stopped
                    // — Start Game showing rather than Stop Game — none of
                    // it should outrank "Ready to play?": without this a
                    // stale verdict or an unresolved misplaced card from the
                    // game that just ended kept talking after Stop Game
                    // reset the phase indicator back to Awaken.
                    instructions: pipeline.isPipelineRunning ? pipeline.instructions : [],
                    progress: pipeline.isPipelineRunning ? pipeline.phaseProgress : nil,
                    misplacedCards: pipeline.isPipelineRunning ? pipeline.misplacedCards : [],
                    needsCalibration: pipeline.isPipelineRunning && pipeline.needsCalibration,
                    inactiveStage: pipeline.isPipelineRunning ? pipeline.inactivePipelineNotice : nil,
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
                opponentScore: $pipeline.opponentScore,
                isPipelineRunning: pipeline.isPipelineRunning,
                isCameraRunning: pipeline.isCameraRunning,
                onTogglePipeline: {
                    if pipeline.isPipelineRunning {
                        pipeline.stopPipeline()
                        // Stopping mid-turn leaves the phase indicator
                        // wherever the player last advanced it. The next
                        // Start Game is a fresh game, not a resume, so the
                        // indicator goes back to the same place a new game
                        // begins rather than reappearing disabled but
                        // pointed at a phase from the game that just ended.
                        pipeline.gameState = ManualGameState()
                    } else {
                        // Safety net for the player who skipped the tour and
                        // so never reached the step that asks. Without this,
                        // deferring the prompt would leave them permanently
                        // blind: `startPipeline` needs a running camera and
                        // returns silently without one, so Start Game would
                        // simply do nothing, forever, with no dialog to
                        // explain why. Pressing Start Game is itself an
                        // unambiguous request for the camera, so it's a fair
                        // moment to ask.
                        Task {
                            await pipeline.openCamera()
                            pipeline.startPipeline()
                        }
                    }
                }
            )
        }
        .background(RiftboundPalette.mainBackground)
    }
}

#Preview {
    ContentView()
}
