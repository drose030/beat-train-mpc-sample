import Foundation
import Testing
@testable import MPCHardware

/// The mixer and clock, offline (no device): `drum-miss.mp3` is 24 kHz stereo,
/// 0.36 s, so it also exercises the resampler.
struct AudioEngineTests {
    private static let rate: UInt32 = 44100
    private static let fixture: [UInt8] = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/drum-miss.mp3")
        return [UInt8]((try? Data(contentsOf: url)) ?? Data())
    }()

    private func peak(_ samples: [Float]) -> Float {
        samples.map(abs).max() ?? 0
    }

    @Test func stemPlaysAtTheDeviceRateAndFinishes() throws {
        let engine = AudioEngine(offlineRate: Self.rate)
        try engine.addStem(encoded: Self.fixture)
        #expect(abs(engine.duration - 0.36) < 0.03)

        #expect(peak(engine.render(frames: 4410)) == 0, "silent until play")
        engine.play()
        var rendered = 0
        var loudest: Float = 0
        while !engine.isFinished && rendered < 44100 {
            loudest = max(loudest, peak(engine.render(frames: 512)))
            rendered += 512
        }
        #expect(engine.isFinished)
        #expect(loudest > 0.05)
        // 0.36 s at 44.1 kHz, rendered in 512-frame blocks.
        #expect(abs(Double(rendered) / Double(Self.rate) - engine.duration) < 0.03)
    }

    @Test func positionCountsOnlyWhilePlaying() throws {
        let engine = AudioEngine(offlineRate: Self.rate)
        try engine.addStem(encoded: Self.fixture)
        engine.play()
        _ = engine.render(frames: 4410)
        #expect(abs(engine.position - 0.1) < 0.001)
        engine.pause()
        _ = engine.render(frames: 4410)
        #expect(abs(engine.position - 0.1) < 0.001)
        engine.clearStems()
        #expect(engine.position == 0)
    }

    @Test func rewindPlaysTheSongAgainFromTheStart() throws {
        let engine = AudioEngine(offlineRate: Self.rate)
        try engine.addStem(encoded: Self.fixture)
        engine.play()
        let first = engine.render(frames: 8820)
        while !engine.isFinished { _ = engine.render(frames: 512) }
        engine.rewind()
        #expect(engine.position == 0)
        #expect(!engine.isFinished)
        #expect(peak(engine.render(frames: 512)) == 0, "stopped until play")
        engine.play()
        let again = engine.render(frames: 8820)
        #expect(again == first, "same samples from the start")
    }

    @Test func zeroGainSilencesAStem() throws {
        let engine = AudioEngine(offlineRate: Self.rate)
        let stem = try engine.addStem(encoded: Self.fixture)
        engine.setGain(0, forStem: stem)
        engine.play()
        #expect(peak(engine.render(frames: 8820)) == 0)
    }

    @Test func effectPlaysWithoutASong() throws {
        let engine = AudioEngine(offlineRate: Self.rate)
        try engine.loadEffect(slot: 0, encoded: Self.fixture)
        engine.triggerEffect(slot: 0)
        #expect(peak(engine.render(frames: 8820)) > 0.05)
        engine.setEffectGain(0, slot: 0)
        engine.triggerEffect(slot: 0)
        #expect(peak(engine.render(frames: 8820)) == 0)
        engine.setEffectGain(1, slot: 0)
        engine.setMaster(0)
        engine.triggerEffect(slot: 0)
        #expect(peak(engine.render(frames: 8820)) == 0)
    }

    @Test func scheduledEffectStartsAtItsSongFrame() throws {
        let engine = AudioEngine(offlineRate: Self.rate)
        let silent = try engine.addStem(encoded: Self.fixture)
        engine.setGain(0, forStem: silent)
        try engine.loadEffect(slot: 1, samples: [Float](repeating: 0.5, count: 100), rate: Self.rate)
        engine.scheduleEffect(slot: 1, atSongTime: 1000.0 / Double(Self.rate))  // song frame 1000
        #expect(peak(engine.render(frames: 512)) == 0, "nothing before the song plays")
        engine.play()
        let first = engine.render(frames: 512)   // song frames 0-511
        let second = engine.render(frames: 512)  // song frames 512-1023: starts at 488
        #expect(peak(first) == 0)
        #expect(second[487 * 2] == 0)
        #expect(second[488 * 2] == 0.5)
        #expect(second[511 * 2] == 0.5)
    }

    @Test func scheduledEffectsAreDroppedWithTheSong() throws {
        let engine = AudioEngine(offlineRate: Self.rate)
        let silent = try engine.addStem(encoded: Self.fixture)
        engine.setGain(0, forStem: silent)
        try engine.loadEffect(slot: 1, samples: [Float](repeating: 0.5, count: 100), rate: Self.rate)
        engine.scheduleEffect(slot: 1, atSongTime: 0.01)
        engine.clearStems()
        let again = try engine.addStem(encoded: Self.fixture)
        engine.setGain(0, forStem: again)
        engine.play()
        #expect(peak(engine.render(frames: 2048)) == 0)
    }

    /// A mono 16-bit WAV of a sine at half level.
    private static func sineWAV(hz: Double, seconds: Double) -> [UInt8] {
        let samples = (0..<Int(seconds * Double(rate))).map { Int16(16384 * sin(2 * Double.pi * hz * Double($0) / Double(rate))) }
        func le(_ value: Int, _ bytes: Int) -> [UInt8] { (0..<bytes).map { UInt8((value >> (8 * $0)) & 0xFF) } }
        let data = samples.flatMap { le(Int(UInt16(bitPattern: $0)), 2) }
        let format = le(1, 2) + le(1, 2) + le(Int(rate), 4) + le(Int(rate) * 2, 4) + le(2, 2) + le(16, 2)
        let chunks = Array("fmt ".utf8) + le(format.count, 4) + format + Array("data".utf8) + le(data.count, 4) + data
        return Array("RIFF".utf8) + le(4 + chunks.count, 4) + Array("WAVE".utf8) + chunks
    }

    /// The left channel of interleaved stereo.
    private func left(_ samples: [Float]) -> [Float] {
        stride(from: 0, to: samples.count, by: 2).map { samples[$0] }
    }

    @Test func atFullSpeedTheOutputIsTheSong() throws {
        let engine = AudioEngine(offlineRate: Self.rate)
        try engine.addStem(encoded: Self.sineWAV(hz: 440, seconds: 1))
        engine.play()
        let out = left(engine.render(frames: 4096))
        let expected = (0..<4096).map { Float(Int16(16384 * sin(2 * Double.pi * 440 * Double($0) / Double(Self.rate)))) / 32768 }
        #expect(zip(out, expected).allSatisfy { abs($0 - $1) < 1e-4 }, "sample for sample, from the first frame")
    }

    @Test func halfSpeedKeepsThePitchAndTheLevel() throws {
        let engine = AudioEngine(offlineRate: Self.rate)
        try engine.addStem(encoded: Self.sineWAV(hz: 440, seconds: 2))
        engine.speed = 0.5
        engine.play()
        let out = left(engine.render(frames: Int(Self.rate)))
        #expect(abs(engine.position - 0.5) < 0.001, "one second of output is half a second of song")
        // Rising zero crossings over half a second: 220 for 440 Hz.
        let part = Array(out[11025..<33075])
        let crossings = zip(part, part.dropFirst()).filter { $0 < 0 && $1 >= 0 }.count
        #expect(abs(crossings - 220) <= 4, "\(crossings) crossings")
        // No dips where the segments overlap: every 10 ms keeps the sine's level.
        for block in stride(from: 2048, to: out.count - 441, by: 441) {
            #expect(abs(out[block..<block + 441].map(abs).max()! - 0.5) < 0.05, "level at frame \(block)")
        }
    }

    @Test func speedChangesApplyAsTheSongRuns() throws {
        let engine = AudioEngine(offlineRate: Self.rate)
        try engine.addStem(encoded: Self.sineWAV(hz: 440, seconds: 2))
        engine.play()
        _ = engine.render(frames: 22050)
        engine.speed = 0.5
        _ = engine.render(frames: 22050)
        #expect(abs(engine.position - 0.75) < 0.015, "0.5 s at full speed, then 0.25 s at half: \(engine.position)")
        engine.speed = 0.2
        #expect(engine.speed == 0.5, "no slower than half")
    }

    @Test func slowingDownMidSongStaysSmooth() throws {
        let engine = AudioEngine(offlineRate: Self.rate)
        try engine.addStem(encoded: Self.sineWAV(hz: 440, seconds: 3))
        engine.play()
        var out = left(engine.render(frames: 10000))
        // Slowing down in steps, as the fader does, then back up.
        for speed in [0.95, 0.9, 0.75, 0.5, 0.75, 1.0] {
            engine.speed = speed
            out += left(engine.render(frames: 5000))
        }
        // A 440 Hz sine at half level never moves more than 0.032 from one frame to the next.
        let jumps = zip(out, out.dropFirst()).enumerated().filter { abs($1.1 - $1.0) > 0.04 }.map(\.offset)
        #expect(jumps.isEmpty, "jumps at frames \(jumps.prefix(5))")
        for block in stride(from: 1024, to: out.count - 441, by: 441) {
            #expect(abs(out[block..<block + 441].map(abs).max()! - 0.5) < 0.05, "level at frame \(block)")
        }
    }

    @Test func scheduledEffectFollowsTheSlowerSong() throws {
        let engine = AudioEngine(offlineRate: Self.rate)
        let silent = try engine.addStem(encoded: Self.fixture)
        engine.setGain(0, forStem: silent)
        try engine.loadEffect(slot: 1, samples: [Float](repeating: 0.5, count: 100), rate: Self.rate)
        engine.scheduleEffect(slot: 1, atSongTime: 1000.0 / Double(Self.rate))  // song frame 1000
        engine.speed = 0.5
        engine.play()
        let out = left(engine.render(frames: 4096))
        #expect(out.firstIndex { $0 != 0 } == 2000, "song frame 1000 is output frame 2000")
    }

    @Test func garbageIsNotAStem() {
        let engine = AudioEngine(offlineRate: Self.rate)
        #expect(throws: HardwareError.self) { try engine.addStem(encoded: [0, 1, 2, 3]) }
    }
}
