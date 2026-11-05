/// Where a song stands in time, and from it the chart time: the count-in, pause
/// and the 3-2-1 back from the settings, the **Song speed**, the chart delay and
/// the player's timing offset. `SongPlayback` drives it and moves the engine when
/// it says so.
///
/// Once the count-in is over the song's seconds come from `enginePosition` (the
/// audio engine: what is heard), or without one from a timer at `speed`.
struct SongClock {
    static let leadInSec = 3.0
    /// The count-in before the song goes on after the settings: 3, 2, 1.
    static let resumeCountInSec = 3.0
    /// The song speeds there are, for practising: slower at the same pitch.
    static let speedRange = 0.5...1.0
    static let speedStep = 0.05

    private let enginePosition: (() -> Double)?
    /// Without an engine, the song's seconds once the music has started: `base`
    /// at monotonic time `at`.
    private var timer: (base: Double, at: Double)?
    private var begun = false

    private(set) var musicStarted = false
    /// Song seconds per second, in `speedRange`.
    private(set) var speed = 1.0
    /// Monotonic time at which the count-in ends and the music starts.
    private(set) var startsAt = 0.0
    private(set) var pausedAt: Double?
    /// Counting in to go on after a pause: when the song goes on.
    private(set) var resumesAt: Double?

    init(enginePosition: (() -> Double)?) {
        self.enginePosition = enginePosition
    }

    var isPaused: Bool {
        pausedAt != nil
    }

    /// Counting in or playing, not paused.
    var isRunning: Bool {
        begun && pausedAt == nil
    }

    /// From the song's beginning, after a count-in from `now`.
    mutating func begin(now: Double) {
        begun = true
        musicStarted = false
        timer = nil
        pausedAt = nil
        resumesAt = nil
        startsAt = now + Self.leadInSec
    }

    /// No song: nothing runs until the next `begin`.
    mutating func stop() {
        begun = false
        pausedAt = nil
        resumesAt = nil
    }

    /// True when it paused (it was running).
    mutating func pause(now: Double) -> Bool {
        guard begun, pausedAt == nil else { return false }
        pausedAt = now
        return true
    }

    /// True when the music has to play again (it had started).
    mutating func resume(now: Double) -> Bool {
        guard let pausedAt else { return false }
        resumesAt = nil
        if !musicStarted { startsAt += now - pausedAt }
        timer?.at += now - pausedAt
        self.pausedAt = nil
        return musicStarted
    }

    /// Goes on after a count-in of `resumeCountInSec`, paused until then; at once
    /// while the song's own count-in still runs.
    mutating func resumeAfterCountIn(now: Double) {
        guard pausedAt != nil else { return }
        guard musicStarted else {
            _ = resume(now: now)
            return
        }
        resumesAt = now + Self.resumeCountInSec
    }

    /// Ends a count-in that is over. True when the music has to play now: its
    /// count-in is over, or the 3-2-1 after a pause.
    mutating func tick(now: Double) -> Bool {
        var play = false
        if let resumesAt, now >= resumesAt { play = resume(now: resumesAt) }
        guard isRunning, !musicStarted, now >= startsAt else { return play }
        musicStarted = true
        if enginePosition == nil { timer = (now - startsAt, now) }
        return true
    }

    /// Rounds the speed to `speedStep` and keeps it in `speedRange`. True when it
    /// changed.
    mutating func setSpeed(_ value: Double, now: Double) -> Bool {
        let rounded = min(max((value / Self.speedStep).rounded() * Self.speedStep, Self.speedRange.lowerBound), Self.speedRange.upperBound)
        guard rounded != speed else { return false }
        if timer != nil { timer = (songSeconds(now: now), pausedAt ?? now) }
        speed = rounded
        return true
    }

    /// Chart seconds at `now`: negative during the count-in, then the song's
    /// seconds shifted by the chart delay and the timing offset, never below 0.
    func chartTime(now: Double, chartDelayMs: Double, timingOffsetMs: Double) -> Double {
        let seconds = songSeconds(now: now)
        guard seconds >= 0 else { return seconds }
        // The offset makes up for delays in real time (sound out, strike in), which
        // are fewer song seconds when the song runs slower.
        return max(0, seconds - chartDelayMs / 1000 - timingOffsetMs * speed / 1000)
    }

    /// The count-in (real seconds, negative), then the engine or the timer.
    private func songSeconds(now: Double) -> Double {
        if musicStarted, let enginePosition { return enginePosition() }
        if let timer { return timer.base + ((pausedAt ?? now) - timer.at) * speed }
        return (pausedAt ?? now) - startsAt
    }
}
