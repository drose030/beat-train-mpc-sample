import Testing
@testable import beattrain

/// The song clock's rules, with a stepped engine position or the timer.
struct SongClockTests {
    @Test func chartTimeAppliesDelayAndOffsetAndIsNeverNegative() {
        var position = 0.0
        var clock = SongClock(enginePosition: { position })
        clock.begin(now: 0)
        #expect(clock.chartTime(now: 1, chartDelayMs: 100, timingOffsetMs: 70) == -2, "counting in, in real seconds")
        let starts = clock.tick(now: 3)
        #expect(starts, "the music starts")
        position = 2
        #expect(abs(clock.chartTime(now: 99, chartDelayMs: 100, timingOffsetMs: 70) - 1.83) < 1e-9, "the engine is the clock")
        position = 0.05
        #expect(clock.chartTime(now: 99, chartDelayMs: 100, timingOffsetMs: 70) == 0)
    }

    @Test func theOffsetShrinksWithTheSpeed() {
        var clock = SongClock(enginePosition: { 2 })
        clock.begin(now: 0)
        _ = clock.tick(now: 3)
        let changed = clock.setSpeed(0.52, now: 3), again = clock.setSpeed(0.5, now: 3)
        #expect(changed && clock.speed == 0.5)
        #expect(!again, "no change")
        #expect(abs(clock.chartTime(now: 3, chartDelayMs: 0, timingOffsetMs: 40) - 1.98) < 1e-9)
    }

    @Test func pauseBackFromTheSettingsCountsInThenPlays() {
        var clock = SongClock(enginePosition: nil)
        clock.begin(now: 0)
        _ = clock.tick(now: 3)
        let paused = clock.pause(now: 5), pausedAgain = clock.pause(now: 5)
        #expect(paused && !pausedAgain, "the second time it is already paused")
        clock.resumeAfterCountIn(now: 10)
        #expect(clock.resumesAt == 10 + SongClock.resumeCountInSec)
        let early = clock.tick(now: 12)
        #expect(!early && clock.isPaused, "3, 2, 1")
        let on = clock.tick(now: 13)
        #expect(on, "and on: the music plays again")
        #expect(clock.chartTime(now: 14, chartDelayMs: 0, timingOffsetMs: 0) == 3, "2 s before the pause, 1 s after")
    }

    @Test func backFromTheSettingsDuringTheCountInGoesOnAtOnce() {
        var clock = SongClock(enginePosition: nil)
        clock.begin(now: 0)
        _ = clock.pause(now: 1)
        clock.resumeAfterCountIn(now: 5)
        #expect(!clock.isPaused && clock.resumesAt == nil)
        #expect(clock.startsAt == 7, "the count-in held while paused")
    }

    @Test func stoppedItRunsNoMore() {
        var clock = SongClock(enginePosition: nil)
        clock.begin(now: 0)
        clock.stop()
        let starts = clock.tick(now: 5)
        #expect(!clock.isRunning && !starts)
    }
}
