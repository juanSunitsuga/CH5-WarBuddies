import Testing
@testable import RiftboundTextProcessing

/// A card whose origin was never observed — it appeared already on the
/// board, or its track dropped and was re-acquired — used to be reported
/// with `sourceRegion: "Hand"`, which turned a *missed observation* into a
/// confident "the player played this card from hand." That's the one
/// failure mode in this pipeline that produces a wrong answer rather than
/// a missing one, so it gets its own tests.
@Suite("Unobserved Origin")
struct UnobservedOriginTests {
    private let engine = ActionTranslatingEngine()

    /// "Sai Scout" is a Unit in the shipped database, so this reaches the
    /// Unit branch with authoritative type and no reliance on the CoreML
    /// classifier.
    private func unitEvent(sourceRegion: String?) -> ObservedTableEvent {
        ObservedTableEvent(
            cardID: "ogn-unit-under-test",
            cardName: "Sai Scout",
            ocrText: "",
            sourceRegion: sourceRegion,
            destinationRegion: "Battlefield"
        )
    }

    @Test("A Unit with an unobserved origin is rejected, not assumed to be played from hand")
    func unknownOriginIsRejected() async {
        guard case .rejected(let reason) = await engine.inferAction(event: unitEvent(sourceRegion: nil)) else {
            Issue.record("An unobserved origin must not resolve to a play")
            return
        }
        // The reason has to name the actual problem — a generic "illegal
        // move" would send someone hunting for a rules bug that isn't there.
        #expect(reason.lowercased().contains("observe"))
    }

    @Test("The same Unit observed leaving the Hand is accepted")
    func observedHandOriginIsAccepted() async {
        guard case .playUnit(_, let name, _, let zone, _) = await engine.inferAction(event: unitEvent(sourceRegion: "Hand")) else {
            Issue.record("A Unit observed moving Hand → Battlefield should be a play")
            return
        }
        #expect(name == "Sai Scout")
        #expect(zone == "Battlefield")
    }

    @Test("A Unit observed coming from somewhere other than the Hand is still rejected")
    func nonHandOriginIsRejected() async {
        guard case .rejected = await engine.inferAction(event: unitEvent(sourceRegion: "Base")) else {
            Issue.record("Only Hand → Base/Battlefield is a play")
            return
        }
    }
}
