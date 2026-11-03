// Beat-Train on the MPC Sample: pick a song with the encoder, play its drum chart
// on the pads. Started by the SD-card autorun in place of the stock app; SHIFT +
// STOP quits back to it.
//
//   beattrain [--songs DIR]...           run on the device
//   beattrain --songs DIR --preview DIR  render sample frames as PPM files and exit
//   beattrain [--songs DIR]... --list    print each song's charts and note counts

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

nonisolated(unsafe) var stopRequested: sig_atomic_t = 0

func log(_ line: String) {
    print(line)
    fflush(nil)  // all streams; glibc's `stdout` is a global var Swift 6 rejects
}

func option(_ name: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

func writePPM(_ canvas: Canvas, to path: String) {
    let data = canvas.ppmData()
    guard let file = fopen(path, "wb") else { return log("cannot write \(path)") }
    fwrite(data, 1, data.count, file)
    fclose(file)
    log("wrote \(path)")
}

/// Renders each screen once, with a simulated part-played chart, for checks off-device.
func renderPreviews(app: BeatTrainApp, into directory: String) {
    var canvas = Canvas(width: 320, height: 240)
    var now = 1000.0
    func shot(_ name: String) {
        app.render(into: &canvas, now: now)
        writePPM(canvas, to: "\(directory)/\(name).ppm")
    }
    shot("1-library")
    app.handle(.encoder(delta: 1), now: now)
    app.handle(.button(.dataPush, pressed: true), now: now)
    shot("2-difficulty")
    app.handle(.button(.dataPush, pressed: true), now: now)
    shot("3-loading")
    app.tick(now: now)  // the loading screen is up
    app.tick(now: now)  // the song loads
    now += 1.2
    shot("4-countin")
    guard case let .playing(play) = app.screen else { return log("no chart started") }
    // Hit three of four notes up to the 40th, then look at the highway.
    let notes = play.session.chart.notes
    let stopIndex = min(40, notes.count - 1)
    for (index, note) in notes.prefix(stopIndex).enumerated() {
        now = app.playback.startsAt + note.timeSec
        app.tick(now: now)
        if index % 4 != 3 {
            let pad = DrumKit.pad(forLayout: app.kit.target(remapping: note.target))
            app.handle(.padDown(pad: PanelPads.panelPad(forPad: pad), velocity: 100), now: now + 0.01)
        }
    }
    now = app.playback.startsAt + notes[stopIndex].timeSec - 0.6
    app.tick(now: now)
    shot("5-playing")
    app.handle(.button(.stop, pressed: true), now: now)
    shot("6-results")
    app.handle(.button(.dataPush, pressed: true), now: now)
    app.handle(.button(.screen3, pressed: true), now: now)
    app.handle(.padDown(pad: 5, velocity: 100), now: now)   // panel pad 6: unused by default
    app.handle(.encoder(delta: 3), now: now)               // off -> kick -> snare -> hi-hat
    shot("7-padsetup")
    app.handle(.button(.stop, pressed: true), now: now)
    app.handle(.button(.screen2, pressed: true), now: now)
    app.handle(.encoder(delta: 3), now: now)                // METRONOME
    app.handle(.button(.dataPush, pressed: true), now: now)
    app.handle(.encoder(delta: 12), now: now)               // 60 %
    shot("8-settings")
    app.powerButtonPressed(now: now)
    shot("9-shutdown")
}

let arguments = CommandLine.arguments
let roots = StartupPaths.songRoots(arguments: arguments, environmentSongs: getenv("BEATTRAIN_SONGS").map { String(cString: $0) })
let songs = roots.flatMap { SongLibrary.scan(root: URL(fileURLWithPath: $0)) }
log("songs: \(songs.count) in \(roots)")

if arguments.contains("--list") {
    for song in songs {
        guard let notesURL = song.notesURL else { continue }
        let charts = DrumDifficulty.allCases.compactMap { difficulty -> String? in
            guard let chart = try? DrumChartLoader.parse(from: notesURL, difficulty: difficulty), !chart.notes.isEmpty else { return nil }
            return "\(difficulty.rawValue) \(chart.notes.count)"
        }
        log("\(song.artist) - \(song.title): \(charts.isEmpty ? "no drum chart" : charts.joined(separator: ", "))")
    }
    exit(0)
}

if let directory = option("--preview", in: arguments) {
    renderPreviews(app: BeatTrainApp(songs: songs, songRoots: roots, audio: nil), into: directory)
    exit(0)
}

/// The directory of this executable (`/run/beattrain` on the device), where the
/// autorun puts the sounds and pictures.
func executableDirectory() -> URL {
    let exe = (try? FileManager.default.destinationOfSymbolicLink(atPath: "/proc/self/exe")) ?? CommandLine.arguments[0]
    return URL(fileURLWithPath: exe).deletingLastPathComponent()
}

let display: Display
do {
    display = try Display()
    log("display \(display.width)x\(display.height)")
} catch {
    log("display error: \(error)")
    exit(2)
}
var canvas = display.makeCanvas()

// The start picture, on the display while the rest starts.
let startedAt = monotonicSeconds()
let splash = Splash.load(from: executableDirectory(), now: startedAt)
if let splash {
    splash.draw(into: &canvas)
    try? display.present(canvas)
}

var audio: AudioEngine?
do {
    let engine = try AudioEngine()
    log("audio \(engine.setup)")
    audio = engine
} catch {
    log("audio error: \(error)")
}
let missURL = executableDirectory().appendingPathComponent("drum-miss.mp3")
let missSound = (try? Data(contentsOf: missURL)).map { [UInt8]($0) }
if missSound == nil { log("no miss sound at \(missURL.path)") }
let settingsFile = StartupPaths.settingsURL(for: roots).map(SettingsFile.init(url:))
let app = BeatTrainApp(songs: songs, songRoots: roots, playback: SongPlayback(audio: audio, missSound: missSound),
                       settings: settingsFile)
app.splash = splash
log("settings: offset \(BeatTrainApp.signed(app.timingOffsetMs)) ms from \(settingsFile?.url.path ?? "nowhere")")

signal(SIGTERM) { _ in stopRequested = 1 }
signal(SIGINT) { _ in stopRequested = 1 }

var surface: ControlSurface?
do {
    let opened = try ControlSurface()
    try opened.sendInit()
    log("control surface \(opened.devicePath)")
    surface = opened
} catch {
    app.message = ("Pads: \(error)", .infinity)
    log("control surface error: \(error)")
}

// Without it only the long press works, which powers off in hardware.
let powerButton: PowerButton?
do {
    let opened = try PowerButton()
    log("power key \(opened.devicePaths.joined(separator: ", "))")
    powerButton = opened
} catch {
    powerButton = nil
    log("power button error: \(error)")
}

var lights = PanelLights()
let frameInterval = 1.0 / 60
var nextFrame = monotonicSeconds()

log("ready after \(monotonicSeconds() - startedAt) s")
while stopRequested == 0 && !app.lifecycle.isOver {
    let untilFrame = max(0, nextFrame - monotonicSeconds())
    if let surface {
        do {
            for event in try surface.poll(timeoutMs: Int32((untilFrame * 1000).rounded(.up))) {
                if app.splash != nil { log("splash: \(event) after \(monotonicSeconds() - startedAt) s") }
                app.handle(event, now: monotonicSeconds())
            }
        } catch {
            log("input error: \(error)")
            usleep(UInt32(untilFrame * 1_000_000))
        }
    } else {
        usleep(UInt32(untilFrame * 1_000_000))
    }
    if powerButton?.pollPressed() == true {
        app.powerButtonPressed(now: monotonicSeconds())
    }

    let now = monotonicSeconds()
    guard now >= nextFrame else { continue }
    nextFrame = max(nextFrame + frameInterval, now)

    app.tick(now: now)
    app.render(into: &canvas, now: now)
    do {
        try display.present(canvas)
    } catch {
        log("present error: \(error)")
    }

    if let surface {
        for change in lights.changes(to: app.padColors(now: now)) {
            try? surface.send(ControlSurfaceProtocol.padColor(pad: change.panelPad, change.color))
        }
    }
}

if let surface {
    for change in lights.off() { try? surface.send(ControlSurfaceProtocol.padColor(pad: change.panelPad, change.color)) }
}
app.quit()  // a stop signal: save as any other way out
if app.lifecycle == .poweringOff {
    app.render(into: &canvas, now: monotonicSeconds())  // "Shutting down..."
    try? display.present(canvas)
}
log("exit: \(app.lifecycle)")
exit(app.lifecycle.exitCode)
