import BeatTrainCore
import Foundation
import MPCHardware
import Testing
@testable import beattrain

/// Settings kept in memory, in place of `settings.json`.
final class MemorySettings: SettingsStorage {
    var saved: PlayerSettings?

    func load() -> PlayerSettings {
        saved ?? PlayerSettings()
    }

    func save(_ settings: PlayerSettings) throws {
        saved = settings
    }

    /// An app without audio that keeps its settings here.
    func app() -> BeatTrainApp {
        BeatTrainApp(songs: [], songRoots: [], playback: SongPlayback(audio: nil), settings: self)
    }
}

struct BeatTrainAppTests {
    @Test func padsShowTheirVoiceDimmed() {
        let app = BeatTrainApp(songs: [], songRoots: [], audio: nil)
        let colors = app.padColors(now: 0)
        #expect(colors.count == 8)
        #expect(colors[4] == DrumVoice.red.color.mixed(with: .black, amount: 0.8))
        #expect(colors[0] == DrumVoice.kick.color.mixed(with: .black, amount: 0.8))
        #expect(colors[1] == .black, "off")
    }

    @Test func k1MovesTheOffsetByItsTurnNotItsPosition() {
        let app = BeatTrainApp(songs: [], songRoots: [], audio: nil)
        app.handle(.control(.k1, value: 120), now: 0)
        #expect(app.timingOffsetMs == 0, "the first value only sets the reference")
        app.handle(.control(.k1, value: 127), now: 0.1)
        #expect(app.timingOffsetMs == 15)   // 7 steps x 1.9 ms, in 5 ms steps
        app.handle(.control(.k1, value: 0), now: 0.2)
        #expect(app.timingOffsetMs == -120) // clamped
    }

    @Test func offsetIsSavedAfterAPauseAndLoadedAtStart() {
        let storage = MemorySettings()
        let app = storage.app()
        app.handle(.control(.k1, value: 64), now: 0)
        app.handle(.control(.k1, value: 54), now: 0)
        app.tick(now: 1)
        #expect(storage.saved == nil, "not saved while still turning")
        app.tick(now: 2)
        #expect(storage.saved?.timingOffsetMs == -20)
        #expect(storage.app().timingOffsetMs == -20, "loaded at the next start")
    }
}

struct SpeedFaderTests {
    @Test func theFaderAloneDoesNothing() {
        let app = BeatTrainApp(songs: [], songRoots: [], audio: nil)
        app.handle(.control(.fader, value: 127), now: 0)
        app.handle(.control(.fader, value: 0), now: 0)
        #expect(app.playback.speed == 1)
    }

    @Test func shiftAndFaderSetTheSpeedByTheFadersTravel() {
        let app = BeatTrainApp(songs: [], songRoots: [], audio: nil)
        app.handle(.control(.fader, value: 127), now: 0)            // where it stands
        app.handle(.button(.shift, pressed: true), now: 0)
        app.handle(.control(.fader, value: 64), now: 0)             // half way down
        #expect(app.playback.speed == 0.75)
        #expect(app.message?.text == "SPEED 75%")
        app.handle(.button(.shift, pressed: false), now: 0)
        app.handle(.control(.fader, value: 0), now: 0)              // moved without SHIFT
        #expect(app.playback.speed == 0.75)
        app.handle(.button(.shift, pressed: true), now: 0)
        app.handle(.control(.fader, value: 127), now: 0)            // all the way up
        #expect(app.playback.speed == 1)
    }
}

struct PadSetupTests {
    private func openSetup(_ app: BeatTrainApp) {
        app.handle(.button(.screen3, pressed: true), now: 0)
    }

    @Test func b3OpensTheSetupOnPadOne() {
        let app = BeatTrainApp(songs: [], songRoots: [], audio: nil)
        openSetup(app)
        guard case let .padSetup(selected, _) = app.screen else {
            Issue.record("not in pad setup")
            return
        }
        #expect(selected == PanelPads.pad(forPanelPad: 0))
    }

    @Test func hittingAPadSelectsItAndTheEncoderStepsItsVoice() {
        let app = BeatTrainApp(songs: [], songRoots: [], audio: nil)
        openSetup(app)
        app.handle(.padDown(pad: 5, velocity: 90), now: 1)   // panel pad 6 = Beat-Train pad 1, off
        app.handle(.encoder(delta: 1), now: 1)
        #expect(app.kit.voice(forPad: 1) == .kick)
        app.handle(.encoder(delta: -2), now: 1)
        #expect(app.kit.voice(forPad: 1) == .green, "wraps around backwards past off")
        app.handle(.padDown(pad: 12, velocity: 90), now: 1)  // pads 9-16 select nothing
        app.handle(.encoder(delta: 1), now: 1)
        #expect(app.kit.voice(forPad: 1) == .off)
    }

    @Test func eraseResetsAndStopSavesAndReturns() {
        let storage = MemorySettings()
        let app = storage.app()
        openSetup(app)
        app.handle(.padDown(pad: 0, velocity: 90), now: 1)   // panel pad 1 = snare
        app.handle(.encoder(delta: 2), now: 1)
        #expect(app.kit.voice(forPad: 4) == .blue)
        app.handle(.button(.stop, pressed: true), now: 1.1)
        guard case .library = app.screen else {
            Issue.record("STOP did not return to the song list")
            return
        }
        #expect(storage.saved?.padVoices[4] == .blue, "saved right away on leaving")

        openSetup(app)
        app.handle(.button(.erase, pressed: true), now: 2)
        #expect(app.kit.padVoices == DrumKit.defaultPadVoices)
    }
}

struct SettingsScreenTests {
    @Test func b2OpensSettingsAndTheEncoderEditsTheSelectedLine() {
        let app = BeatTrainApp(songs: [], songRoots: [], audio: nil)
        app.handle(.button(.screen2, pressed: true), now: 0)
        app.handle(.encoder(delta: 1), now: 0)                       // HIT WINDOW
        app.handle(.button(.dataPush, pressed: true), now: 0)        // edit
        app.handle(.encoder(delta: 6), now: 0)                       // +30 ms
        #expect(app.settings.hitWindowMs == 150)
        #expect(app.timing.hitWindowTotalSec == 0.15)
        app.handle(.button(.erase, pressed: true), now: 0)
        #expect(app.settings.hitWindowMs == 120)
        app.handle(.button(.dataPush, pressed: true), now: 0)        // done editing
        app.handle(.encoder(delta: 100), now: 0)                     // to the last line
        guard case let .settings(index, editing, _) = app.screen else {
            Issue.record("not on the settings screen")
            return
        }
        #expect(index == SettingsItem.all.count - 1)
        #expect(!editing)
    }

    @Test func highwayLineStepsThroughTheLayouts() {
        let app = BeatTrainApp(songs: [], songRoots: [], audio: nil)
        app.handle(.button(.screen2, pressed: true), now: 0)
        app.handle(.encoder(delta: SettingsItem.all.firstIndex(of: .highway)!), now: 0)
        app.handle(.button(.dataPush, pressed: true), now: 0)
        var texts = [SettingsItem.highway.text(in: app.settings)]
        for _ in 0..<3 {
            app.handle(.encoder(delta: 1), now: 0)
            texts.append(SettingsItem.highway.text(in: app.settings))
        }
        #expect(texts == ["VERTICAL", "VERTICAL BY PAD", "HORIZONTAL", "HORIZONTAL"], "stays at the end")
        app.handle(.encoder(delta: -1), now: 0)
        #expect(app.settings.highwayLayout == .verticalByPad)
    }

    @Test func strikeLineStepsThroughItsPositions() {
        let app = BeatTrainApp(songs: [], songRoots: [], audio: nil)
        app.handle(.button(.screen2, pressed: true), now: 0)
        app.handle(.encoder(delta: SettingsItem.all.firstIndex(of: .strikeLine)!), now: 0)
        app.handle(.button(.dataPush, pressed: true), now: 0)
        let texts = (0..<4).map { _ -> String in
            app.handle(.encoder(delta: 1), now: 0)
            return SettingsItem.strikeLine.text(in: app.settings)
        }
        #expect(texts == ["1/4", "1/3", "MIDDLE", "MIDDLE"])
        app.handle(.button(.erase, pressed: true), now: 0)
        #expect(app.settings.strikeLine == .edge)
        #expect(SettingsItem.strikeLine.text(in: app.settings) == "BOTTOM")
    }

    @Test func theListScrollsToShowTheLastLine() {
        let app = BeatTrainApp(songs: [], songRoots: [], audio: nil)
        app.handle(.button(.screen2, pressed: true), now: 0)
        app.handle(.encoder(delta: 100), now: 0)
        var canvas = Canvas(width: 320, height: 240)
        app.render(into: &canvas, now: 0)
        // The selected line is the last that fits above the footer (13 lines from y 17).
        #expect(canvas.pixel(x: 1, y: 17 + 12 * 15 + 1) == Theme.selection)
    }

    @Test func stopLeavesEditingFirstThenSavesAndReturns() {
        let storage = MemorySettings()
        let app = storage.app()
        app.handle(.button(.screen2, pressed: true), now: 0)
        app.handle(.encoder(delta: SettingsItem.all.firstIndex(of: .stem(.vocals))!), now: 0)
        app.handle(.button(.dataPush, pressed: true), now: 0)
        app.handle(.encoder(delta: -4), now: 0)
        #expect(app.settings.stemVolume(.vocals) == 0.8)
        app.handle(.button(.stop, pressed: true), now: 0.1)
        guard case .settings(_, editing: false, _) = app.screen else {
            Issue.record("STOP should only end editing")
            return
        }
        app.handle(.button(.stop, pressed: true), now: 0.2)
        guard case .library = app.screen else {
            Issue.record("second STOP should return to the song list")
            return
        }
        #expect(storage.saved?.stemVolume(.vocals) == 0.8)
    }

    @Test func k2AndK3TurnMetronomeAndMissSoundByTheirTurn() {
        let app = BeatTrainApp(songs: [], songRoots: [], audio: nil)
        app.handle(.control(.k2, value: 40), now: 0)
        #expect(app.settings.metronomeVolume == 0, "first value is the reference")
        app.handle(.control(.k2, value: 104), now: 0.1)             // +64 of 127: about half
        #expect(app.settings.metronomeVolume == 0.5)
        app.handle(.control(.k3, value: 127), now: 0.2)
        app.handle(.control(.k3, value: 0), now: 0.3)
        #expect(app.settings.missSoundVolume == 0, "turned all the way down: off")
    }

    @Test func hitWindowReachesTheGameSession() throws {
        let app = BeatTrainApp(songs: [], songRoots: [], audio: nil)
        app.handle(.button(.screen2, pressed: true), now: 0)
        app.handle(.encoder(delta: 2), now: 0)                       // EARLY
        app.handle(.button(.dataPush, pressed: true), now: 0)
        app.handle(.encoder(delta: 2), now: 0)                       // 60 ms
        #expect(app.timing.hitWindowFrontSec == 0.06)
        #expect(abs(app.timing.hitWindowBackSec - 0.06) < 1e-9)
    }
}

struct SoftKeyTests {
    @Test func labelsFollowTheScreen() {
        let app = BeatTrainApp(songs: [], songRoots: [], audio: nil)
        #expect(app.hints.softKeys == [nil, "SETTINGS", "PADS"])
        app.handle(.button(.screen2, pressed: true), now: 0)
        #expect(app.hints.softKeys == ["DEFAULT", nil, "DONE"])
        app.handle(.button(.screen3, pressed: true), now: 0)
        app.handle(.button(.screen3, pressed: true), now: 0)
        #expect(app.hints.softKeys == ["RESET", nil, "DONE"])
    }

    @Test func b1ResetsInSettingsAndPadSetup() {
        let app = BeatTrainApp(songs: [], songRoots: [], audio: nil)
        app.handle(.button(.screen2, pressed: true), now: 0)
        app.handle(.button(.dataPush, pressed: true), now: 0)
        app.handle(.encoder(delta: 4), now: 0)               // offset +20
        #expect(app.settings.timingOffsetMs == 20)
        app.handle(.button(.screen1, pressed: true), now: 0)
        #expect(app.settings.timingOffsetMs == 0)

        app.handle(.button(.screen3, pressed: true), now: 0)  // done
        app.handle(.button(.screen3, pressed: true), now: 0)  // pads
        app.handle(.encoder(delta: 1), now: 0)
        #expect(app.kit.padVoices != DrumKit.defaultPadVoices)
        app.handle(.button(.screen1, pressed: true), now: 0)
        #expect(app.kit.padVoices == DrumKit.defaultPadVoices)
        app.handle(.button(.screen3, pressed: true), now: 0)
        guard case .library = app.screen else {
            Issue.record("B3 should close the pad setup")
            return
        }
    }
}

struct ShutdownTests {
    @Test func powerAsksAndNoGoesBack() {
        let app = BeatTrainApp(songs: [], songRoots: [], audio: nil)
        app.powerButtonPressed(now: 0)
        #expect(app.lifecycle == .askingToShutDown)
        #expect(app.hints.softKeys == ["NO", nil, "YES"])
        app.handle(.button(.screen2, pressed: true), now: 0.1)  // SETTINGS, but the question is open
        guard case .library = app.screen else {
            Issue.record("other buttons wait while the question is open")
            return
        }
        app.handle(.button(.screen1, pressed: true), now: 0.2)
        #expect(app.lifecycle == .running)
        #expect(app.hints.softKeys == [nil, "SETTINGS", "PADS"])
    }

    @Test func stopAnswersNo() {
        let app = BeatTrainApp(songs: [], songRoots: [], audio: nil)
        app.powerButtonPressed(now: 0)
        app.handle(.button(.stop, pressed: true), now: 0.1)
        #expect(app.lifecycle == .running)
    }

    @Test func shiftStopSavesAndQuitsToTheStockApp() {
        let storage = MemorySettings()
        let app = storage.app()
        app.handle(.control(.k1, value: 64), now: 0)
        app.handle(.control(.k1, value: 54), now: 0)              // -20 ms, not saved yet
        app.handle(.button(.shift, pressed: true), now: 0.1)
        app.handle(.button(.stop, pressed: true), now: 0.1)
        #expect(app.lifecycle == .quitting)
        #expect(app.lifecycle.exitCode == 0)
        #expect(storage.saved?.timingOffsetMs == -20)
        app.powerButtonPressed(now: 0.2)
        #expect(app.lifecycle == .quitting, "no question on the way out")
    }

    @Test func yesSavesAndAsksForPowerOff() {
        let storage = MemorySettings()
        let app = storage.app()
        app.handle(.control(.k1, value: 64), now: 0)
        app.handle(.control(.k1, value: 54), now: 0)              // -20 ms, not saved yet
        app.powerButtonPressed(now: 0.1)
        app.handle(.button(.screen3, pressed: true), now: 0.2)
        #expect(app.lifecycle == .poweringOff)
        #expect(app.lifecycle.exitCode == 10)
        #expect(storage.saved?.timingOffsetMs == -20)
    }
}

/// Song end, restart and retry with a real (offline) audio engine and a tiny song:
/// one kick at 0 s, and 3.6 s of music (the miss sound ten times).
struct SongEndTests {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent("beattrain-song-\(UUID().uuidString)")

    /// A one-note song whose audio is ten copies of `drum-miss.mp3` as
    /// `song.mp3`, or `stem` (file name and bytes) when given.
    private func makeApp(stem: (name: String, data: Data)? = nil, missSound: [UInt8]? = nil) throws -> (BeatTrainApp, AudioEngine) {
        let folder = root.appendingPathComponent("Songs/Test Song")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("[song]\nname = Test Song\nartist = Test\n".utf8).write(to: folder.appendingPathComponent("song.ini"))
        let chart = """
        [Song]
        {
          Resolution = 192
        }
        [SyncTrack]
        {
          0 = B 120000
        }
        [ExpertDrums]
        {
          0 = N 0 0
        }
        """
        try Data(chart.utf8).write(to: folder.appendingPathComponent("notes.chart"))
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../MPCHardwareTests/Fixtures/drum-miss.mp3")
        if let stem {
            try stem.data.write(to: folder.appendingPathComponent(stem.name))
        } else {
            let frames = Self.audioFrames(of: try Data(contentsOf: fixture))
            try Data((0..<10).flatMap { _ in frames }).write(to: folder.appendingPathComponent("song.mp3"))
        }

        let audio = AudioEngine(offlineRate: 44100)
        let songs = SongLibrary.scan(root: root.appendingPathComponent("Songs"))
        return (BeatTrainApp(songs: songs, songRoots: [], playback: SongPlayback(audio: audio, missSound: missSound)), audio)
    }

    /// The MP3's frames without its ID3 tag and its first frame (an "Info" header
    /// that states the length, which would end ten copies after the first).
    private static func audioFrames(of data: Data) -> [UInt8] {
        var bytes = [UInt8](data)
        if bytes.starts(with: Array("ID3".utf8)) {
            let size = bytes[6...9].reduce(0) { $0 << 7 | Int($1 & 0x7F) }
            bytes.removeFirst(10 + size)
        }
        // Every frame of this file starts with FF F3; skip to the second one.
        let second = (4..<bytes.count - 1).first { bytes[$0] == 0xFF && bytes[$0 + 1] == 0xF3 } ?? 0
        return Array(bytes[second...])
    }

    /// The test song started and counted in: the music starts. Its start time.
    private func startSong(_ app: BeatTrainApp) -> Double {
        guard var song = PlayThrough(app: app, now: 0) else { return 0 }
        song.countIn()
        return song.now
    }

    private func play(_ app: BeatTrainApp) -> Play? {
        if case let .playing(play) = app.screen { return play }
        return nil
    }

    @Test func oggStemPlays() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let ogg = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../MPCHardwareTests/Fixtures/sine1k-stereo-48000.ogg")
        let (app, audio) = try makeApp(stem: ("drums.ogg", try Data(contentsOf: ogg)))
        _ = startSong(app)
        #expect(app.playback.hasMusic)
        #expect(abs(audio.duration - 0.5) < 0.01)
    }

    @Test func musicPlaysOnAfterTheLastNoteThenResults() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let (app, audio) = try makeApp()
        let start = startSong(app)
        #expect(app.playback.hasMusic)
        #expect(audio.duration > 3, "duration \(audio.duration)")
        _ = audio.render(frames: 44100 * 2)                      // 2 s: the chart is done
        app.tick(now: start + 2)
        #expect(play(app) != nil, "still playing while the music runs")
        while !audio.isFinished { _ = audio.render(frames: 4096) }
        app.tick(now: start + 4)
        guard case .results = app.screen else {
            Issue.record("results after the music ended")
            return
        }
    }

    @Test func horizontalHighwayJudgesOnTheStruckPadsRow() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let (app, audio) = try makeApp()
        app.keeper.set(.highway, to: 2, now: 0)
        #expect(app.sweep == .rows, "menus go out row by row")
        let start = startSong(app)
        #expect(app.sweep == .columns, "notes running sideways go out in strips")
        let kick = DrumKit.pad(forLayout: DrumTarget(lane: 0, row: .bottom))
        #expect(play(app)?.chartPads == [kick], "only the pads the chart uses")
        app.handle(.padDown(pad: PanelPads.panelPad(forPad: kick), velocity: 100), now: start)
        #expect(play(app)?.padFeedback.judgement(ofPad: kick, at: start) == true)
        var canvas = Canvas(width: 320, height: 240)
        app.render(into: &canvas, now: start)
        // One row, centred: its target box lights up green left of the strike line.
        let top = Highway.rowsTop + (Highway.rowsBottom - Highway.rowsTop - Highway.maxRowHeight) / 2
        let strikeX = Highway.strikeX(for: .edge)
        #expect(canvas.pixel(x: strikeX - 6, y: top + 10) == Theme.hit)
        #expect(canvas.pixel(x: strikeX, y: top + 1) == Theme.accent)

        // In the middle, the note struck a second ago still shows left of the line.
        app.keeper.set(.strikeLine, to: 3, now: start)
        let middle = Highway.strikeX(for: .middle)
        #expect(middle == 176)
        _ = audio.render(frames: 44100)
        app.render(into: &canvas, now: start + 1)
        #expect(canvas.pixel(x: middle, y: top + 1) == Theme.accent)
        #expect(canvas.pixel(x: middle - Int(Highway.pixelsPerSecond), y: top + 10) == Theme.text, "the struck note, a second on")
    }

    @Test func aMissedNoteFlashesRedOnItsPadsRow() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let (app, audio) = try makeApp()
        app.keeper.set(.highway, to: 2, now: 0)
        let start = startSong(app)
        // The kick at 0 s is not struck: once its window has passed it is missed.
        _ = audio.render(frames: 22050)
        app.tick(now: start + 0.5)
        let kick = DrumKit.pad(forLayout: DrumTarget(lane: 0, row: .bottom))
        #expect(play(app)?.padFeedback.judgement(ofPad: kick, at: start + 0.5) == false)
        var canvas = Canvas(width: 320, height: 240)
        app.render(into: &canvas, now: start + 0.5)
        let top = Highway.rowsTop + (Highway.rowsBottom - Highway.rowsTop - Highway.maxRowHeight) / 2
        #expect(canvas.pixel(x: Highway.strikeX(for: .edge) - 6, y: top + 10) == Theme.miss)
    }

    @Test func verticalHighwayShowsStruckNotesBelowARaisedLine() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let (app, audio) = try makeApp()
        app.keeper.set(.strikeLine, to: 3, now: 0)
        let start = startSong(app)
        let kick = DrumKit.pad(forLayout: DrumTarget(lane: 0, row: .bottom))
        app.handle(.padDown(pad: PanelPads.panelPad(forPad: kick), velocity: 100), now: start)
        _ = audio.render(frames: 22050)
        var canvas = Canvas(width: 320, height: 240)
        app.render(into: &canvas, now: start + 0.5)
        let middle = Highway.strikeY(for: .middle)
        #expect(middle == 106)
        #expect(canvas.pixel(x: 30, y: middle) == Theme.accent)
        // Half a second on, the struck kick is 62 px below the line, in white (its
        // upper half: kicks are on the upper panel row).
        #expect(canvas.pixel(x: 10, y: middle + 62 - 5) == Theme.text)

        // Under lane 1 one map of the panel, with both its pads: the kick (upper
        // panel row) and the snare (lower); below it, the bar naming K1-K3.
        let snare = DrumKit.pad(forLayout: DrumTarget(lane: 0, row: .top))
        let mapX = (Highway.laneWidth - BeatTrainApp.padMapSize.width) / 2, mapY = Highway.bottom + 2
        #expect(canvas.pixel(x: mapX + PanelPads.rows[0].firstIndex(of: kick)! * 6 + 2, y: mapY + 2) == DrumVoice.kick.color)
        #expect(canvas.pixel(x: mapX + PanelPads.rows[1].firstIndex(of: snare)! * 6 + 2, y: mapY + 6 + 2) == DrumVoice.red.color)
        #expect(canvas.pixel(x: 3, y: canvas.height - 14) == Theme.accent)
    }

    @Test func byPadHighwayGivesTheChartsPadsALaneEach() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let (app, _) = try makeApp()
        app.keeper.set(.highway, to: 1, now: 0)
        let start = startSong(app)
        let kick = DrumKit.pad(forLayout: DrumTarget(lane: 0, row: .bottom))
        app.handle(.padDown(pad: PanelPads.panelPad(forPad: kick), velocity: 100), now: start)
        var canvas = Canvas(width: 320, height: 240)
        app.render(into: &canvas, now: start)
        #expect(app.sweep == .rows)
        // The kick is the only pad: one lane, the whole highway, judged green.
        let strikeY = Highway.strikeY(for: .edge)
        #expect(canvas.pixel(x: 5, y: strikeY + 5) == Theme.hit)
        #expect(canvas.pixel(x: 100, y: strikeY) == Theme.accent)
        let mapX = (Highway.width - BeatTrainApp.padMapSize.width) / 2
        #expect(canvas.pixel(x: mapX + PanelPads.rows[0].firstIndex(of: kick)! * 6 + 2, y: Highway.bottom + 4) == Theme.text, "struck: white")
    }

    @Test func settingsFromTheSongPauseItAndGoOnAfterACountIn() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let (app, audio) = try makeApp()
        let start = startSong(app)
        _ = audio.render(frames: 4410)
        #expect(app.hints.softKeys == ["RESTART", "SETTINGS", "END"])
        app.handle(.button(.screen2, pressed: true), now: start + 0.1)
        guard case .settings(_, _, paused: .some) = app.screen else {
            Issue.record("B2 opens the settings over the song")
            return
        }
        #expect(app.playback.isPaused)
        app.handle(.encoder(delta: 1), now: start + 1)                // HIT WINDOW
        app.handle(.button(.dataPush, pressed: true), now: start + 1)
        app.handle(.encoder(delta: 6), now: start + 1)                // 150 ms
        app.handle(.button(.dataPush, pressed: true), now: start + 1)
        app.handle(.button(.screen3, pressed: true), now: start + 5)  // DONE
        guard case .playing = app.screen else {
            Issue.record("DONE goes back to the song")
            return
        }
        #expect(play(app)?.session.timing.hitWindowTotalSec == 0.15, "the new hit window judges the rest of the song")
        let position = app.playback.chartTime(now: start + 5)
        app.tick(now: start + 7.9)
        #expect(app.playback.isPaused, "3, 2, 1")
        #expect(app.playback.chartTime(now: start + 7.9) == position)
        app.tick(now: start + 8)
        #expect(!app.playback.isPaused, "and on")
    }

    @Test func playDuringTheCountInGoesOnAtOnce() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let (app, _) = try makeApp()
        let start = startSong(app)
        app.handle(.button(.screen2, pressed: true), now: start)
        app.handle(.button(.stop, pressed: true), now: start + 1)
        #expect(app.playback.resumesAt == start + 1 + SongClock.resumeCountInSec)
        app.handle(.button(.play, pressed: true), now: start + 2)
        #expect(!app.playback.isPaused)
        #expect(app.playback.resumesAt == nil)
    }

    @Test func shiftShowsTheStemGroupsTheSongHas() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let (app, audio) = try makeApp()   // a song stem only
        #expect(app.knobLabels == ["TIMING OFFSET", "METRONOME", "MISS SOUND"])
        app.handle(.button(.shift, pressed: true), now: 0)
        #expect(app.knobLabels == ["SONG", "DRUMS", "OTHERS"], "no song loaded: all")
        _ = startSong(app)
        #expect(app.knobLabels == ["SONG", nil, nil])
        app.handle(.control(.k1, value: 127), now: 1)
        app.handle(.control(.k1, value: 63), now: 1)                 // half a turn down
        #expect(app.settings.stemVolume(.song) == 0.5)
        #expect(app.message?.text == "SONG 50%")
        #expect(app.settings.timingOffsetMs == 0, "not the offset")
        _ = audio
        app.handle(.button(.shift, pressed: false), now: 1)
        app.handle(.control(.k1, value: 74), now: 1)
        #expect(app.settings.timingOffsetMs != 0, "without SHIFT K1 is the offset again, from where it stands")
        #expect(app.settings.stemVolume(.song) == 0.5)
    }

    @Test func b1RestartsTheSongFromTheStart() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let (app, audio) = try makeApp()
        let start = startSong(app)
        app.handle(.padDown(pad: 4, velocity: 100), now: start)  // panel pad 5 = kick
        _ = audio.render(frames: 44100)
        app.tick(now: start + 1)
        #expect(play(app)?.session.score.hits == 1)

        app.handle(.button(.screen1, pressed: true), now: start + 1)
        let again = try #require(play(app))
        #expect(again.session.score == ScoreState())
        #expect(app.playback.chartTime(now: start + 1) < 0, "counting in again")
        #expect(app.playback.startsAt == start + 1 + SongClock.leadInSec)
        #expect(audio.position == 0)
    }

    @Test func b1OnTheResultsRetriesWithTheLoadedStems() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let (app, audio) = try makeApp()
        let start = startSong(app)
        app.handle(.button(.stop, pressed: true), now: start + 0.5)
        guard case .results = app.screen else {
            Issue.record("STOP should show the results")
            return
        }
        #expect(app.hints.softKeys == ["RETRY", nil, "SONGS"])
        app.handle(.button(.screen1, pressed: true), now: start + 1)
        #expect(app.playback.hasMusic)
        app.tick(now: start + 1 + SongClock.leadInSec)
        _ = audio.render(frames: 4410)
        #expect(audio.position > 0, "the stems play again")
    }

    @Test func powerPausesTheSong() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let (app, audio) = try makeApp()
        let start = startSong(app)
        _ = audio.render(frames: 4410)
        app.powerButtonPressed(now: start + 0.1)
        #expect(app.playback.isPaused)
        let position = audio.position
        _ = audio.render(frames: 4410)
        #expect(audio.position == position, "the music stops while the question is open")
        app.handle(.button(.screen1, pressed: true), now: start + 1)
        #expect(app.playback.isPaused, "NO leaves it paused; PLAY goes on")
    }

    /// 2 s of silence as a 16-bit mono WAV.
    private static func silentWAV() -> Data {
        Data(wav([Int16](repeating: 0, count: 2 * 44100)))
    }

    /// `samples` as a 16-bit mono 44.1 kHz WAV.
    static func wav(_ samples: [Int16]) -> [UInt8] {
        func le(_ value: Int, _ bytes: Int) -> [UInt8] { (0..<bytes).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) } }
        let body = samples.flatMap { le(Int($0), 2) }
        let fmt = le(1, 2) + le(1, 2) + le(44100, 4) + le(88200, 4) + le(2, 2) + le(16, 2)
        let chunks = Array("fmt ".utf8) + le(16, 4) + fmt + Array("data".utf8) + le(body.count, 4) + body
        return Array("RIFF".utf8) + le(4 + chunks.count, 4) + Array("WAVE".utf8) + chunks
    }

    @Test func knobsSoundTheirLevelExceptOverARunningSong() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let (app, audio) = try makeApp(stem: ("song.wav", Self.silentWAV()), missSound: Self.wav([Int16](repeating: 16000, count: 441)))
        func turnK3(_ now: Double) {
            app.handle(.control(.k3, value: 64), now: now)
            app.handle(.control(.k3, value: 54), now: now)
        }
        func heard() -> Bool { audio.render(frames: 512).contains { $0 != 0 } }

        turnK3(0)
        #expect(heard(), "in the song list")
        let start = startSong(app)
        turnK3(start)
        #expect(!heard(), "not over the song")
        app.handle(.button(.play, pressed: true), now: start + 0.1)
        turnK3(start + 0.1)
        #expect(heard(), "paused")
    }
}

/// The start picture through `Splash`, and how the app hands it events and time.
struct SplashTests {
    private let splash = Splash(image: Canvas(width: 320, height: 240, fill: Color(rgb: 0x123456)), since: 10)

    @Test func endsAfterItsTimeOrAtAPressAfterTheMinimum() {
        #expect(!splash.isOver(now: 11.9))
        #expect(splash.isOver(now: 12))
        #expect(splash.effect(of: .padDown(pad: 0, velocity: 100), now: 11.4) == .swallowed)
        #expect(splash.effect(of: .encoder(delta: 0), now: 11.6) == .passes, "the panel's start report is no turn")
        #expect(splash.effect(of: .control(.k1, value: 3), now: 10) == .passes, "knobs work under the picture")
        #expect(splash.effect(of: .button(.screen3, pressed: true), now: 11.5) == .ends)
    }

    @Test func thePressThatEndsItDoesNothingElse() {
        let app = BeatTrainApp(songs: [], songRoots: [], audio: nil)
        app.splash = splash
        app.handle(.button(.screen3, pressed: true), now: 11.5)
        #expect(app.splash == nil)
        guard case .library = app.screen else {
            Issue.record("B3 opened \(app.screen) instead of only ending the picture")
            return
        }
    }

    @Test func tickTakesItAwayWhenItIsOver() {
        let app = BeatTrainApp(songs: [], songRoots: [], audio: nil)
        app.splash = splash
        app.tick(now: 11)
        #expect(app.splash != nil)
        app.tick(now: 12)
        #expect(app.splash == nil)
    }

    @Test func drawsCentred() {
        var canvas = Canvas(width: 320, height: 240)
        Splash(image: Canvas(width: 2, height: 2, fill: .white), since: 0).draw(into: &canvas)
        #expect(canvas.pixel(x: 159, y: 119) == .white && canvas.pixel(x: 158, y: 119) == .black)
    }
}
