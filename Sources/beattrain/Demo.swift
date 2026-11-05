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
    static func renderPlay(songs: [SongMetadata], roots: [String], layout: HighwayLayout = .vertical, strikeLine: StrikeLinePosition = .edge,
                           into directory: String, seconds: Double = 8) {
        let audio = AudioEngine(offlineRate: 44100)
        let app = BeatTrainApp(songs: songs, songRoots: roots, audio: audio)
        let folder = "\(directory)/" + Self.playFolder(layout)
        var canvas = Canvas(width: 320, height: 240)
        let now = monotonicSeconds()
        app.keeper.set(.highway, to: Double(HighwayLayout.allCases.firstIndex(of: layout) ?? 0), now: now)
        app.keeper.set(.strikeLine, to: Double(StrikeLinePosition.allCases.firstIndex(of: strikeLine) ?? 0), now: now)
        guard var song = PlayThrough(app: app, audio: audio, song: 1, now: now, misses: { $0 % 9 == 4 }) else { return log("no chart started") }
        guard let firstNote = song.play?.session.chart.notes.first else { return log("no notes") }
        // Count in and play up to the start without drawing, then draw each frame.
        song.countIn()
        song.play(until: firstNote.timeSec + 6, step: 1 / fps)
        var frame = 0
        for _ in 0..<Int(seconds * fps) {
            song.step(1 / fps)
            app.render(into: &canvas, now: song.now)
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
