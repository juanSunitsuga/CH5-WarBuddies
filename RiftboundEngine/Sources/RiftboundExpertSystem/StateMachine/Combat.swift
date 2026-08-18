/// Rule 624–628: what happens once a Combat Showdown closes.
///
/// The Showdown is the *window* (players get to act); this is the
/// resolution that follows it. Ordering matters and is fixed:
///
///     626 Combat Damage → 627 Resolution → 628 Cleanup
///
/// Only reached from a Showdown whose `origin` is `.combat` — a standalone
/// Showdown (516.5.b: units moving to an *empty* Battlefield) has no
/// opposing units to fight, so it ends with no damage and no Conquer, which
/// is why `resolve` returns early on that origin rather than treating an
/// empty defender set as a win.
public enum Combat {
    public struct Outcome: Sendable {
        public var state: GameState
        public var events: [PlayerInstruction]
    }

    /// Runs 626–628 for a Showdown that has just closed.
    ///
    /// 627.3 is the rule the whole thing exists to reach: *the Battlefield
    /// is Conquered if no Defending Units remain but Attacking Units do*.
    /// That — not "the attacker played more spells" — is what winning a
    /// Showdown as the attacker means, and it's what hands Control over
    /// (627.3.a) and triggers the Conquer score (630.1).
    public static func resolve(_ showdown: Showdown, in state: GameState) -> Outcome {
        var state = state
        var events: [PlayerInstruction] = []
        let battlefieldID = battlefield(of: showdown.origin)

        if case .combat(let attacker, let defender, _) = showdown.origin {
            assignCombatDamage(attacker: attacker, defender: defender, at: battlefieldID, in: &state)  // 626
            killLethallyDamagedUnits(at: battlefieldID, in: &state)                                     // 627.1

            let survivors = state.units.values.filter { $0.location == .battlefield(battlefieldID) }
            let attackersRemain = survivors.contains { $0.controller == attacker }
            let defendersRemain = survivors.contains { $0.controller == defender }

            // 627.2: both sides left standing — the attack failed, and the
            // Attacking Units are Recalled to their Base (616). Doing this
            // *before* establishing Control is what makes the defender keep
            // the Battlefield: by 181.4.a Control follows who has Units
            // there, and after the recall that's only the defender.
            //
            // Currently unreachable through combat damage alone, and the
            // arithmetic says so rather than the implementation: both sides
            // surviving needs each side's summed Might to be too small to
            // kill any single unit opposite, i.e. attackerSum < defenderMin
            // and defenderSum < attackerMin. Since a sum is never less than
            // its own smallest term, that chains to attackerMin < attackerMin.
            // So this branch only opens once something can blunt damage —
            // Shield (726), Deflect (721), damage prevention — none of which
            // are modeled yet. Kept because it is the rule, and because the
            // moment Shield lands this is the behavior it needs.
            if attackersRemain, defendersRemain {
                for unit in survivors where unit.controller == attacker {
                    state.units[unit.id]?.location = .base(unit.controller)
                }
            }
        }
        // 516.5.b.1: a standalone Showdown has no Combat and so no damage
        // step — the Units that moved in are simply still there. Control is
        // then established the same way for both origins, below.

        events += establishControl(at: battlefieldID, in: &state)

        clearContested(battlefieldID, in: &state)   // 627.4 / 181.3.b

        // 627.5/139.3.b.2: clear marked damage from all Units at all
        // Locations — every Location, not only this Battlefield.
        for id in state.units.keys {
            state.units[id]?.damage = 0
        }

        state = Cleanup.run(state)                   // 628
        return Outcome(state: state, events: events)
    }

    /// Rule 181.4: Control is established by the presence of Units.
    ///
    ///   - 181.4.a: a player with Units at a Battlefield, outside of
    ///     Combat, Controls it.
    ///   - 181.4.c: Control changes immediately if, at the end of Combat,
    ///     the Units there are controlled by a different player.
    ///   - 181.4.d: a player with no Units there has no Control of it.
    ///
    /// Gaining Control this way is exactly rule 630.1's definition of a
    /// Conquer, which is why the score is awarded here rather than only on
    /// the 627.3 combat path — moving unopposed into an empty Battlefield
    /// and surviving the standalone Showdown conquers it just as much as
    /// killing the defenders does.
    ///
    /// Contested Battlefields with two sides still present keep their
    /// existing Controller (181.4.b) — that state is a Combat waiting to
    /// happen, not a change of hands.
    private static func establishControl(
        at battlefieldID: BattlefieldID,
        in state: inout GameState
    ) -> [PlayerInstruction] {
        let present = Set(
            state.units.values
                .filter { $0.location == .battlefield(battlefieldID) }
                .map(\.controller)
        )
        let previous = state.battlefieldControl[battlefieldID]?.controller

        guard present.count == 1, let claimant = present.first else {
            if present.isEmpty {
                state.battlefieldControl[battlefieldID]?.controller = nil   // 181.4.d
            }
            return []   // 181.4.b: still contested by two sides — no change.
        }

        guard claimant != previous else { return [] }

        state.battlefieldControl[battlefieldID]?.controller = claimant
        return Scoring.scoreConquer(battlefieldID, by: claimant, in: &state)   // 630.1
    }

    /// 627.1: Units with Lethal Damage are removed, to their **owner's**
    /// Trash (107.1.d — owner, not controller, so a stolen Unit goes home).
    private static func killLethallyDamagedUnits(at battlefieldID: BattlefieldID, in state: inout GameState) {
        let killed = state.units.values.filter {
            $0.location == .battlefield(battlefieldID) && isLethallyDamaged($0)
        }
        for unit in killed {
            state.units[unit.id] = nil
            state.zones[unit.owner]?.trash.append(
                MainDeckCard(
                    id: unit.id,
                    definitionID: unit.cardDefinitionID,
                    owner: unit.owner,
                    name: unit.name,
                    type: .unit(isChampion: unit.isChampion),
                    might: unit.baseMight
                )
            )
        }
    }

    /// Rule 626.1: both sides deal damage equal to their summed Might.
    ///
    /// 626.1.a: this step only happens if Units from *both* sides remain;
    /// otherwise no Combat occurred and we skip straight to Resolution.
    ///
    /// Damage assignment (626.1.d) is formally the assigning player's
    /// choice, but the rules constrain it hard enough that a canonical
    /// order is faithful for the cases this engine can currently see:
    /// 626.1.d.1 puts Tank units first, and 626.1.d.2 requires each unit be
    /// assigned Lethal Damage *in full* before any damage goes to the next.
    /// So the only real freedom is which equal-priority unit to hit first
    /// (626.1.d.4), resolved here by a stable ID sort.
    ///
    /// NOT modeled, and each would change the numbers: Assault/Shield
    /// modulating Might during a Showdown (625.1.b.1/2), Deflect (721), and
    /// "assign me last" restrictions like Caitlyn's (626.1.d.3). Might is
    /// `printedMightClamped`, since the Layers-aware calculator (637)
    /// doesn't exist — a buffed or debuffed Unit fights at its printed
    /// value here. Flagged rather than approximated silently.
    private static func assignCombatDamage(
        attacker: PlayerID,
        defender: PlayerID,
        at battlefieldID: BattlefieldID,
        in state: inout GameState
    ) {
        let present = state.units.values.filter { $0.location == .battlefield(battlefieldID) }
        let attackingUnits = present.filter { $0.controller == attacker }
        let defendingUnits = present.filter { $0.controller == defender }

        // 626.1.a: no Combat Damage Step unless both sides are present.
        guard !attackingUnits.isEmpty, !defendingUnits.isEmpty else { return }

        let attackerMight = attackingUnits.reduce(0) { $0 + $1.printedMightClamped }  // 626.1.b
        let defenderMight = defendingUnits.reduce(0) { $0 + $1.printedMightClamped }  // 626.1.c

        // 626.1.d: "Starting with the Attacker" — the order is stated by
        // the rule, though with damage marked and resolved simultaneously
        // at 627.1 it doesn't change the outcome today. Kept in rule order
        // so it stays right if a future effect reacts to assignment.
        distribute(attackerMight, among: defendingUnits, in: &state)
        distribute(defenderMight, among: attackingUnits, in: &state)
    }

    /// 626.1.d.1/d.2: Tank first, then lethal-in-full per unit before
    /// moving on. Leftover damage too small to be lethal still gets marked
    /// on the next unit — 626.1.d.2 bars *splitting* below lethal while
    /// more units could be killed, not marking a final remainder.
    private static func distribute(_ damage: Int, among units: [Unit], in state: inout GameState) {
        var remaining = damage
        let ordered = units.sorted { lhs, rhs in
            let lhsTank = lhs.printedKeywords.contains(.tank) || lhs.grantedKeywords.contains(.tank)
            let rhsTank = rhs.printedKeywords.contains(.tank) || rhs.grantedKeywords.contains(.tank)
            if lhsTank != rhsTank { return lhsTank }                     // 626.1.d.1
            return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString  // 626.1.d.4
        }

        for unit in ordered {
            guard remaining > 0 else { break }
            let lethal = max(1, unit.printedMightClamped - unit.damage)
            let assigned = min(remaining, lethal)
            state.units[unit.id]?.damage += assigned
            remaining -= assigned
        }
    }

    /// Rule 520/627.1: nonzero damage equal to or exceeding the Unit's
    /// Might. Uses printed Might for the same reason `assignCombatDamage`
    /// does — the Layers calculator (637) isn't built.
    static func isLethallyDamaged(_ unit: Unit) -> Bool {
        unit.damage > 0 && unit.damage >= unit.printedMightClamped
    }

    /// Rule 627.4/181.3.b: the Contested status is temporary and ends with
    /// the Showdown that it opened.
    private static func clearContested(_ battlefieldID: BattlefieldID, in state: inout GameState) {
        state.battlefieldControl[battlefieldID]?.isContested = false
        state.battlefieldControl[battlefieldID]?.contestedBy = nil
    }

    private static func battlefield(of origin: Showdown.Origin) -> BattlefieldID {
        switch origin {
        case .combat(_, _, let battlefieldID): return battlefieldID
        case .standalone(let battlefieldID): return battlefieldID
        }
    }
}
