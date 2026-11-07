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
        return SongMetadata(id: folder.path, title: "T", artist: "A", album: nil, hasDrumTrack: true, drumDifficulty: nil, hasProDrums: false,
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

    @Test func slowerSpeedSlowsTheClockAndTheOffset() {
        let playback = SongPlayback(audio: nil)
        playback.apply(PlayerSettings(timingOffsetMs: 20))
        playback.load(song(), beatTimes: [])
        playback.begin(now: 0)
        playback.tick(now: 3)
        playback.setSpeed(0.5, now: 4)
        // 1 s at full speed, 2 s at half; the 20 ms offset is 10 ms of song.
        #expect(abs(playback.chartTime(now: 6) - (2 - 0.01)) < 1e-9)
        playback.pause(now: 6)
        playback.resume(now: 10)
        #expect(abs(playback.chartTime(now: 12) - (3 - 0.01)) < 1e-9, "paused time does not count")
    }

    @Test func speedIsRoundedKeptInRangeAndReachesTheEngine() {
        let audio = AudioEngine(offlineRate: 44100)
        let playback = SongPlayback(audio: audio)
        playback.setSpeed(0.73, now: 0)
        #expect(playback.speed == 0.75)
        #expect(audio.speed == 0.75)
        playback.setSpeed(0.2, now: 0)
        #expect(playback.speed == 0.5)
        playback.setSpeed(2, now: 0)
        #expect(playback.speed == 1)
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

    @Test func padSoundsPlayAtTheirOwnLevelNextToTheDrumStem() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("beattrain-pad-sounds-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("sounds"), withIntermediateDirectories: true)
        try Data(SongEndTests.wav([Int16](repeating: 8000, count: 44100))).write(to: folder.appendingPathComponent("drums.wav"))
        try Data(SongEndTests.wav([Int16](repeating: 16000, count: 441))).write(to: folder.appendingPathComponent("sounds/kick.wav"))
        let song = SongMetadata(id: folder.path, title: "T", artist: "A", album: nil, hasDrumTrack: true, drumDifficulty: nil, hasProDrums: false,
                                chartDelayMilliseconds: 0, songFolderURL: folder, notesURL: nil, audioURL: nil)
        let audio = AudioEngine(offlineRate: 44100)
        let playback = SongPlayback(audio: audio)
        playback.load(song, beatTimes: [])
        playback.begin(now: 0)
        playback.tick(now: 3)
        #expect(!playback.playsPadSounds, "off by default")
        playback.strike(.kick)
        #expect(audio.render(frames: 512).allSatisfy { abs($0 - 8000.0 / 32768) < 0.01 }, "the drum stem alone")

        // Pads only: the drum stem turned down, the pad sounds up.
        playback.apply(PlayerSettings(stemVolumes: [.drums: 0], padSoundsVolume: 1))
        #expect(playback.playsPadSounds)
        _ = audio.render(frames: 2048)  // mixed ahead at the old level for the time stretch
        #expect(audio.render(frames: 512).allSatisfy { $0 == 0 }, "the drum stem is silent")
        playback.strike(.red)
        #expect(audio.render(frames: 512).allSatisfy { $0 == 0 }, "no sound for the snare in this song")
        playback.strike(.kick)
        #expect(audio.render(frames: 256).contains { abs($0 - 16000.0 / 32768) < 0.01 }, "the kick's sound")

        // Both, the pad sounds at half their level.
        playback.apply(PlayerSettings(padSoundsVolume: 0.5))
        _ = audio.render(frames: 2048)
        playback.strike(.kick)
        #expect(audio.render(frames: 256).contains { abs($0 - (8000.0 + 8000.0) / 32768) < 0.01 }, "the stem and half the kick")
    }
}
