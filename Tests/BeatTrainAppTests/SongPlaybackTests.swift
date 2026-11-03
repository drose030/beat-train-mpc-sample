import Foundation
import Testing
@testable import BeatTrainCore
@testable import beattrain
import MPCHardware

/// The song clock and its sounds, through `SongPlayback`'s interface.
struct SongPlaybackTests {
    /// A song without stem files (its folder does not exist), with a chart delay.
    private func song(delayMs: Double = 0) -> SongMetadata {
        let folder = URL(fileURLWithPath: "/nonexistent/beattrain-test-song")
        return SongMetadata(id: folder.path, title: "T", artist: "A", album: nil, hasDrumTrack: true, drumDifficulty: nil,
                            chartDelayMilliseconds: delayMs, songFolderURL: folder, notesURL: nil, audioURL: nil)
    }

    @Test func countInThenTimerWithDelayAndOffset() {
        let playback = SongPlayback(audio: nil)
        playback.apply(PlayerSettings(timingOffsetMs: 20))
        playback.load(song(delayMs: 100), beatTimes: [])
        playback.begin(now: 10)
        #expect(playback.chartTime(now: 11) == -2, "counting in")
        playback.tick(now: 13)
        #expect(abs(playback.chartTime(now: 14) - 0.88) < 1e-9, "1 s minus 100 ms delay minus 20 ms offset")
    }

    @Test func pauseHoldsTheCountIn() {
        let playback = SongPlayback(audio: nil)
        playback.load(song(), beatTimes: [])
        playback.begin(now: 0)
        playback.pause(now: 1)
        #expect(playback.isPaused && !playback.isRunning)
        #expect(playback.chartTime(now: 5) == -2)
        playback.resume(now: 5)
        #expect(playback.chartTime(now: 6) == -1)
    }

    @Test func withoutStemsTheEngineStillCountsAndClicks() {
        let audio = AudioEngine(offlineRate: 44100)
        let playback = SongPlayback(audio: audio)
        playback.apply(PlayerSettings(metronomeVolume: 1))
        #expect(!playback.load(song(), beatTimes: [0, 0.5, 1]))
        playback.begin(now: 0)
        playback.tick(now: 3)
        let first = audio.render(frames: 512)
        #expect(first.contains { abs($0) > 0.05 }, "the click on beat 1")
        _ = audio.render(frames: 22050 - 512)
        #expect(abs(playback.chartTime(now: 0) - 0.5) < 0.01, "the engine is the clock")
        #expect(!playback.musicPlaying)
    }

    @Test func missCueFollowsItsVolume() {
        let audio = AudioEngine(offlineRate: 44100)
        let playback = SongPlayback(audio: audio, missSound: SongEndTests.wav([Int16](repeating: 16000, count: 441)))
        playback.react(to: .playMissSFX)
        #expect(audio.render(frames: 512).contains { $0 != 0 })
        playback.apply(PlayerSettings(missSoundVolume: 0))
        playback.react(to: .playMissSFX)
        #expect(!audio.render(frames: 512).contains { $0 != 0 })
    }

    @Test func previewIsSilentWhileTheSongRuns() {
        let audio = AudioEngine(offlineRate: 44100)
        let playback = SongPlayback(audio: audio, missSound: SongEndTests.wav([Int16](repeating: 16000, count: 441)))
        playback.load(song(), beatTimes: [])
        playback.begin(now: 0)
        playback.preview(.miss)
        #expect(!audio.render(frames: 512).contains { $0 != 0 })
        playback.pause(now: 1)
        playback.preview(.miss)
        #expect(audio.render(frames: 512).contains { $0 != 0 })
    }
}
