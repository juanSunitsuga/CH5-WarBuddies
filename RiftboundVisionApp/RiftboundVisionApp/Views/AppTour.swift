import SwiftUI

/// The real regions the guided tour points at. A step's `region` picks one
/// of these to spotlight; several steps in a row can share the same one
/// (all the camera/playmat steps point at `.playmat` in sequence) before
/// the tour moves on.
enum TourRegion: CaseIterable, Hashable {
    /// The row of recognised cards — *not* including the Library button
    /// at its trailing end, which the script points at separately.
    case table
    case cardLibrary
    /// The framed camera stage. Anchored on the aspect-fitted picture
    /// itself, not its container — see `CameraStageView`.
    case playmat
    case cameraMenu
    case calibrate
    case startGame
    /// The Phase Indicator's *readout* — header, pips, and the current
    /// phase's name and blurb.
    case phaseIndicator
    /// Auto-advance plus the Back/Next/End Turn row. Split from
    /// `.phaseIndicator` because the script points at the readout and the
    /// controls in separate beats.
    case turnControls
    case score

    /// Which side of the spotlit region the card sits on.
    var cardPlacement: TourCardPlacement {
        switch self {
        case .table, .cardLibrary, .playmat:
            return .below
        case .phaseIndicator, .turnControls, .score, .startGame:
            return .leading
        case .cameraMenu, .calibrate:
            return .underToolbar
        }
    }

    /// Lives in the window's **title bar**, not its content view.
    ///
    /// AppKit hosts toolbar items in a title bar accessory that is a
    /// sibling of the content view, so it is outside both the coordinate
    /// space `.tourRegion` measures into *and* the area `TourOverlay` can
    /// draw over. There is no spotlight to be had for these: a cutout
    /// would be drawn at an unrelated position, and even a correct one
    /// couldn't dim or reveal a pixel of the title bar.
    ///
    /// What these steps do instead is park the card directly beneath the
    /// toolbar, at the same edge the control sits on, and put the
    /// control's own icon inline in the sentence (`{sf:…}`, rendered by
    /// `TourCard`) so the thing being described is identifiable by sight
    /// rather than by position alone.
    var isTitleBarHosted: Bool {
        switch self {
        case .cameraMenu, .calibrate: return true
        case .table, .cardLibrary, .playmat, .startGame,
             .phaseIndicator, .turnControls, .score: return false
        }
    }

    /// How far the spotlight pulls **in** from this region's measured
    /// layout frame (negative pushes out).
    ///
    /// A view's layout frame and the shape a player perceives are not
    /// always the same rectangle. `TableCardStrip` reserves `columnInset`
    /// of horizontal padding *outside* the thing you can see, inside a
    /// frame that runs flush to the window's own edges — so a spotlight
    /// drawn on its raw frame is a full-bleed rectangle touching the
    /// title bar and the window's left edge, with its corner radius
    /// clipped away off-screen. That's what made the highlight read as
    /// broken rather than as "this section of the screen." Pulling in by
    /// the padding the region already reserves puts the highlight's edge
    /// where the player thinks the section's edge is.
    ///
    /// Where a region can instead declare `.tourRegion` on the exact view
    /// it wants highlighted, that's the better fix and this drops to a
    /// few points of overhang — `.playmat` is the worked example.
    var spotlightInset: EdgeInsets {
        switch self {
        case .table, .cardLibrary:
            // The two halves of the card strip, and they share a
            // constraint the sidebar regions don't have: both frames fill
            // the row's full `stripCardHeight + 24` height, and the row
            // itself is flush against the top of the content area. So
            // they pull *in* vertically — the 4pt comes out of the slack
            // the row already leaves around its tallest content — where
            // pushing out would put the cutout's top edge above the
            // window's own content and bleed past the border.
            // Horizontally they still push out, like every other
            // content-anchored region.
            return EdgeInsets(top: 4, leading: -8, bottom: 4, trailing: -8)
        case .cameraMenu, .calibrate:
            // Unused — `isTitleBarHosted` means these never reach a
            // cutout. Stated rather than defaulted so adding a region
            // here still has to answer the question.
            return EdgeInsets()
        case .playmat:
            // Pushed *out*, not pulled in — unlike every other region this
            // one is measured on exactly the rectangle it should
            // highlight (the aspect-fitted, gold-framed stage; see
            // `CameraStageView`), so there is no padding to undo. The only
            // adjustment it wants is enough overhang to clear its own 2pt
            // border, so the spotlight reads as a ring around the stage
            // rather than a cut along the border itself.
            return EdgeInsets(top: -6, leading: -6, bottom: -6, trailing: -6)
        case .phaseIndicator, .turnControls, .score, .startGame:
            // Negative — pushed *out*. These sit inside their column's own
            // inset, so a spotlight hugging their frame exactly stops
            // right against their text. A few points of overhang reads as
            // a deliberate frame around the control.
            return EdgeInsets(top: -8, leading: -8, bottom: -8, trailing: -8)
        }
    }
}

enum TourCardPlacement {
    case below
    case leading
    /// Intro and the Skip-tour landing card aren't about any one control,
    /// so there's nothing to sit flush against — the card just sits in
    /// the middle of the dimmed window.
    case center
    /// Parked against the top-trailing corner of the content area, as
    /// close to the real toolbar as the overlay can reach. For the two
    /// title-bar-hosted controls — see `TourRegion.isTitleBarHosted`.
    case underToolbar
}

/// What a step's button row looks like. Every button in this tour is a
/// solid gold pill (`RiftPrimaryButtonStyle`) — there's no quieter/plain
/// style anywhere in the reference, including "Skip tour" itself.
enum TourStepButtons {
    /// The ordinary case: Skip tour, leading; Next (or a step-specific
    /// label), trailing.
    case skipAndNext(nextLabel: String = "Next")
    /// One button, right-aligned — "Deal!", "Let's Go!". Reads as a
    /// checkpoint the player confirms, not a step they might skip past.
    case single(String)
    /// One button, centred — only the Skip-tour landing card's "Start
    /// Playing" uses this; everywhere else a lone button sits right-
    /// aligned to land under "Next"'s usual position.
    case singleCentered(String)
    /// Intro only: two full-weight choices instead of a skip/advance
    /// pair, since this is the one place the player is actually choosing
    /// whether they want the tour at all.
    case branch(exploreLabel: String, showMeLabel: String)
    /// Skip tour and nothing else. For a step that advances when the
    /// player does the real thing it's pointing at — offering a "Next"
    /// alongside would let them walk past the very action the step
    /// exists to get them to take.
    case skipOnly
}

/// Which BonBon the card draws. The tour uses the *head* crops rather
/// than the full-body sprite the mascot band uses — at the card's size a
/// full body renders the face too small to read, which is the whole point
/// of having one.
enum TourSprite {
    case bonbon
    /// For the two beats where BonBon is admitting a limitation rather
    /// than explaining a feature: "I'm still learning to read cards" and
    /// the no-camera branch. The expression is the tell that something is
    /// wrong, so it has to change with the words.
    case bonbonDizzy

    var imageName: String {
        switch self {
        case .bonbon: return "BonBon Head (Default)"
        case .bonbonDizzy: return "BonBon Head (Dizzy)"
        }
    }
}

/// One beat of the tour. `message` is a closure rather than a stored
/// string only because one step's wording depends on whether a camera is
/// actually connected right now — every other step's closure just returns
/// a constant. `sprite` is a closure for exactly the same reason, and on
/// exactly the same step: the two have to branch together or BonBon ends
/// up cheerful while apologising.
struct TourStep {
    /// `nil` for the steps that aren't about any one control — they dim
    /// the whole window and sit in the middle of it, the same shape the
    /// intro uses.
    let region: TourRegion?
    let message: (_ isCameraRunning: Bool) -> String
    let sprite: (_ isCameraRunning: Bool) -> TourSprite
    let buttons: TourStepButtons
    /// Whether this step waits for the player to actually start the game
    /// rather than for a button on the card. While it's showing, the
    /// scrim stops swallowing clicks so the real Start Game button
    /// underneath is reachable.
    let waitsForGameStart: Bool

    init(
        _ region: TourRegion?,
        buttons: TourStepButtons,
        waitsForGameStart: Bool = false,
        sprite: @escaping (_ isCameraRunning: Bool) -> TourSprite = { _ in .bonbon },
        message: @escaping (_ isCameraRunning: Bool) -> String
    ) {
        self.region = region
        self.buttons = buttons
        self.waitsForGameStart = waitsForGameStart
        self.sprite = sprite
        self.message = message
    }

    init(
        _ region: TourRegion?,
        _ message: String,
        buttons: TourStepButtons,
        waitsForGameStart: Bool = false,
        sprite: TourSprite = .bonbon
    ) {
        self.init(
            region,
            buttons: buttons,
            waitsForGameStart: waitsForGameStart,
            sprite: { _ in sprite }
        ) { _ in message }
    }
}

/// The tour's actual script, in the order it plays, with each step aimed
/// at the region the annotated reference marks for it. The numbering in
/// the comments below is the reference's own ("Script 2", "Script 3A"),
/// kept because it's how the script is discussed — Script 1 and 1A are
/// the intro and skip-landing screens, which live in `TourPhase` rather
/// than in this array.
///
/// Two orderings here look wrong out of context and are deliberate: the
/// camera and calibration steps point at *toolbar* controls rather than
/// at the picture they affect, and the "Deal?"/"ready to play?" beats
/// close the tour after the turn controls rather than introducing them.
enum TourScript {
    // Computed, not a stored `static let` — a stored array of `TourStep`
    // (which holds a closure) is flagged under Swift 6 strict concurrency
    // as shared mutable global state, the same issue `TourRegionFrameKey
    // .defaultValue` hit. Rebuilt on each access rather than cached; this
    // is 14 struct literals, not a cost worth avoiding.
    static var steps: [TourStep] {
        [
        // Script 2 — the one step with no Skip tour; right after the
        // intro's own choice, a second bail-out option in the very next
        // beat would read as the app not trusting its own opening answer.
        TourStep(.playmat, "This is your table. Everything happens in here.", buttons: .single("Next")),

        // Script 3 / 3A — the camera source menu, which is where the
        // player fixes it if the answer is "no camera".
        TourStep(
            .cameraMenu,
            buttons: .skipAndNext(),
            // 3A only. The wording and the face are the same branch:
            // "I can't see anything" over a cheerful default head reads
            // as a joke rather than as the app telling you it's blind.
            sprite: { $0 ? .bonbon : .bonbonDizzy }
        ) { isCameraRunning in
            isCameraRunning
                ? "Let's adjust the camera, so I can see the game and guide you. Pick it under {sf:camera} up top."
                : "Nooo~ I can't see anything T-T Plug one in or use your iPhone, and I'll be watching. Choose it under {sf:camera} up top."
        },

        // Script 4
        TourStep(.calibrate, "Cool, now let's set your playmat so that it's adjusted to the table. Hit {sf:square.dashed} up top and drag the corners.", buttons: .skipAndNext()),

        // Script 5
        TourStep(.playmat, "Now that it's ready, you can put your cards based on their zone.", buttons: .skipAndNext()),

        // Script 6
        TourStep(.table, "I'll read your cards as they land. Cards I recognize show up at the top.", buttons: .skipAndNext()),

        // Script 7
        TourStep(.table, "Click one and I'll tell you its type, its cost, and what it does.", buttons: .skipAndNext()),

        // Script 8
        TourStep(.cardLibrary, "Don't worry! If you ever forget, I'll remember everything for you. Click search or filter if you want to find any specific card.", buttons: .skipAndNext()),

        // Script 8.5 — the only step with no Next. Everything after this
        // is about a turn in progress, so the tour waits here until the
        // player actually starts one; `waitsForGameStart` is what both
        // drops the Next button and lets clicks through the scrim to the
        // real button underneath.
        TourStep(
            .startGame,
            "This is **Start Game** — press it and I'll start watching your table. Hit it again any time to stop.",
            buttons: .skipOnly,
            waitsForGameStart: true
        ),

        // Script 9
        TourStep(.phaseIndicator, "When you begin your turn, start with the ABCD: (A)waken → (B)eginning → (C)hannel → (D)raw", buttons: .skipAndNext()),

        // Script 10
        TourStep(.turnControls, "Tap **Next** when a step is done or flip on **Auto-advance** and I'll keep up with you.", buttons: .skipAndNext()),

        // Script 11
        TourStep(.turnControls, "When you're done, hit **End Turn**.", buttons: .skipAndNext()),

        // Script 12
        TourStep(.score, "Track you and your opponent's score every time someone wins at a battlefield.", buttons: .skipAndNext()),

        // Script 13 — centred, no region. A caveat about BonBon rather
        // than a pointer at any control, so there is nothing to spotlight.
        TourStep(
            nil,
            "I'm still learning to read cards. If something looks off, trust your eyes over mine. Deal?",
            buttons: .single("Deal!"),
            sprite: .bonbonDizzy
        ),

        // Script 14 — centred, and the last beat.
        TourStep(nil, "So, ready to play?", buttons: .single("Let's Go!")),
        ]
    }
}

/// Where the tour currently is. Three shapes rather than one: the intro
/// and the Skip-tour landing card are both one-off screens with their own
/// button layout and no region to spotlight, so folding them into
/// `.step(Int)` would mean every reader of that case handling a region
/// that might not actually exist.
enum TourPhase: Equatable {
    case intro
    /// Landed on from *either* Skip tour on a regular step or "I'll
    /// explore myself" on the intro — the same reassurance either way:
    /// go set up, find BonBon again in Help.
    case skippedTo
    case step(Int)
}

/// Drives the guided tour: which phase/step is showing right now, and
/// whether the camera-aware step should read as connected or not.
@MainActor
final class TourCoordinator: ObservableObject {
    @Published private(set) var phase: TourPhase?
    /// Read by the one step whose wording depends on it. A plain stored
    /// property set by the caller each time `CameraPipelineController`
    /// publishes a change, rather than this class holding a reference to
    /// the controller itself — the tour doesn't need to know the camera
    /// pipeline exists beyond this one fact.
    @Published var isCameraRunning = false

    var currentStep: TourStep? {
        guard case .step(let index) = phase else { return nil }
        return TourScript.steps[index]
    }

    func start() {
        phase = .intro
    }

    func exploreMyself() {
        phase = .skippedTo
    }

    func showMeAround() {
        phase = .step(0)
    }

    func skip() {
        phase = .skippedTo
    }

    /// Ends the tour — the Skip-tour landing card's own "Start Playing".
    func finish() {
        phase = nil
    }

    /// The regular step buttons' "Next" (or step-specific label) and the
    /// checkpoint buttons' "Deal!"/"Let's Go!" all do the same thing:
    /// move to the next step, or end the tour after the last one.
    func advance() {
        guard case .step(let index) = phase else { return }
        let next = index + 1
        phase = next < TourScript.steps.count ? .step(next) : nil
    }

    /// The real Start Game button was pressed. Only the step that's
    /// waiting on it moves — called unconditionally from `ContentView`
    /// whenever the pipeline starts, including when no tour is running or
    /// the player is somewhere else in it, so the guard is the whole
    /// point rather than a defensive extra.
    func gameDidStart() {
        guard let step = currentStep, step.waitsForGameStart else { return }
        advance()
    }
}

// MARK: - Region measurement

/// The one coordinate space every tour region's frame — and the overlay
/// that reads them back — agrees on. Without a named space, `GeometryProxy`
/// hands back frames relative to whatever view happens to be asking, which
/// is a different answer at each of the five anchors split across the left
/// and right columns; a shared name is what makes all five comparable to
/// the *same* window-relative rectangle the spotlight draws into.
///
/// Declared on `ContentView`'s outer `HStack` — the actual common ancestor
/// of every anchor and of the overlay itself. Declaring it anywhere *not*
/// an ancestor of both sides silently resolves to nothing, which is
/// exactly the bug that motivated writing this note down.
let tourCoordinateSpace = "tour"

/// Collects each tour region's on-screen frame as views declare it, so the
/// spotlight overlay can cut a hole in exactly the right place — and the
/// card can sit flush against it — without this file hardcoding a single
/// coordinate.
struct TourRegionFrameKey: PreferenceKey {
    static var defaultValue: [TourRegion: CGRect] { [:] }
    static func reduce(value: inout [TourRegion: CGRect], nextValue: () -> [TourRegion: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    /// Marks this view as the real anchor for `region`'s tour card — the
    /// spotlight cutout and the card's own position both line up on
    /// whatever this view's actual layout bounds turn out to be, so moving
    /// the control later doesn't leave the tour pointing at empty space.
    func tourRegion(_ region: TourRegion) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: TourRegionFrameKey.self,
                    value: [region: geo.frame(in: .named(tourCoordinateSpace))]
                )
            }
        )
    }
}

// MARK: - Spotlight + card

/// Darkens the whole window — with a rounded-rect cutout around the
/// current step's region, or no cutout at all for the intro/skipped-to
/// screens, which aren't about any one control — and draws that step's
/// card. One view rather than two, because the card's position is
/// computed straight from the same cutout rect the mask uses, so they
/// can't disagree about where the highlighted region actually is.
struct TourOverlay: View {
    let coordinator: TourCoordinator
    let frames: [TourRegion: CGRect]
    let onExploreMyself: () -> Void
    let onShowMeAround: () -> Void
    let onSkip: () -> Void
    let onAdvance: () -> Void
    let onFinish: () -> Void

    private static let cardWidth: CGFloat = 470
    /// The card's box (BonBon + text) plus its button row, guessed rather
    /// than measured — see `cardCenter(for:bounds:)`. Has to be raised
    /// alongside `cardWidth`: the box wraps its content, so a taller
    /// sprite and deeper padding grow the real card while a stale
    /// estimate here would quietly place it too high and let it overlap
    /// the very region it's pointing at.
    private static let estimatedCardHeight: CGFloat = 215

    var body: some View {
        GeometryReader { proxy in
            switch coordinator.phase {
            case .none:
                EmptyView()
            case .intro:
                fullScrim(in: proxy.size)
                card(
                    sprite: .bonbon,
                    message: "Hi~ I'm BonBon! I'll be here with you while you play Riftbound ^^",
                    buttons: .branch(exploreLabel: "I'll explore myself", showMeLabel: "Show me around")
                )
                .position(cardCenter(placement: .center, cutout: nil, bounds: proxy.size))
            case .skippedTo:
                fullScrim(in: proxy.size)
                card(
                    sprite: .bonbon,
                    message: "Awesome, let's line up the camera and start the game! You can always find me in **Help** on the top.",
                    buttons: .singleCentered("Start Playing")
                )
                .position(cardCenter(placement: .center, cutout: nil, bounds: proxy.size))
            case .step:
                if let step = coordinator.currentStep {
                    // Three ways to land in the centred branch, and they
                    // want identical treatment: the step names no region
                    // (Scripts 13 and 14), or it names one whose frame
                    // hasn't arrived yet, or it names one that can't be
                    // measured at all. Falling back to "dim everything,
                    // card in the middle" means a region that never
                    // reports still shows its words — the previous
                    // `if let` rendered nothing whatsoever, so a single
                    // unmeasurable region would have stalled the tour on
                    // a blank dark screen with no way forward.
                    if let region = step.region, region.isTitleBarHosted {
                        // No cutout is possible — the control is in the
                        // title bar. Dim everything and park the card at
                        // the toolbar's own edge; the copy carries the
                        // control's icon inline.
                        fullScrim(in: proxy.size)
                        card(
                            sprite: step.sprite(coordinator.isCameraRunning),
                            message: step.message(coordinator.isCameraRunning),
                            buttons: step.buttons
                        )
                        .position(cardCenter(placement: .underToolbar, cutout: nil, bounds: proxy.size))
                    } else if let region = step.region,
                       let rawCutout = frames[region],
                       !rawCutout.isEmpty {
                        // Inset *then* clamp, in that order: the inset is
                        // what turns a layout frame into the shape the
                        // player sees, and the clamp is a safety net
                        // against measurement drift. Clamping first would
                        // measure the safety margin from an edge that's
                        // about to move anyway.
                        let cutout = clampedToSidebar(
                            rawCutout.inset(by: region.spotlightInset),
                            region: region
                        )
                        // Last, after both the inset and the sidebar
                        // clamp: whatever those two produce, a cutout is
                        // never allowed outside the window. A region
                        // whose frame sits flush against an edge — the
                        // card strip's two halves both do, against the
                        // top — would otherwise have its outward push
                        // land off-content, and the spotlight's rounded
                        // corner gets sliced off against the window
                        // border instead of reading as a panel.
                        .clamped(within: proxy.size, margin: Self.windowMargin)
                        cutoutScrim(around: cutout, in: proxy.size)
                            // The waiting step points at a button the
                            // player has to actually press, so the scrim
                            // must not eat the click. Scoped to that one
                            // step: everywhere else the tour stays modal.
                            .allowsHitTesting(!step.waitsForGameStart)
                        card(
                            sprite: step.sprite(coordinator.isCameraRunning),
                            message: step.message(coordinator.isCameraRunning),
                            buttons: step.buttons
                        )
                        .position(cardCenter(placement: region.cardPlacement, cutout: cutout, bounds: proxy.size))
                    } else {
                        fullScrim(in: proxy.size)
                            .allowsHitTesting(!step.waitsForGameStart)
                        card(
                            sprite: step.sprite(coordinator.isCameraRunning),
                            message: step.message(coordinator.isCameraRunning),
                            buttons: step.buttons
                        )
                        .position(cardCenter(placement: .center, cutout: nil, bounds: proxy.size))
                    }
                }
            }
        }
        .allowsHitTesting(coordinator.phase != nil)
        .animation(.easeInOut(duration: 0.25), value: coordinator.phase)
    }

    /// `.table`'s and `.playmat`'s measured frame keeps reporting a few
    /// points wider than the left column actually renders, letting the
    /// cutout's edge — and the sliver of undimmed sidebar with it — bleed
    /// just past the boundary even after the frame-measurement rework
    /// elsewhere fixed the far larger version of this same bug. Rather
    /// than keep chasing the exact source of a few points of drift, the
    /// two left-column regions are clamped here to whatever the right
    /// column's own regions report as their real, live left edge, so the
    /// cutout physically cannot reach the sidebar regardless of what the
    /// left side's own measurement says.
    /// Now a safety net rather than the thing that supplies the visible
    /// gap: `TourRegion.spotlightInset` already pulls the left column's
    /// regions in by their own `columnInset`, so the margin the reference
    /// shows is there before this runs. 48 on top of that read as a wide
    /// dead band, so this is back to just enough to absorb the few points
    /// of measurement drift it exists for.
    private static let sidebarGap: CGFloat = 8

    /// The smallest gap a spotlight may leave between itself and the
    /// window's edge. Enough that the cutout's corner radius is fully
    /// drawn rather than clipped flat against the border.
    private static let windowMargin: CGFloat = 6

    private func clampedToSidebar(_ rect: CGRect, region: TourRegion) -> CGRect {
        guard region == .table || region == .playmat else { return rect }
        let sidebarRegions: [TourRegion] = [.phaseIndicator, .score, .startGame]
        guard let sidebarMinX = sidebarRegions.compactMap({ frames[$0]?.minX }).min() else { return rect }
        let maxWidth = max(0, sidebarMinX - rect.minX - Self.sidebarGap)
        guard rect.width > maxWidth else { return rect }
        return CGRect(x: rect.minX, y: rect.minY, width: maxWidth, height: rect.height)
    }

    @ViewBuilder
    private func fullScrim(in size: CGSize) -> some View {
        Rectangle()
            .fill(RiftboundPalette.tourScrim)
            .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    private func cutoutScrim(around cutout: CGRect, in size: CGSize) -> some View {
        Path { path in
            path.addRect(CGRect(origin: .zero, size: size))
            // Drawn on `cutout` exactly, with no expansion of its own —
            // every region now states its own breathing room as
            // `TourRegion.spotlightInset`, which is the only place that
            // can know whether a given frame needs pulling in (the
            // left column's padded, full-bleed frames) or pushing out
            // (the sidebar's snug ones). A blanket expansion here used to
            // do both jobs badly and silently cancelled part of the
            // sidebar clamp.
            //
            // 16, not 10 — the reference's highlighted box reads as a soft
            // rounded panel; 10 was closer to the sharp corner of an
            // ordinary control than a distinct "this is a spotlighted
            // card" shape.
            path.addRoundedRect(in: cutout, cornerSize: CGSize(width: 16, height: 16))
        }
        // `eoFill` is what turns the cutout into an actual hole — without
        // it the two shapes just fill on top of each other and the
        // "cutout" is invisible.
        .fill(RiftboundPalette.tourScrim, style: FillStyle(eoFill: true))
    }

    private func card(sprite: TourSprite, message: String, buttons: TourStepButtons) -> some View {
        TourCard(
            sprite: sprite,
            message: message,
            buttons: buttons,
            onExploreMyself: onExploreMyself,
            onShowMeAround: onShowMeAround,
            onSkip: onSkip,
            onAdvance: onAdvance,
            onFinish: onFinish
        )
        .frame(width: Self.cardWidth)
        // Keyed by *what's being said*, not just the step index — two
        // different steps can share a region, and without this SwiftUI
        // read that as "the same card, new text" and cross-faded the
        // wording instead of swapping it outright.
        .id(message)
    }

    /// `.position(_:)` places a view's *centre*, not its corner, so this
    /// still has to guess a card height to keep the math in one place
    /// rather than mixing `.position` for one axis and a corner-anchored
    /// `.offset` for the other. `estimatedCardHeight` comfortably covers
    /// two lines of body text plus the button row at `cardWidth`; a card
    /// that runs longer than that grows downward past its nominal centre,
    /// which reads as "slightly lower than planned," not as clipped or
    /// overlapping the cutout — the safer direction for an estimate to be
    /// wrong in.
    private func cardCenter(placement: TourCardPlacement, cutout: CGRect?, bounds: CGSize) -> CGPoint {
        let x: CGFloat
        let y: CGFloat
        switch placement {
        case .center:
            x = bounds.width / 2
            y = bounds.height / 2
        case .underToolbar:
            // Top-trailing: the toolbar's items are trailing-aligned in
            // the title bar, so this is the corner of the content area
            // nearest the control the step is about. Pressed right up
            // against the top edge on purpose — the shorter the gap
            // between the card and the real button above it, the more
            // the two read as one pointer.
            x = bounds.width - Self.cardWidth / 2 - 24
            y = Self.estimatedCardHeight / 2 + 16
        case .below:
            let cutout = cutout ?? CGRect(origin: .zero, size: bounds)
            // Centred on the cutout's own midpoint — and the cutout
            // passed in here is already `clampedToSidebar`'s narrowed
            // rect, not the raw measured one. Centring on the *raw*
            // rect's midpoint was the earlier bug: `.table`'s box runs
            // almost to the sidebar, so its true midpoint sits far
            // enough right that a centred card either overlapped the
            // sidebar or, once a separate clamp pulled it back, landed
            // in an arbitrary spot touching neither edge. Centring on
            // the already-narrowed cutout instead means "the middle of
            // the section" and "safely clear of the sidebar" are the
            // same point, with no second clamp needed.
            x = cutout.midX
            y = cutout.maxY + 16 + Self.estimatedCardHeight / 2
        case .leading:
            let cutout = cutout ?? CGRect(origin: .zero, size: bounds)
            x = cutout.minX - 16 - Self.cardWidth / 2
            y = cutout.minY + Self.estimatedCardHeight / 2
        }
        // Clamped so a region near an edge doesn't push the card half off
        // the window — better a card that overlaps its own cutout's edge
        // slightly than one you can't read the button row of.
        let clampedX = min(max(x, Self.cardWidth / 2 + 8), bounds.width - Self.cardWidth / 2 - 8)
        let clampedY = min(max(y, Self.estimatedCardHeight / 2 + 8), bounds.height - Self.estimatedCardHeight / 2 - 8)
        return CGPoint(x: clampedX, y: clampedY)
    }
}

/// The card itself: BonBon and one line of text in a bordered box, with
/// the button row sitting *below and outside* that box — matching the
/// reference exactly, and different from a first pass at this that put
/// the buttons inside the card's own padding.
private struct TourCard: View {
    let sprite: TourSprite
    let message: String
    let buttons: TourStepButtons
    let onExploreMyself: () -> Void
    let onShowMeAround: () -> Void
    let onSkip: () -> Void
    let onAdvance: () -> Void
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 18) {
                Image(sprite.imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 104, height: 104)
                    .accessibilityHidden(true)

                Self.styled(message)
                    .font(RiftboundFont.body)
                    .foregroundStyle(RiftboundPalette.regularText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Sprite, padding and spacing all scale with `cardWidth`
            // above. Growing the frame alone would have spent the extra
            // room on white space and a longer line length, which reads
            // as a looser card rather than a bigger one. The type stays
            // at `RiftboundFont.body` — 15pt is the only body size the
            // board carries, and the tour is not the place to invent a
            // sixteenth.
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: RiftboundLayout.cornerRadius, style: .continuous)
                    .fill(RiftboundPalette.mainBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: RiftboundLayout.cornerRadius, style: .continuous)
                    .stroke(RiftboundPalette.elementStroke, lineWidth: 2)
            )

            buttonRow
        }
    }

    /// Renders a step's message, turning any `{sf:name}` token into the
    /// live SF Symbol of that name, inline in the sentence.
    ///
    /// This exists for the two steps that describe a **toolbar** control:
    /// the tour cannot spotlight the title bar (see
    /// `TourRegion.isTitleBarHosted`), so "the camera button up top" has
    /// to be identifiable from the sentence alone. Showing the actual
    /// glyph the player is looking for does that in a way no amount of
    /// describing it in words does.
    ///
    /// Everything outside a token still goes through `LocalizedStringKey`,
    /// so `**bold**` keeps working either side of an icon.
    private static func styled(_ message: String) -> Text {
        let token = "{sf:"
        var result = Text("")
        var remainder = Substring(message)

        while let open = remainder.range(of: token),
              let close = remainder[open.upperBound...].firstIndex(of: "}") {
            let literal = remainder[..<open.lowerBound]
            if !literal.isEmpty { result = result + Text(.init(String(literal))) }
            let name = String(remainder[open.upperBound..<close])
            result = result + Text(Image(systemName: name))
            remainder = remainder[remainder.index(after: close)...]
        }

        // Whatever follows the last token — and, when there were none at
        // all, the entire message.
        if !remainder.isEmpty { result = result + Text(.init(String(remainder))) }
        return result
    }

    @ViewBuilder
    private var buttonRow: some View {
        switch buttons {
        case .skipAndNext(let nextLabel):
            HStack {
                Button("Skip tour", action: onSkip)
                    .buttonStyle(RiftPrimaryButtonStyle())
                Spacer()
                Button(nextLabel, action: onAdvance)
                    .buttonStyle(RiftPrimaryButtonStyle())
            }
        case .single(let label):
            HStack {
                Spacer()
                Button(label, action: onAdvance)
                    .buttonStyle(RiftPrimaryButtonStyle())
            }
        case .singleCentered(let label):
            HStack {
                Spacer()
                Button(label, action: onFinish)
                    .buttonStyle(RiftPrimaryButtonStyle())
                Spacer()
            }
        case .branch(let exploreLabel, let showMeLabel):
            HStack {
                Button(exploreLabel, action: onExploreMyself)
                    .buttonStyle(RiftPrimaryButtonStyle())
                Spacer()
                Button(showMeLabel, action: onShowMeAround)
                    .buttonStyle(RiftPrimaryButtonStyle())
            }
        case .skipOnly:
            HStack {
                Button("Skip tour", action: onSkip)
                    .buttonStyle(RiftPrimaryButtonStyle())
                Spacer()
            }
        }
    }
}

// MARK: - Geometry helpers

private extension CGRect {
    /// Per-edge inset. `CGRect.insetBy(dx:dy:)` only does symmetric pairs,
    /// and `TourRegion.spotlightInset` genuinely needs four different
    /// numbers — the strip's horizontal padding is twice its vertical
    /// slack. Negative values push the edge out, matching `insetBy`.
    func inset(by insets: EdgeInsets) -> CGRect {
        CGRect(
            x: minX + insets.leading,
            y: minY + insets.top,
            // `max(0, …)` so an inset larger than the rect collapses it to
            // an empty spotlight rather than inverting into a rectangle
            // drawn inside-out, which `eoFill` would render as a hole in
            // the wrong place entirely.
            width: max(0, width - insets.leading - insets.trailing),
            height: max(0, height - insets.top - insets.bottom)
        )
    }

    /// Pulls each edge back inside `bounds`, keeping `margin` clear of it.
    /// Only edges that actually stick out move, so a rect already well
    /// inside the window is returned untouched rather than resized.
    func clamped(within bounds: CGSize, margin: CGFloat) -> CGRect {
        let left = max(minX, margin)
        let top = max(minY, margin)
        let right = min(maxX, bounds.width - margin)
        let bottom = min(maxY, bounds.height - margin)
        // `max(0, …)` for the degenerate case where the margins overlap in
        // a very small window — an empty rect draws no hole, which beats
        // a negative-width one that `eoFill` would render inside-out.
        return CGRect(x: left, y: top, width: max(0, right - left), height: max(0, bottom - top))
    }
}
