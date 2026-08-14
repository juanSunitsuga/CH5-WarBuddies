import Testing
@testable import RiftboundExpertSystem

@Suite("Rune Channel Pace")
struct RuneChannelPaceTests {
    @Test("Before any turns, nothing is expected yet")
    func noTurnsYet() {
        let first = TestFixtures.makePlayer()
        let second = TestFixtures.makePlayer()
        #expect(RuneChannelPace.expectedRunesChanneled(for: first, turnOrder: [first, second], completedTurns: 0) == 0)
    }

    @Test("The first player expects a flat 2 per completed turn")
    func firstPlayerPace() {
        let first = TestFixtures.makePlayer()
        let second = TestFixtures.makePlayer()
        #expect(RuneChannelPace.expectedRunesChanneled(for: first, turnOrder: [first, second], completedTurns: 1) == 2)
        #expect(RuneChannelPace.expectedRunesChanneled(for: first, turnOrder: [first, second], completedTurns: 3) == 6)
    }

    @Test("The second player gets 3 on their first turn, then 2 per turn after (rule 515.3's first-turn extra)")
    func secondPlayerFirstTurnBonus() {
        let first = TestFixtures.makePlayer()
        let second = TestFixtures.makePlayer()
        #expect(RuneChannelPace.expectedRunesChanneled(for: second, turnOrder: [first, second], completedTurns: 1) == 3)
        #expect(RuneChannelPace.expectedRunesChanneled(for: second, turnOrder: [first, second], completedTurns: 2) == 5)
        #expect(RuneChannelPace.expectedRunesChanneled(for: second, turnOrder: [first, second], completedTurns: 3) == 7)
    }

    @Test("A single-player turnOrder never triggers the second-player bonus")
    func singlePlayerNoBonus() {
        let solo = TestFixtures.makePlayer()
        #expect(RuneChannelPace.expectedRunesChanneled(for: solo, turnOrder: [solo], completedTurns: 3) == 6)
    }
}
