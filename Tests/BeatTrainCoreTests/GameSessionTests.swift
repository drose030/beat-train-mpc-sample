import Testing
@testable import BeatTrainCore

struct GameSessionTests {
    private let timing = TimingConfiguration(totalSec: 0.12, frontSec: 0.05, offsetMs: 0)

    /// Kick at 1.0 s (pad 0), snare/red at 2.0 s (pad 4, lane 0 top).
    private func makeSession() throws -> GameSession {
        let tempo = try TempoMap(ppq: 480, changes: [(tick: 0, bpm: 120)])
        let chart = DrumChart(tempoMap: tempo, notes: [
            DrumNoteEvent(tick: 960, timeSec: 1.0, target: DrumTarget(lane: 0, row: .bottom), velocity: 100),
            DrumNoteEvent(tick: 1920, timeSec: 2.0, target: DrumTarget(lane: 0, row: .top), velocity: 100),
        ])
        return GameSession(chart: chart, kit: DrumKit(), timing: timing)
    }

    @Test func strikeWithinWindowHitsTheNote() throws {
        var session = try makeSession()
        let feedback = session.strike(pad: 0, at: 1.02)
        #expect(session.state(ofNote: 0) == .hit)
        #expect(session.score.hits == 1)
        #expect(feedback == [.flashTarget(DrumTarget(lane: 0, row: .bottom), isHit: true), .setDrumsMuted(false)])
    }

    @Test func strikeWithoutANoteIsAnOverhit() throws {
        var session = try makeSession()
        let feedback = session.strike(pad: 0, at: 1.5)
        #expect(session.score.overhits == 1)
        #expect(session.score.misses == 1)
        #expect(feedback.contains(.playMissSFX))
    }

    @Test func snarePadDoesNotHitTheKickNorTheOtherWayRound() throws {
        var session = try makeSession()
        _ = session.strike(pad: 4, at: 1.0)   // red, lane 0 top, at the kick
        _ = session.strike(pad: 0, at: 2.0)   // kick, lane 0 bottom, at the snare
        #expect(session.score.hits == 0)
        #expect(session.score.overhits == 2)
        _ = session.strike(pad: 4, at: 2.0)
        #expect(session.state(ofNote: 1) == .hit)
    }

    @Test func padSetToOffDoesNothing() throws {
        var session = try makeSession()
        #expect(session.strike(pad: 1, at: 1.0).isEmpty)
        #expect(session.score == ScoreState())
    }

    @Test func advancingPastTheWindowMissesPendingNotes() throws {
        var session = try makeSession()
        _ = session.strike(pad: 0, at: 1.0)
        let feedback = session.advance(to: 2.5)
        #expect(session.state(ofNote: 1) == .missed)
        #expect(session.score.misses == 1)
        #expect(session.score.streak == 0)
        #expect(feedback.first == .flashTarget(DrumTarget(lane: 0, row: .top), isHit: false))
        #expect(session.accuracy == 0.5)
    }

    @Test func runningAccuracyCountsOnlyJudgedNotes() throws {
        var session = try makeSession()
        #expect(session.runningAccuracy == 0)
        _ = session.strike(pad: 0, at: 1.0)
        #expect(session.runningAccuracy == 1)
        #expect(session.accuracy == 0.5)
    }

    @Test func finishesAfterTheOutro() throws {
        let session = try makeSession()
        #expect(!session.isFinished(at: 2.5))
        #expect(session.isFinished(at: 4.0))
    }
}
