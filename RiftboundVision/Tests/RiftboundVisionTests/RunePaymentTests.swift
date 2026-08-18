import Testing
import RiftboundExpertSystem
@testable import RiftboundVision

/// Rules 130.2/130.3 and 157.2: can the player actually pay for what they
/// just put down?
///
/// The whole difficulty is that **one Rune pays one thing**. Energy comes
/// from Exhausting a Rune, Power from Recycling one, and a single Rune can
/// do either but not both.
@Suite("Rune Payment")
struct RunePaymentTests {

    private func ready(_ domain: Domain) -> ObservedRune { ObservedRune(domain: domain, stance: .ready) }
    private func spent(_ domain: Domain) -> ObservedRune { ObservedRune(domain: domain, stance: .exhausted) }

    // MARK: - Energy (157.2.a)

    @Test("Enough ready runes covers an energy cost")
    func readyRunesCoverEnergy() {
        let verdict = RunePayment.verdict(
            energy: 2, power: 0, eligibleDomains: [],
            runes: [ready(.fury), ready(.calm), ready(.mind)]
        )
        #expect(verdict.isAffordable)
    }

    /// You can't turn a rune that's already sideways, so an Exhausted Rune
    /// is worth nothing toward Energy no matter how many there are.
    @Test("Already-exhausted runes don't pay energy")
    func exhaustedRunesDoNotPayEnergy() {
        let verdict = RunePayment.verdict(
            energy: 2, power: 0, eligibleDomains: [],
            runes: [spent(.fury), spent(.calm), ready(.mind)]
        )
        #expect(verdict == .unaffordable(.energy(required: 2, available: 1)))
    }

    // MARK: - Power (157.2.b)

    /// Recycling returns the card to the Rune Deck; whether it was upright
    /// first doesn't matter. So an Exhausted Rune still pays Power.
    @Test("An exhausted rune still pays power")
    func exhaustedRunePaysPower() {
        let verdict = RunePayment.verdict(
            energy: 0, power: 1, eligibleDomains: [.chaos],
            runes: [spent(.chaos)]
        )
        #expect(verdict.isAffordable)
    }

    @Test("Power must come from a domain the card accepts")
    func powerRequiresMatchingDomain() {
        let verdict = RunePayment.verdict(
            energy: 0, power: 1, eligibleDomains: [.chaos],
            runes: [ready(.fury), ready(.calm)]
        )
        #expect(verdict == .unaffordable(.power(required: 1, available: 0, eligibleDomains: [.chaos])))
    }

    @Test("A dual-domain cost accepts either domain")
    func dualDomainCostAcceptsEither() {
        let verdict = RunePayment.verdict(
            energy: 0, power: 2, eligibleDomains: [.fury, .chaos],
            runes: [ready(.fury), ready(.chaos)]
        )
        #expect(verdict.isAffordable)
    }

    // MARK: - The interaction, which is the point

    /// The case the naive implementation gets wrong. 1 energy + 1 Chaos
    /// power, holding an exhausted Chaos rune and a ready Fury rune.
    ///
    /// Pay the Power with the **exhausted** Chaos rune — it was useless for
    /// Energy anyway — and the ready Fury rune covers the Energy. Reach for
    /// a ready rune to pay Power first and this reads as unaffordable, and
    /// the app tells the player to put back a card they could legally play.
    @Test("Power is paid with exhausted runes first, so ready ones survive for energy")
    func powerPrefersExhaustedRunes() {
        let verdict = RunePayment.verdict(
            energy: 1, power: 1, eligibleDomains: [.chaos],
            runes: [spent(.chaos), ready(.fury)]
        )
        #expect(verdict.isAffordable)
    }

    /// The same shape, but the only Chaos rune is the ready one — so paying
    /// Power has to consume it, and nothing is left to exhaust for Energy.
    @Test("When power must take the last ready rune, energy comes up short")
    func powerConsumingTheLastReadyRuneStarvesEnergy() {
        let verdict = RunePayment.verdict(
            energy: 1, power: 1, eligibleDomains: [.chaos],
            runes: [ready(.chaos), spent(.fury)]
        )
        #expect(verdict == .unaffordable(.energy(required: 1, available: 0)))
    }

    /// One rune cannot be both exhausted for energy and recycled for power.
    @Test("A single rune can't pay both energy and power")
    func oneRuneCannotPayTwice() {
        let verdict = RunePayment.verdict(
            energy: 1, power: 1, eligibleDomains: [.fury],
            runes: [ready(.fury)]
        )
        #expect(!verdict.isAffordable)
    }

    @Test("A free card is always affordable, even with no runes at all")
    func freeCardIsAlwaysAffordable() {
        #expect(RunePayment.verdict(energy: 0, power: 0, eligibleDomains: [], runes: []).isAffordable)
    }

    /// An empty `eligibleDomains` means the Power cost is domainless — the
    /// same reading the engine's `Cost.eligibleDomains` gets — so any rune
    /// pays it.
    @Test("A domainless power cost accepts any rune")
    func domainlessPowerAcceptsAnyRune() {
        let verdict = RunePayment.verdict(
            energy: 0, power: 2, eligibleDomains: [],
            runes: [ready(.fury), spent(.order)]
        )
        #expect(verdict.isAffordable)
    }
}
