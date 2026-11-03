import Testing
@testable import BeatTrainCore

struct DrumHitJudgeTests {

    private let timing = TimingConfiguration(totalSec: 0.12, frontSec: 0.06, offsetMs: 0)
    private let kit = DrumKit()

    /// Kick on lane 0 at 1.0s, snare (red) on lane 0-top at 2.0s. Both default-mapped
    /// to lane 0, in different rows.
    private func notes() -> [DrumNoteEvent] {
        [
            DrumNoteEvent(tick: 0, timeSec: 1.0, target: DrumTarget(lane: 0, row: .bottom), velocity: 100),
            DrumNoteEvent(tick: 0, timeSec: 2.0, target: DrumTarget(lane: 0, row: .top), velocity: 100),
        ]
    }

    @Test func hitsNearestPendingNoteInWindow() {
        // Input at 1.02s, within the 60ms back window of the 1.0s note.
        let judgement = DrumHitJudge.judgeInput(
            target: DrumTarget(lane: 0, row: .bottom), atTime: 1.02, notes: notes(), noteStates: [:], kit: kit, timing: timing
        )
        #expect(judgement == .hit(noteIndex: 0))
    }

    @Test func overhitWhenOutsideWindow() {
        // Input at 1.5s — between the two notes, outside both windows.
        let judgement = DrumHitJudge.judgeInput(
            target: DrumTarget(lane: 0, row: .bottom), atTime: 1.5, notes: notes(), noteStates: [:], kit: kit, timing: timing
        )
        #expect(judgement == .overhit)
    }

    @Test func skipsAlreadyJudgedNotes() {
        // Note 0 already hit → an input near it falls through to overhit.
        let judgement = DrumHitJudge.judgeInput(
            target: DrumTarget(lane: 0, row: .bottom), atTime: 1.0, notes: notes(), noteStates: [0: .hit], kit: kit, timing: timing
        )
        #expect(judgement == .overhit)
    }

    @Test func ignoresNotesOnOtherLanes() {
        let judgement = DrumHitJudge.judgeInput(
            target: DrumTarget(lane: 2, row: .bottom), atTime: 1.0, notes: notes(), noteStates: [:], kit: kit, timing: timing
        )
        #expect(judgement == .overhit)
    }

    @Test func ignoresTheOtherRowOfTheSameLane() {
        let judgement = DrumHitJudge.judgeInput(
            target: DrumTarget(lane: 0, row: .top), atTime: 1.0, notes: notes(), noteStates: [:], kit: kit, timing: timing
        )
        #expect(judgement == .overhit)
    }

    @Test func autoMissReturnsPendingNotesPastWindow() {
        // At 1.5s, the 1.0s note is past its 60ms back window; the 2.0s note isn't.
        let missed = DrumHitJudge.autoMissedNoteIndices(
            now: 1.5, notes: notes(), noteStates: [:], timing: timing
        )
        #expect(missed == [0])
    }

    @Test func autoMissSkipsAlreadyJudged() {
        let missed = DrumHitJudge.autoMissedNoteIndices(
            now: 1.5, notes: notes(), noteStates: [0: .hit], timing: timing
        )
        #expect(missed.isEmpty)
    }
}

struct ScoreStateTests {

    @Test func hitsBuildStreakAndMax() {
        var score = ScoreState()
        score.registerHit()
        score.registerHit()
        #expect(score.hits == 2)
        #expect(score.streak == 2)
        #expect(score.maxStreak == 2)
    }

    @Test func overhitCountsAsMissAndBreaksStreak() {
        var score = ScoreState()
        score.registerHit()
        score.registerOverhit()
        #expect(score.hits == 1)
        #expect(score.overhits == 1)
        #expect(score.misses == 1)
        #expect(score.streak == 0)
        #expect(score.maxStreak == 1) // preserved from before the break
    }

    @Test func autoMissesAddToMissesAndBreakStreak() {
        var score = ScoreState()
        score.registerHit()
        score.registerHit()
        score.registerMisses(3)
        #expect(score.misses == 3)
        #expect(score.streak == 0)
        #expect(score.maxStreak == 2)
    }

    @Test func zeroMissesIsNoOp() {
        var score = ScoreState()
        score.registerHit()
        score.registerMisses(0)
        #expect(score.streak == 1)
    }
}
