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

/// One run of a chart on screen: the session and the flashes the highway draws.
/// Its music and clock are the app's `SongPlayback`.
struct Play {
    let song: SongMetadata
    let difficulty: DrumDifficulty
    var session: GameSession
    let beatTimes: [Double]
    var laneFlash: [(until: Double, color: Color)?] = Array(repeating: nil, count: 4)
    var judgeFlash: [(until: Double, isHit: Bool)?] = Array(repeating: nil, count: 4)
    var padFlashUntil = [Double](repeating: 0, count: DrumKit.padCount)
}

enum Screen {
    case library
    case difficulty(song: SongMetadata, options: [DrumDifficulty], index: Int)
    /// The loading screen. `ticked`: a tick has passed, so the screen has been
    /// drawn and the next tick loads the song (which blocks for a moment).
    case loading(song: SongMetadata, difficulty: DrumDifficulty, ticked: Bool)
    case playing(Play)
    case results(song: SongMetadata, difficulty: DrumDifficulty, session: GameSession)
    /// Which voice each pad plays; `selected` is the Beat-Train pad being set.
    case padSetup(selected: Int, flashUntil: Double)
    /// `SettingsItem.all`, `index` selected; `editing`: the encoder changes its value.
    case settings(index: Int, editing: Bool)
}

/// What the controls do on a screen: B1–B3 (nil: unused) and the footer items.
struct ControlHints: Equatable {
    var softKeys: [String?]
    var footer: [String] = []
    var footerRight = ""
}

/// The game's screens and their input handling. Time comes in as `now`, and audio
/// is optional, so it runs the same on the device and in previews.
final class BeatTrainApp {
    let songs: [SongMetadata]
    let songRoots: [String]
    let playback: SongPlayback
    var screen: Screen = .library
    var libraryIndex = 0
    var shiftHeld = false
    private(set) var lifecycle = Lifecycle.running
    var message: (text: String, until: Double)?
    /// The start picture, over everything until it is over.
    var splash: Splash?

    let keeper: SettingsKeeper

    init(songs: [SongMetadata], songRoots: [String], playback: SongPlayback, settings storage: SettingsStorage? = nil) {
        self.songs = songs
        self.songRoots = songRoots
        self.playback = playback
        keeper = SettingsKeeper(storage: storage)
        playback.apply(keeper.current)
        keeper.onChange = { [unowned self] item in
            self.playback.apply(self.keeper.current)
            if item == .metronome { self.playback.preview(.click) }
            if item == .missSound { self.playback.preview(.miss) }
        }
    }

    /// An app whose settings are not kept.
    convenience init(songs: [SongMetadata], songRoots: [String], audio: AudioEngine?) {
        self.init(songs: songs, songRoots: songRoots, playback: SongPlayback(audio: audio))
    }

    var settings: PlayerSettings {
        keeper.current
    }

    var kit: DrumKit {
        settings.kit
    }

    /// The voices a pad can be set to, in the order the encoder steps through them.
    static let voiceChoices: [DrumVoice] = [.kick, .red, .yellow, .blue, .orange, .green, .off]

    /// Shifts the chart against the audio; K1 turns it (±120 ms, 5 ms steps).
    var timingOffsetMs: Double {
        settings.timingOffsetMs
    }

    var timing: TimingConfiguration {
        settings.timing
    }

    // MARK: - Input

    /// Ends the app: the song stops and the settings are saved. Every way out
    /// (SHIFT+STOP, YES to shutting down, a stop signal) goes through here.
    func quit(powerOff: Bool = false) {
        guard !lifecycle.isOver else { return }
        playback.unload()
        keeper.saveNow()
        lifecycle = powerOff ? .poweringOff : .quitting
    }

    /// The power key: ask before shutting down, as the stock app does. A song
    /// pauses meanwhile.
    func powerButtonPressed(now: Double) {
        guard lifecycle == .running else { return }
        lifecycle = .askingToShutDown
        if case .playing = screen { playback.pause(now: now) }
    }

    func handle(_ event: ControlEvent, now: Double) {
        if lifecycle == .askingToShutDown {
            answerShutdown(event, now: now)
            return
        }
        switch splash?.effect(of: event, now: now) {
        case .ends?:
            splash = nil
            return
        case .swallowed?:
            return
        case .passes?, nil:
            break
        }
        switch event {
        case let .button(.shift, pressed):
            shiftHeld = pressed
            return
        case .button(.stop, pressed: true) where shiftHeld:
            quit()
            return
        case let .control(.mainVolume, value):
            playback.setMainVolume(value)
            return
        case let .control(control, value) where SettingsKeeper.knobs.contains(where: { $0.control == control }):
            if let item = keeper.turn(control, to: value, now: now) {
                message = ("\(item.title) \(item.text(in: settings))", now + 1.5)
            }
            return
        default:
            break
        }

        if case let .padDown(panelPad, _) = event {
            if let pad = PanelPads.pad(forPanelPad: panelPad) { strike(pad, now: now) }
            return
        }

        switch screen {
        case .library:
            handleLibrary(event, now: now)
        case let .difficulty(song, options, index):
            handleDifficulty(event, song: song, options: options, index: index, now: now)
        case .loading:
            break
        case var .playing(play):
            handlePlaying(event, play: &play, now: now)
            if case .playing = screen { screen = .playing(play) }
        case let .results(song, difficulty, session):
            switch event {
            case .button(.screen1, pressed: true):
                screen = .playing(newPlay(song: song, difficulty: difficulty, chart: session.chart))
                playback.begin(now: now)
            case .button(.play, pressed: true), .button(.dataPush, pressed: true), .button(.stop, pressed: true),
                 .button(.screen3, pressed: true):
                playback.unload()
                screen = .library
            default:
                break
            }
        case let .padSetup(selected, flashUntil):
            handlePadSetup(event, selected: selected, flashUntil: flashUntil, now: now)
        case let .settings(index, editing):
            handleSettings(event, index: index, editing: editing, now: now)
        }
    }

    // MARK: - Settings

    private func handleSettings(_ event: ControlEvent, index: Int, editing: Bool, now: Double) {
        let item = SettingsItem.all[index]
        switch event {
        case let .encoder(delta):
            if editing {
                keeper.step(item, by: delta, now: now)
            } else {
                screen = .settings(index: min(max(index + delta, 0), SettingsItem.all.count - 1), editing: false)
            }
        case .button(.dataPush, pressed: true):
            screen = .settings(index: index, editing: !editing)
        case .button(.erase, pressed: true), .button(.screen1, pressed: true):
            keeper.reset(item, now: now)
        case .button(.stop, pressed: true) where editing:
            screen = .settings(index: index, editing: false)
        case .button(.stop, pressed: true), .button(.screen3, pressed: true):
            keeper.saveNow()
            screen = .library
        default:
            break
        }
    }

    /// NO on B1 (or STOP), YES on B3, as in the stock app; everything else waits.
    private func answerShutdown(_ event: ControlEvent, now: Double) {
        switch event {
        case let .button(.shift, pressed):
            shiftHeld = pressed
        case .button(.screen1, pressed: true), .button(.stop, pressed: true):
            lifecycle = .running
        case .button(.screen3, pressed: true):
            quit(powerOff: true)
        default:
            break
        }
    }

    /// What the controls do on this screen, as the screen shows it: B1, B2 and B3
    /// in the bar at the top (labelled as the stock app does) and the other
    /// controls in the footer. Kept here, next to the handlers that do it.
    var hints: ControlHints {
        if lifecycle == .askingToShutDown { return ControlHints(softKeys: ["NO", nil, "YES"]) }
        switch screen {
        case .library:
            return ControlHints(softKeys: [nil, "SETTINGS", "PADS"], footer: ["TURN: SELECT", "PUSH: PLAY", "SHIFT+STOP: QUIT"],
                                footerRight: "\(songs.count) SONGS")
        case .difficulty:
            return ControlHints(softKeys: ["BACK", nil, "START"], footer: ["TURN: SELECT", "PUSH/PLAY: START", "STOP: BACK"])
        case .loading:
            return ControlHints(softKeys: [nil, nil, nil])
        case .playing:
            return ControlHints(softKeys: ["RESTART", nil, "END"], footer: ["PLAY: PAUSE", "STOP: END"])
        case .results:
            return ControlHints(softKeys: ["RETRY", nil, "SONGS"], footer: ["PUSH/PLAY: SONGS"])
        case let .settings(_, editing):
            return ControlHints(softKeys: ["DEFAULT", nil, "DONE"],
                                footer: editing ? ["TURN: CHANGE", "PUSH: DONE"] : ["TURN: SELECT", "PUSH: EDIT", "STOP: BACK"])
        case .padSetup:
            return ControlHints(softKeys: ["RESET", nil, "DONE"], footer: ["HIT: SELECT PAD", "TURN: SOUND", "STOP: DONE"])
        }
    }

    static func signed(_ value: Double) -> String {
        value > 0 ? "+\(Int(value))" : "\(Int(value))"
    }

    private func handleLibrary(_ event: ControlEvent, now: Double) {
        switch event {
        case let .encoder(delta):
            guard !songs.isEmpty else { return }
            libraryIndex = min(max(libraryIndex + delta, 0), songs.count - 1)
        case .button(.play, pressed: true), .button(.dataPush, pressed: true):
            guard songs.indices.contains(libraryIndex) else { return }
            let song = songs[libraryIndex]
            let available = song.notesURL.flatMap { try? DrumChartLoader.availableDifficulties(from: $0) } ?? []
            let options = DrumDifficulty.allCases.filter(available.contains)
            if options.isEmpty {
                message = ("No drum chart in this song", now + 2)
            } else {
                screen = .difficulty(song: song, options: options, index: options.count - 1)
            }
        case .button(.screen2, pressed: true):
            screen = .settings(index: 0, editing: false)
        case .button(.screen3, pressed: true):
            // Start on panel pad 1, the bottom left one.
            screen = .padSetup(selected: PanelPads.pad(forPanelPad: 0) ?? 0, flashUntil: 0)
        default:
            break
        }
    }

    private func handlePadSetup(_ event: ControlEvent, selected: Int, flashUntil: Double, now: Double) {
        switch event {
        case let .encoder(delta):
            let current = Self.voiceChoices.firstIndex(of: kit.voice(forPad: selected)) ?? 0
            let count = Self.voiceChoices.count
            keeper.setVoice(Self.voiceChoices[((current + delta) % count + count) % count], forPad: selected, now: now)
        case .button(.erase, pressed: true), .button(.screen1, pressed: true):
            keeper.resetPads(now: now)
            message = ("Pads reset", now + 1.5)
        case .button(.stop, pressed: true), .button(.screen3, pressed: true):
            keeper.saveNow()
            screen = .library
        default:
            break
        }
    }

    private func handleDifficulty(_ event: ControlEvent, song: SongMetadata, options: [DrumDifficulty], index: Int, now: Double) {
        switch event {
        case let .encoder(delta):
            screen = .difficulty(song: song, options: options, index: min(max(index + delta, 0), options.count - 1))
        case .button(.play, pressed: true), .button(.dataPush, pressed: true), .button(.screen3, pressed: true):
            // Loading the stems takes a moment: show the loading screen first,
            // `tick` starts the song once it is on the display.
            screen = .loading(song: song, difficulty: options[index], ticked: false)
        case .button(.stop, pressed: true), .button(.screen1, pressed: true):
            screen = .library
        default:
            break
        }
    }

    func start(song: SongMetadata, difficulty: DrumDifficulty, now: Double) {
        guard let notesURL = song.notesURL else { return }
        let chart: DrumChart
        do {
            chart = try DrumChartLoader.parse(from: notesURL, difficulty: difficulty, proDrums: song.hasProDrums)
        } catch {
            message = ("Chart error: \(error)", now + 3)
            screen = .library
            return
        }
        let play = newPlay(song: song, difficulty: difficulty, chart: chart)
        playback.load(song, beatTimes: play.beatTimes)
        playback.beginAfterLoading(now: now)
        screen = .playing(play)
    }

    /// A fresh run of a chart; the caller (re)starts `playback`.
    private func newPlay(song: SongMetadata, difficulty: DrumDifficulty, chart: DrumChart) -> Play {
        Play(song: song, difficulty: difficulty, session: GameSession(chart: chart, kit: kit, timing: timing), beatTimes: chart.beatTimesSec())
    }

    /// Shows the results. The stems stay loaded for a retry until the results close.
    private func finish(_ play: Play, now: Double) {
        playback.pause(now: now)
        screen = .results(song: play.song, difficulty: play.difficulty, session: play.session)
    }

    /// A strike on Pad `pad` (0–7): judged while playing, selects it in the pad setup.
    private func strike(_ pad: Int, now: Double) {
        switch screen {
        case var .playing(play):
            play.padFlashUntil[pad] = now + 0.12
            defer { screen = .playing(play) }
            let time = playback.chartTime(now: now)
            // Warm-up strikes during the count-in and while paused are not judged.
            guard time >= 0, !playback.isPaused else { return }
            if let lane = kit.lane(forPad: pad) {
                play.laneFlash[lane] = (now + 0.1, kit.voice(forPad: pad).color)
            }
            apply(play.session.strike(pad: pad, at: time), to: &play, now: now)
        case .padSetup:
            screen = .padSetup(selected: pad, flashUntil: now + 0.15)
        default:
            break
        }
    }

    private func handlePlaying(_ event: ControlEvent, play: inout Play, now: Double) {
        switch event {
        case .button(.play, pressed: true):
            if playback.isPaused { playback.resume(now: now) } else { playback.pause(now: now) }
        case .button(.screen1, pressed: true):
            play = newPlay(song: play.song, difficulty: play.difficulty, chart: play.session.chart)
            playback.begin(now: now)
        case .button(.stop, pressed: true), .button(.screen3, pressed: true):
            finish(play, now: now)
        default:
            break
        }
    }

    private func apply(_ feedback: [GameplayFeedback], to play: inout Play, now: Double) {
        for action in feedback {
            if case let .flashLane(lane, isHit) = action, (0..<4).contains(lane) {
                play.judgeFlash[lane] = (now + 0.15, isHit)
            }
            playback.react(to: action)
        }
    }

    // MARK: - Time

    /// Starts a song once its loading screen shows, runs its playback, misses
    /// notes whose window passed and ends the song.
    func tick(now: Double) {
        if splash?.isOver(now: now) == true { splash = nil }
        keeper.saveIfDue(now: now)
        if case let .loading(song, difficulty, ticked) = screen {
            if ticked {
                start(song: song, difficulty: difficulty, now: now)
            } else {
                screen = .loading(song: song, difficulty: difficulty, ticked: true)
            }
            return
        }
        guard case var .playing(play) = screen, playback.isRunning else { return }
        playback.tick(now: now)
        let time = playback.chartTime(now: now)
        apply(play.session.advance(to: time), to: &play, now: now)
        // After the last note the music plays on to its end.
        if play.session.isFinished(at: time) && !playback.musicPlaying {
            finish(play, now: now)
        } else {
            screen = .playing(play)
        }
    }

    // MARK: - Pad lights

    /// The colour each Pad should show now: its voice, dimmed, and full
    /// brightness while struck during play.
    func padColors(now: Double) -> [Color] {
        (0..<DrumKit.padCount).map { pad in
            let voice = kit.voice(forPad: pad)
            guard voice != .off else { return .black }
            switch screen {
            case let .playing(play) where play.padFlashUntil[pad] > now:
                return voice.color
            case let .padSetup(selected, flashUntil) where pad == selected:
                return flashUntil > now ? .white : voice.color
            default:
                return voice.color.mixed(with: .black, amount: 0.8)
            }
        }
    }
}
