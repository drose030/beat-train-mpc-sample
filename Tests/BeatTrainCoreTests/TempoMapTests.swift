import Testing
@testable import BeatTrainCore

struct TempoMapTests {

    @Test func convertsTicksToSecondsAtConstantTempo() throws {
        // 120 BPM at ppq 480 → one beat (480 ticks) = 0.5s.
        let map = try TempoMap(ppq: 480, changes: [(tick: 0, bpm: 120)])
        #expect(abs(map.seconds(forTick: 0) - 0.0) < 1e-9)
        #expect(abs(map.seconds(forTick: 480) - 0.5) < 1e-9)
        #expect(abs(map.seconds(forTick: 960) - 1.0) < 1e-9)
        #expect(abs(map.seconds(forTick: 240) - 0.25) < 1e-9)
    }

    @Test func accumulatesAcrossTempoChanges() throws {
        // 120 BPM for the first beat (0.5s), then 240 BPM.
        let map = try TempoMap(ppq: 480, changes: [(tick: 0, bpm: 120), (tick: 480, bpm: 240)])
        #expect(abs(map.seconds(forTick: 480) - 0.5) < 1e-9)
        // One more beat at 240 BPM = 0.25s → total 0.75s at tick 960.
        #expect(abs(map.seconds(forTick: 960) - 0.75) < 1e-9)
    }

    @Test func acceptsUnsortedChanges() throws {
        let sorted = try TempoMap(ppq: 480, changes: [(tick: 0, bpm: 120), (tick: 480, bpm: 240)])
        let unsorted = try TempoMap(ppq: 480, changes: [(tick: 480, bpm: 240), (tick: 0, bpm: 120)])
        #expect(sorted == unsorted)
    }

    @Test func backfillsLeadingSegmentWithFirstKnownBPM() throws {
        // First tempo isn't at tick 0 → the span before it uses 240 BPM, not a
        // hardcoded 120.
        let map = try TempoMap(ppq: 480, changes: [(tick: 480, bpm: 240)])
        // 240 BPM → one beat = 0.25s, so tick 480 sits at 0.25s.
        #expect(abs(map.seconds(forTick: 480) - 0.25) < 1e-9)
        #expect(abs(map.seconds(forTick: 0) - 0.0) < 1e-9)
    }

    @Test func throwsWhenNoTempo() {
        #expect(throws: TempoMap.Failure.self) {
            _ = try TempoMap(ppq: 480, changes: [])
        }
    }

    @Test func throwsOnInvalidResolution() {
        #expect(throws: TempoMap.Failure.self) {
            _ = try TempoMap(ppq: 0, changes: [(tick: 0, bpm: 120)])
        }
    }

    @Test func beatTimesSpanThroughLastTick() throws {
        let map = try TempoMap(ppq: 480, changes: [(tick: 0, bpm: 120)])
        let beats = map.beatTimes(throughTick: 960)
        #expect(beats.count == 3) // ticks 0, 480, 960
        #expect(abs(beats[0] - 0.0) < 1e-9)
        #expect(abs(beats[1] - 0.5) < 1e-9)
        #expect(abs(beats[2] - 1.0) < 1e-9)
    }

    @Test func beatTimesEmptyForNonPositiveTick() throws {
        let map = try TempoMap(ppq: 480, changes: [(tick: 0, bpm: 120)])
        #expect(map.beatTimes(throughTick: 0).isEmpty)
    }
}
