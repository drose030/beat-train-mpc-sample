import CMPCHardware
import Foundation
import Testing

/// The time stretch and the heard clock of the audio engine, on their own.
struct StretchTests {
    /// A song source: a sine of `period` frames, both channels, counting frames read.
    final class Sine {
        let period: Double
        var frame = 0
        init(period: Double) { self.period = period }
    }

    private static let read: cmpc_stretch_source = { context, out, frames in
        let sine = Unmanaged<Sine>.fromOpaque(context!).takeUnretainedValue()
        for f in 0..<frames {
            let v = Float(sin(2 * Double.pi * Double(sine.frame) / sine.period))
            out![f * 2] += v
            out![f * 2 + 1] += v
            sine.frame += 1
        }
    }

    private func render(_ sine: Sine, speed: Double, frames: Int) -> (out: [Float], song: [Double], position: Double) {
        let stretch = cmpc_stretch_new(Self.read, Unmanaged.passUnretained(sine).toOpaque())!
        defer { cmpc_stretch_free(stretch) }
        var out = [Float](repeating: 0, count: frames * 2)
        var song = [Double](repeating: 0, count: frames)
        cmpc_stretch_render(stretch, speed, &out, &song, frames)
        return (out, song, cmpc_stretch_position(stretch))
    }

    private func crossings(_ stereo: [Float]) -> Int {
        let left = stride(from: 0, to: stereo.count, by: 2).map { stereo[$0] }
        return zip(left, left.dropFirst()).filter { ($0 < 0) != ($1 < 0) }.count
    }

    @Test func atFullSpeedTheOutputIsTheSong() {
        let sine = Sine(period: 100)
        let (out, song, position) = render(sine, speed: 1, frames: 4000)
        // Sample for sample, up to float rounding where two window halves overlap.
        let worst = (0..<4000).map { abs(out[$0 * 2] - Float(sin(2 * Double.pi * Double($0) / 100))) }.max()!
        #expect(worst < 1e-6)
        #expect(song[0] == 0 && song[3999] == 3999)
        #expect(position == 4000)
    }

    @Test func atHalfSpeedHalfTheSongPlaysAtTheSamePitch() {
        let sine = Sine(period: 100)
        let (out, song, position) = render(sine, speed: 0.5, frames: 8192)
        #expect(position == 4096)
        #expect(song[8191] == 4095.5)
        // A 441 Hz tone stays one: about two crossings per 100 frames, not one.
        let found = crossings(out)
        #expect(abs(found - 8192 * 2 / 100) <= 4, "\(found) crossings")
    }

    @Test func theHeardClockInterpolatesBetweenNotesAndRunsOnUpToTheMix() {
        let clock = cmpc_heard_clock_new()!
        defer { cmpc_heard_clock_free(clock) }
        #expect(cmpc_heard_clock_song_frame(clock, 5, 44100, 1000) == 0, "nothing heard yet")
        cmpc_heard_clock_note(clock, 0, 0)
        cmpc_heard_clock_note(clock, 512, 512)
        cmpc_heard_clock_note(clock, 1024, 768)   // the second piece at half speed
        cmpc_heard_clock_hear(clock, 768, 10)
        #expect(cmpc_heard_clock_song_frame(clock, 10, 22050, 768) == 640)
        #expect(abs(cmpc_heard_clock_song_frame(clock, 10.001, 22050, 768) - (640 + 22.05)) < 1e-6, "on with the wall clock")
        #expect(cmpc_heard_clock_song_frame(clock, 11, 22050, 768) == 768, "never past what was mixed")
        #expect(cmpc_heard_clock_song_frame(clock, 11, 0, 768) == 640, "paused: it stands")
        cmpc_heard_clock_reset(clock)
        #expect(cmpc_heard_clock_song_frame(clock, 11, 22050, 768) == 0)
    }
}
