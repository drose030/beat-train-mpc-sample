// Beat-Train on the MPC Sample: pick a song with the encoder, play its drum chart
// on the pads. Started by the SD-card autorun in place of the stock app; SHIFT +
// STOP quits back to it.
//
//   beattrain [--songs DIR]...           run on the device
//   beattrain --songs DIR --preview DIR  render sample frames as PPM files and exit
//   beattrain --songs DIR --demo DIR     render frames for the README's animations
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

func writePPM(_ canvas: Canvas, to path: String, quiet: Bool = false) {
    let data = canvas.ppmData()
    guard let file = fopen(path, "wb") else { return log("cannot write \(path)") }
    fwrite(data, 1, data.count, file)
    fclose(file)
    if !quiet { log("wrote \(path)") }
}

/// Renders each screen once, with a simulated part-played chart, for checks off-device.
func renderPreviews(app: BeatTrainApp, into directory: String) {
    var canvas = Canvas(width: 320, height: 240)
    var now = 1000.0
    var shots = 0
    func shot(_ name: String) {
        shots += 1
        app.render(into: &canvas, now: now)
        writePPM(canvas, to: "\(directory)/\(shots)-\(name).ppm")
    }
    // Hit three of four notes up to 0.6 s before the 40th, then look at the highway.
    guard var song = PlayThrough(app: app, song: 1, now: now, misses: { $0 % 4 == 3 }, shot: shot) else { return log("no chart started") }
    song.step(1.2)
    now = song.now
    shot("countin")
    let notes = song.play?.session.chart.notes ?? []
    if !notes.isEmpty {
        song.countIn()
        song.play(until: notes[min(40, notes.count - 1)].timeSec - 0.6)
        now = song.now
    }
    shot("playing")
    app.handle(.button(.stop, pressed: true), now: now)
    shot("results")
    app.handle(.button(.dataPush, pressed: true), now: now)
    app.handle(.button(.screen3, pressed: true), now: now)
    app.handle(.padDown(pad: 5, velocity: 100), now: now)   // panel pad 6: unused by default
    app.handle(.encoder(delta: 3), now: now)               // off -> kick -> snare -> hi-hat
    shot("padsetup")
    app.handle(.button(.stop, pressed: true), now: now)
    app.handle(.button(.screen2, pressed: true), now: now)
    app.handle(.encoder(delta: 3), now: now)                // METRONOME
    app.handle(.button(.dataPush, pressed: true), now: now)
    app.handle(.encoder(delta: 12), now: now)               // 60 %
    shot("settings")
    app.powerButtonPressed(now: now)
    shot("shutdown")
}

let arguments = CommandLine.arguments
let roots = StartupPaths.songRoots(arguments: arguments, environmentSongs: getenv("BEATTRAIN_SONGS").map { String(cString: $0) })
let songs = roots.flatMap { SongLibrary.scan(root: URL(fileURLWithPath: $0)) }
log("Beat-Train \(BeatTrainApp.version)")
log("songs: \(songs.count) in \(roots)")

if arguments.contains("--list") {
    for song in songs {
        guard let notesURL = song.notesURL else { continue }
        let charts = DrumDifficulty.allCases.compactMap { difficulty -> String? in
            guard let chart = try? DrumChartLoader.parse(from: notesURL, difficulty: difficulty, proDrums: song.hasProDrums), !chart.notes.isEmpty else { return nil }
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

if let directory = option("--demo", in: arguments) {
    for sub in HighwayLayout.allCases.map(Demo.playFolder) + ["pads"] {
        try? FileManager.default.createDirectory(atPath: "\(directory)/\(sub)", withIntermediateDirectories: true)
    }
    for layout in HighwayLayout.allCases {
        // The horizontal one with its line half way, to show the trail of struck notes.
        Demo.renderPlay(songs: songs, roots: roots, layout: layout, strikeLine: layout == .horizontal ? .middle : .edge, into: directory)
    }
    Demo.renderPads(songs: songs, roots: roots, into: directory)
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
// How long frames take to reach the panel, logged every 10 s during a song.
var frameStats = (since: monotonicSeconds(), frames: 0, total: 0.0, longest: 0.0)

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
    let sweep = app.sweep
    do {
        try display.present(canvas, sweep: sweep)
    } catch {
        log("present error: \(error)")
    }
    if case .playing = app.screen {
        let took = monotonicSeconds() - now
        // The next frames are drawn ahead by about as long as these took.
        app.displayLeadSec = min(max(app.displayLeadSec + (took - app.displayLeadSec) * 0.1, 0), 0.06)
        frameStats.frames += 1
        frameStats.total += took
        frameStats.longest = max(frameStats.longest, took)
        let elapsed = monotonicSeconds() - frameStats.since
        if elapsed >= 10 {
            let fps = Double(frameStats.frames) / elapsed
            log("display \(sweep): \(Int(fps.rounded())) fps, frame \(Int((frameStats.total / Double(frameStats.frames) * 1000).rounded())) ms on average, \(Int((frameStats.longest * 1000).rounded())) ms at most, drawn \(Int((app.displayLeadSec * 1000).rounded())) ms ahead")
            if let audio {
                // Mixing a period must stay well below its length (see the setup
                // logged at start); the delay is how long a pad sound waits.
                let stats = audio.takeStats()
                let ms = { (sec: Double) in String(Double(Int(sec * 10000)) / 10) }
                log("audio at \(BeatTrainApp.percent(app.playback.speed)): \(stats.underruns) underruns, mixing \(ms(stats.mixAverage)) ms on average, \(ms(stats.mixLongest)) ms at most, sound out after \(ms(stats.delay)) ms")
            }
            frameStats = (monotonicSeconds(), 0, 0, 0)
        }
    } else {
        frameStats = (monotonicSeconds(), 0, 0, 0)
        _ = audio?.takeStats()
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
