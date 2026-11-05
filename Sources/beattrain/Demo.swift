import BeatTrainCore
import MPCHardware

/// Frames for the README's animations, rendered off-device: a few seconds of play
/// (`play/frame-NNNN.ppm`, on the other highways `play-by-pad/` and `play-horizontal/`)
/// and the pad setup (`pads/frame-NNNN.ppm`).
enum Demo {
    static let fps = 25.0

    /// The second song on Expert with its stems in an offline engine (so the clock
    /// runs as on the device), from a few seconds after its first note: each note
    /// struck on time, every ninth one missed.
    static func renderPlay(songs: [SongMetadata], roots: [String], layout: HighwayLayout = .vertical, into directory: String, seconds: Double = 8) {
        let audio = AudioEngine(offlineRate: 44100)
        let app = BeatTrainApp(songs: songs, songRoots: roots, audio: audio)
        let folder = "\(directory)/" + Self.playFolder(layout)
        var canvas = Canvas(width: 320, height: 240)
        var now = monotonicSeconds()
        app.keeper.set(.highway, to: Double(HighwayLayout.allCases.firstIndex(of: layout) ?? 0), now: now)
        app.handle(.encoder(delta: 1), now: now)
        app.handle(.button(.dataPush, pressed: true), now: now)
        app.handle(.button(.dataPush, pressed: true), now: now)
        app.tick(now: now)
        app.tick(now: now)
        guard case let .playing(play) = app.screen else { return log("no chart started") }
        let notes = play.session.chart.notes
        guard let firstNote = notes.first else { return log("no notes") }
        let start = firstNote.timeSec + 6
        var next = 0
        var frame = 0
        func step() {
            now += 1 / fps
            _ = audio.render(frames: Int(44100 / fps))
            let time = app.playback.chartTime(now: now)
            while next < notes.count, notes[next].timeSec <= time {
                if next % 9 != 4 {
                    let pad = DrumKit.pad(forLayout: app.kit.target(remapping: notes[next].target))
                    app.handle(.padDown(pad: PanelPads.panelPad(forPad: pad), velocity: 100), now: now)
                }
                next += 1
            }
            app.tick(now: now)
        }
        // Count in and play up to the start without drawing, then draw each frame.
        now = app.playback.startsAt
        app.tick(now: now)
        while app.playback.chartTime(now: now) < start { step() }
        for _ in 0..<Int(seconds * fps) {
            step()
            app.render(into: &canvas, now: now)
            write(canvas, frame: frame, to: folder)
            frame += 1
        }
        log("wrote \(frame) frames to \(folder)")
    }

    static func playFolder(_ layout: HighwayLayout) -> String {
        switch layout {
        case .vertical: "play"
        case .verticalByPad: "play-by-pad"
        case .horizontal: "play-horizontal"
        }
    }

    /// The pad setup: pick a few pads and step through their sounds.
    static func renderPads(songs: [SongMetadata], roots: [String], into directory: String) {
        let app = BeatTrainApp(songs: songs, songRoots: roots, audio: nil)
        var canvas = Canvas(width: 320, height: 240)
        var now = 2000.0
        var frame = 0
        func hold(_ seconds: Double) {
            for _ in 0..<Int(seconds * fps) {
                now += 1 / fps
                app.render(into: &canvas, now: now)
                write(canvas, frame: frame, to: "\(directory)/pads")
                frame += 1
            }
        }
        app.handle(.button(.screen3, pressed: true), now: now)
        hold(1)
        for (panelPad, turns) in [(5, [1, 1, 1]), (6, [1, 1, 1, 1, 1]), (5, [-1, -1, -1])] {
            app.handle(.padDown(pad: panelPad, velocity: 100), now: now)
            hold(0.7)
            for delta in turns {
                app.handle(.encoder(delta: delta), now: now)
                hold(0.5)
            }
        }
        app.handle(.button(.screen1, pressed: true), now: now)
        hold(1.2)
        log("wrote \(frame) frames to \(directory)/pads")
    }

    private static func write(_ canvas: Canvas, frame: Int, to directory: String) {
        let number = String(frame + 10000).dropFirst()
        writePPM(canvas, to: "\(directory)/frame-\(number).ppm", quiet: true)
    }
}
