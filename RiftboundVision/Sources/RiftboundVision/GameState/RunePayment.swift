import RiftboundExpertSystem

/// One Rune as the camera currently sees it in a Rune Area.
public struct ObservedRune: Sendable, Equatable {
    public let domain: Domain
    public let stance: CardStance

    public init(domain: Domain, stance: CardStance) {
        self.domain = domain
        self.stance = stance
    }

    public var isReady: Bool { stance == .ready }
}

/// Can the player actually pay for the card they just put down?
///
/// The rule that makes this non-trivial: **one Rune pays one thing.**
/// Energy comes from Exhausting a Rune (157.2.a, `[T]: Add [1]`) and Power
/// comes from Recycling one (157.2.b, `Recycle this: Add [C]`). A single
/// Rune can do either, never both — so "I have 4 runes and this costs 2
/// energy + 2 power" is affordable only if the domains line up *and* enough
/// of them are still upright.
///
/// Two asymmetries fall out of that, and both matter at the table:
///
/// - **Energy needs a Ready Rune.** You can't turn a rune that's already
///   sideways, so already-spent Runes don't count toward Energy.
/// - **Power doesn't care about stance.** Recycling returns the card to the
///   Rune Deck; whether it was upright first is irrelevant.
///
/// Which is why the assignment isn't greedy-in-order: Power should be paid
/// with **Exhausted** Runes wherever possible, since those are worthless for
/// Energy anyway. Paying Power with a Ready Rune when an Exhausted one of
/// the same Domain was available can turn an affordable card into a
/// rejection.
public enum RunePayment {

    /// Why a card can't be paid for, in the terms the player needs to fix it.
    public enum Shortfall: Sendable, Equatable {
        /// Not enough Runes of a Domain this card accepts, to Recycle for
        /// its Power cost (130.3/157.2.b).
        case power(required: Int, available: Int, eligibleDomains: [Domain])
        /// Not enough *Ready* Runes left to Exhaust for its Energy cost
        /// (130.2/157.2.a). `available` counts only upright Runes not
        /// already committed to the Power cost.
        case energy(required: Int, available: Int)
    }

    public enum Verdict: Sendable, Equatable {
        case affordable
        case unaffordable(Shortfall)

        public var isAffordable: Bool { self == .affordable }
    }

    /// Whether `runes` can cover `energy` + `power`.
    ///
    /// `eligibleDomains` empty means the Power cost is domainless and any
    /// Rune can pay it — the same reading `Cost.eligibleDomains` gets in the
    /// engine. A zero Power cost skips the Domain question entirely.
    public static func verdict(
        energy: Int,
        power: Int,
        eligibleDomains: [Domain],
        runes: [ObservedRune]
    ) -> Verdict {
        let eligible = power > 0
            ? runes.filter { eligibleDomains.isEmpty || eligibleDomains.contains($0.domain) }
            : []

        // Spend Exhausted Runes on Power first: they can't pay Energy, so
        // using them here costs nothing, while spending a Ready one might.
        let eligibleExhausted = eligible.filter { !$0.isReady }.count
        let eligibleReady = eligible.count - eligibleExhausted

        let powerFromExhausted = min(power, eligibleExhausted)
        let powerFromReady = power - powerFromExhausted

        guard powerFromReady <= eligibleReady else {
            return .unaffordable(.power(
                required: power,
                available: eligible.count,
                eligibleDomains: eligibleDomains
            ))
        }

        // Every Ready Rune not committed to Power is still available to
        // Exhaust for Energy.
        let readyLeft = runes.filter(\.isReady).count - powerFromReady
        guard readyLeft >= energy else {
            return .unaffordable(.energy(required: energy, available: max(0, readyLeft)))
        }

        return .affordable
    }
}
