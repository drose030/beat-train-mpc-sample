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

    @Test func garbageIsNotAStem() {
        let engine = AudioEngine(offlineRate: Self.rate)
        #expect(throws: HardwareError.self) { try engine.addStem(encoded: [0, 1, 2, 3]) }
    }
}
