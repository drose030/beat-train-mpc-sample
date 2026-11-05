import BeatTrainCore
import MPCHardware

/// A song played by script, as a player would: picked in the song list and
/// started, then its notes struck on their pads as they come due, frame by frame,
/// some left to miss. The previews, the README's animations and the tests play
/// this way.
struct PlayThrough {
    let app: BeatTrainApp
    /// The app's engine when it renders offline: it renders as far as the time goes.
    let audio: AudioEngine?
    /// The notes left to miss, by index.
    let misses: (Int) -> Bool
    /// Monotonic time now.
    private(set) var now: Double
    private var nextNote = 0

    /// Picks the song `steps` encoder steps down the list and starts its first
    /// difficulty at `now`; `shot` sees the song list, the difficulties and the
    /// loading screen on the way. Nil when no chart starts.
    init?(app: BeatTrainApp, audio: AudioEngine? = nil, song steps: Int = 0, now: Double, misses: @escaping (Int) -> Bool = { _ in false },
          shot: (String) -> Void = { _ in }) {
        self.app = app
        self.audio = audio
        self.misses = misses
        self.now = now
        shot("library")
        if steps != 0 { app.handle(.encoder(delta: steps), now: now) }
        app.handle(.button(.dataPush, pressed: true), now: now)
        shot("difficulty")
        app.handle(.button(.dataPush, pressed: true), now: now)
        shot("loading")
        app.tick(now: now)  // the loading screen is up
        app.tick(now: now)  // the song loads
        guard play != nil else { return nil }
    }

    /// The run on screen, nil once it has ended.
    var play: Play? {
        if case let .playing(play) = app.screen { return play }
        return nil
    }

    /// Chart seconds now.
    var time: Double {
        app.playback.chartTime(now: now)
    }

    /// To the end of the count-in at once: the music starts.
    mutating func countIn() {
        now = app.playback.startsAt
        app.tick(now: now)
    }

    /// One step of `seconds`: the engine renders as far, the notes that came due
    /// are struck (unless missed), the app ticks.
    mutating func step(_ seconds: Double) {
        now += seconds
        _ = audio?.render(frames: Int(44100 * seconds))
        if let notes = play?.session.chart.notes {
            while nextNote < notes.count, notes[nextNote].timeSec <= time {
                if !misses(nextNote) { strike(notes[nextNote]) }
                nextNote += 1
            }
        }
        app.tick(now: now)
    }

    /// Steps of `step` until the chart has reached `time` (or the song has ended,
    /// or the time stands, paused).
    mutating func play(until time: Double, step: Double = 1 / 25) {
        while play != nil, self.time < time {
            let before = self.time
            self.step(step)
            if self.time == before { break }
        }
    }

    /// The pad a note is for, struck as the player would.
    private func strike(_ note: DrumNoteEvent) {
        let pad = DrumKit.pad(forLayout: app.kit.target(remapping: note.target))
        app.handle(.padDown(pad: PanelPads.panelPad(forPad: pad), velocity: 100), now: now)
    }
}
