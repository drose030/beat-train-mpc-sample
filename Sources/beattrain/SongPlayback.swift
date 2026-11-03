import BeatTrainCore
#if canImport(FoundationEssentials)
import FoundationEssentials  // no ICU: keeps the static Linux binary small
#else
import Foundation
#endif
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import MPCHardware

/// The music of the song being played and its clock: the stems in the audio
/// engine, the count-in, pause and restart, the metronome clicks and the miss
/// feedback. The one owner of "what time is it in the chart".
///
/// Once the count-in is over the clock is the engine's position, stems or not
/// (an engine without stems still counts, so clicks land on the beat). Without
/// an engine (previews, tests) a timer stands in. Either way the chart delay and
/// the player's timing offset apply.
final class SongPlayback {
    static let leadInSec = 3.0
    /// The stems the original game plays, in its order; all present ones play together.
    static let stemNames = ["song", "drums", "guitar", "bass", "rhythm", "vocals", "keys", "crowd"]
    /// Stem file types the audio engine plays, in the order they are looked for.
    static let stemExtensions = ["mp3", "ogg", "wav"]
    /// The original game's gain for the drum stem after a miss.
    static let mutedDrumsGain: Float = 0.2
    /// How far ahead metronome clicks are handed to the audio engine.
    static let clickLookaheadSec = 0.3

    /// The one-shot sounds the player can set the level of.
    enum Sound {
        case click, miss
    }

    private static let missSlot = 0
    private static let clickSlot = 1

    /// The original game's metronome click: 30 ms of 1 kHz sine with a fast decay.
    static func clickSamples(rate: Double) -> [Float] {
        (0..<Int(rate * 0.030)).map { frame in
            let t = Double(frame) / rate
            return Float(sin(2 * Double.pi * 1000 * t) * exp(-60 * t) * 0.9)
        }
    }

    private let audio: AudioEngine?
    private var settings = PlayerSettings()
    private var song: SongMetadata?
    private var beatTimes: [Double] = []
    private var stemIndices: [String: Int] = [:]
    private var drumsMuted = false
    private var begun = false
    private var musicStarted = false
    private var nextBeat = 0

    /// Monotonic time at which the count-in ends and the music starts.
    private(set) var startsAt = 0.0
    private(set) var pausedAt: Double?

    /// `missSound`: the bytes of an MP3, Ogg Vorbis or WAV file.
    init(audio: AudioEngine?, missSound: [UInt8]? = nil) {
        self.audio = audio
        guard let audio else { return }
        do {
            if let missSound { try audio.loadEffect(slot: Self.missSlot, encoded: missSound) }
            try audio.loadEffect(slot: Self.clickSlot, samples: Self.clickSamples(rate: 44100), rate: 44100)
        } catch {
            log("effects: \(error)")
        }
    }

    // MARK: - Song

    /// Puts a song's stems into the engine, each from the first of its
    /// `stemExtensions` files there, ready for `begin`. True when it has music.
    @discardableResult
    func load(_ song: SongMetadata, beatTimes: [Double]) -> Bool {
        unload()
        self.song = song
        self.beatTimes = beatTimes
        guard let audio else { return false }
        for name in Self.stemNames {
            for type in Self.stemExtensions {
                let url = song.songFolderURL.appendingPathComponent("\(name).\(type)")
                guard let data = try? Data(contentsOf: url) else { continue }
                do {
                    stemIndices[name] = try audio.addStem(encoded: [UInt8](data))
                } catch {
                    log("stem \(url.lastPathComponent): \(error)")
                }
                break
            }
        }
        applyGains()
        log("stems: \(stemIndices.keys.sorted()) for \(song.title), \((audio.duration * 10).rounded() / 10) s")
        return hasMusic
    }

    func unload() {
        audio?.clearStems()
        stemIndices = [:]
        song = nil
        beatTimes = []
        drumsMuted = false
        begun = false
        pausedAt = nil
    }

    /// The loaded song has stems playing in the engine.
    var hasMusic: Bool {
        !stemIndices.isEmpty
    }

    /// Starts the loaded song from its beginning, after a count-in from `now`.
    func begin(now: Double) {
        audio?.rewind()
        drumsMuted = false
        applyGains()
        begun = true
        musicStarted = false
        nextBeat = 0
        pausedAt = nil
        startsAt = now + Self.leadInSec
    }

    /// `begin` right after `load`: with an engine, loading took real time, so the
    /// count-in runs from when it is done.
    func beginAfterLoading(now: Double) {
        begin(now: audio == nil ? now : monotonicSeconds())
    }

    func pause(now: Double) {
        guard begun, pausedAt == nil else { return }
        pausedAt = now
        audio?.pause()
    }

    func resume(now: Double) {
        guard let pausedAt else { return }
        if !musicStarted { startsAt += now - pausedAt }
        self.pausedAt = nil
        if musicStarted { audio?.play() }
    }

    var isPaused: Bool {
        pausedAt != nil
    }

    /// Counting in or playing, not paused.
    var isRunning: Bool {
        begun && pausedAt == nil
    }

    /// The music goes on (after the last note it plays to its end).
    var musicPlaying: Bool {
        hasMusic && audio?.isFinished == false
    }

    // MARK: - Clock

    /// Chart seconds at `now`: negative during the count-in, then the song clock
    /// shifted by the chart delay and the timing offset.
    func chartTime(now: Double) -> Double {
        let clock: Double
        if musicStarted, let audio {
            clock = audio.position
        } else {
            clock = (pausedAt ?? now) - startsAt
        }
        guard clock >= 0 else { return clock }
        return GameSession.chartTime(audioTime: clock, chartDelayMs: song?.chartDelayMilliseconds ?? 0, timing: settings.timing)
    }

    /// Starts the music when the count-in is over and hands the engine the next
    /// metronome clicks.
    func tick(now: Double) {
        guard isRunning else { return }
        if !musicStarted, now >= startsAt {
            audio?.play()
            musicStarted = true
        }
        scheduleClicks()
    }

    /// Clicks sit on the song's beats (the chart's beat grid plus the chart
    /// delay), not shifted by the timing offset, placed to the sample by the engine.
    private func scheduleClicks() {
        guard settings.metronomeVolume > 0, musicStarted, let audio else { return }
        let delay = (song?.chartDelayMilliseconds ?? 0) / 1000
        let position = audio.position
        while nextBeat < beatTimes.count {
            let at = beatTimes[nextBeat] + delay
            if at > position + Self.clickLookaheadSec { break }
            if at >= position { audio.scheduleEffect(slot: Self.clickSlot, atSongTime: at) }
            nextBeat += 1
        }
    }

    // MARK: - Sound

    /// Volumes and the timing offset from the player's settings.
    func apply(_ settings: PlayerSettings) {
        self.settings = settings
        applyGains()
    }

    /// The audio part of the gameplay feedback: the drum stem's mute and the miss cue.
    func react(to feedback: GameplayFeedback) {
        switch feedback {
        case let .setDrumsMuted(muted):
            guard muted != drumsMuted else { return }
            drumsMuted = muted
            applyGains()
        case .playMissSFX:
            if settings.missSoundVolume > 0 { audio?.triggerEffect(slot: Self.missSlot) }
        case .flashLane:
            break
        }
    }

    /// Lets the player hear a level they set, except over a running song: there
    /// the song's own clicks and misses tell.
    func preview(_ sound: Sound) {
        guard !isRunning else { return }
        audio?.triggerEffect(slot: sound == .click ? Self.clickSlot : Self.missSlot)
    }

    /// The MAIN VOLUME knob (0–127), on a square curve.
    func setMainVolume(_ value: UInt8) {
        let level = Float(value) / 127
        audio?.setMaster(level * level)
    }

    private func applyGains() {
        guard let audio else { return }
        audio.setEffectGain(Float(settings.missSoundVolume), slot: Self.missSlot)
        audio.setEffectGain(Float(settings.metronomeVolume), slot: Self.clickSlot)
        for (name, index) in stemIndices {
            let muted = name == "drums" && drumsMuted
            audio.setGain(Float(settings.stemVolume(name)) * (muted ? Self.mutedDrumsGain : 1), forStem: index)
        }
    }
}
