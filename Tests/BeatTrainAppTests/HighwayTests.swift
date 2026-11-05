@testable import BeatTrainCore
import Testing
@testable import beattrain

/// The highway's geometry: which pads get a lane, in which order, and where
/// notes and beats lie.
struct HighwayTests {
    private func session(_ targets: [DrumTarget]) throws -> GameSession {
        let tempo = try TempoMap(ppq: 480, changes: [(tick: 0, bpm: 120)])
        let notes = targets.enumerated().map { DrumNoteEvent(tick: $0.offset * 480, timeSec: Double($0.offset) / 2, target: $0.element, velocity: 100) }
        return GameSession(chart: DrumChart(tempoMap: tempo, notes: notes), kit: DrumKit(), timing: PlayerSettings().timing)
    }

    @Test func onlyUsedPadsCymbalsOnTopKickAtTheBottom() throws {
        let kick = DrumTarget(lane: 0, row: .bottom), snare = DrumTarget(lane: 0, row: .top), cymbal = DrumTarget(lane: 3, row: .top)
        let rows = Highway.chartPads(of: try session([kick, snare, cymbal, snare]), kit: DrumKit())
        #expect(rows == [cymbal, snare, kick].map(DrumKit.pad(forLayout:)))
    }

    @Test func byPadLanesFollowThePanel() {
        let pads = [DrumTarget(lane: 3, row: .top), DrumTarget(lane: 0, row: .top), DrumTarget(lane: 0, row: .bottom), DrumTarget(lane: 3, row: .bottom)]
            .map(DrumKit.pad(forLayout:))
        // Panel column by column, the upper panel row (the kick's) first.
        let expected = [DrumTarget(lane: 0, row: .bottom), DrumTarget(lane: 0, row: .top), DrumTarget(lane: 3, row: .bottom), DrumTarget(lane: 3, row: .top)]
            .map(DrumKit.pad(forLayout:))
        #expect(Highway.padLanes(pads) == expected)
    }

    @Test func withoutNotesEveryPadWithAVoice() throws {
        let rows = Highway.chartPads(of: try session([]), kit: DrumKit())
        #expect(rows.count == (0..<DrumKit.padCount).filter { DrumKit().voice(forPad: $0) != .off }.count)
        #expect(rows.last == DrumKit.pad(forLayout: DrumTarget(lane: 0, row: .bottom)), "kick at the bottom")
    }

    @Test func timesLieAlongTheWayTheNotesRun() throws {
        let kit = DrumKit(), pads = Highway.chartPads(of: try session([]), kit: kit)
        // Down the vertical highways: what is to come lies above the line.
        let down = Highway(layout: .vertical, strikeLine: .edge, chartPads: pads, kit: kit)
        #expect(down.strike == Highway.bottom - 14)
        #expect(down.position(of: 10, at: 10) == down.strike)
        #expect(down.position(of: 11, at: 10) == down.strike - Int(Highway.pixelsPerSecond))
        // Left on the horizontal one: what is to come lies right of it.
        let left = Highway(layout: .horizontal, strikeLine: .middle, chartPads: pads, kit: kit)
        #expect(left.strike == 176)
        #expect(left.position(of: 10.5, at: 10) == 176 + 63)
    }

    @Test func notesShowFromTheEndOfTheHighwayToItsFarEnd() throws {
        let kick = DrumTarget(lane: 0, row: .bottom), cymbal = DrumTarget(lane: 3, row: .top)
        // Notes every half second from 0 to 3.5 s.
        let session = try session([kick, cymbal, kick, cymbal, kick, cymbal, kick, cymbal])
        let kit = DrumKit()
        let highway = Highway(layout: .horizontal, strikeLine: .edge, chartPads: Highway.chartPads(of: session, kit: kit), kit: kit)
        // 42 px back to the panel maps (0.34 s), 246 px ahead (1.97 s).
        let notes = highway.notes(of: session, at: 1)
        #expect(notes.map(\.index) == [2, 3, 4, 5])
        #expect(notes.map(\.lane) == [1, 0, 1, 0], "cymbal row on top")
        #expect(highway.beats([0.5, 1, 2.8, 3.1], at: 1) == [highway.strike, highway.strike + 225])
    }

    @Test func byPadLanesShareTheHighwayWidth() throws {
        let kick = DrumTarget(lane: 0, row: .bottom), snare = DrumTarget(lane: 0, row: .top), cymbal = DrumTarget(lane: 3, row: .top)
        let session = try session([kick, snare, cymbal])
        let kit = DrumKit()
        let highway = Highway(layout: .verticalByPad, strikeLine: .edge, chartPads: Highway.chartPads(of: session, kit: kit), kit: kit)
        #expect(highway.lanes == [[kick], [snare], [cymbal]].map { $0.map(DrumKit.pad(forLayout:)) })
        #expect(highway.laneSize == 66 && highway.laneOrigin(0) == 1)
        #expect(highway.lane(of: DrumTarget(lane: 2, row: .top)) == nil, "no lane for a pad without notes")
    }
}

/// What the play screen shows of strikes and judgements, per pad and per lane.
struct PadFeedbackTests {
    @Test func strikesAndJudgementsShowForAMoment() {
        var feedback = PadFeedback()
        let snare = DrumKit.pad(forLayout: DrumTarget(lane: 0, row: .top))
        feedback.strike(pad: snare, at: 10)
        feedback.judge(DrumTarget(lane: 0, row: .top), isHit: true, at: 10)
        #expect(feedback.isStruck(pad: snare, at: 10.1))
        #expect(!feedback.isStruck(pad: snare, at: 10 + PadFeedback.strikeSec))
        #expect(feedback.judgement(ofPad: snare, at: 10.1) == true)
        #expect(feedback.judgement(ofPad: snare, at: 10.2) == nil)
        #expect(feedback.struckPad(inLane: 0, at: 10.05) == snare)
        #expect(feedback.struckPad(inLane: 0, at: 10.1) == nil, "the lane's tint is shorter")
        #expect(feedback.struckPad(inLane: 1, at: 10.05) == nil)
    }

    @Test func aLaneShowsItsLatestJudgement() {
        var feedback = PadFeedback()
        feedback.judge(DrumTarget(lane: 0, row: .top), isHit: true, at: 10)
        feedback.judge(DrumTarget(lane: 0, row: .bottom), isHit: false, at: 10.05)
        #expect(feedback.judgement(ofLane: 0, at: 10.1) == false)
        #expect(feedback.judgement(ofPad: DrumKit.pad(forLayout: DrumTarget(lane: 0, row: .top)), at: 10.1) == true)
    }
}
