import Foundation
import Testing
@testable import MPCHardware

/// Resampling quality, through an effect slot (decoded whole) and a stem
/// (streamed through its window): both use the same windowed-sinc kernel.
struct ResamplerTests {
    private static let rate: UInt32 = 44100
    private static let fixture: [UInt8] = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/drum-miss.mp3")
        return [UInt8]((try? Data(contentsOf: url)) ?? Data())
    }()

    /// A 0.5-amplitude sine at `hz`, resampled to 44.1 kHz; the left channel,
    /// without the first and last 200 frames (where the filter runs into silence).
    private func resampledSine(_ frequency: Double, from hz: UInt32) throws -> [Float] {
        let engine = AudioEngine(offlineRate: Self.rate)
        let count = Int(hz) / 10
        let sine = (0..<count).map { Float(0.5 * sin(2 * Double.pi * frequency * Double($0) / Double(hz))) }
        try engine.loadEffect(slot: 0, samples: sine, rate: hz)
        engine.triggerEffect(slot: 0)
        let out = engine.render(frames: Int(Self.rate) / 10)
        return stride(from: 200, to: out.count / 2 - 200, by: 1).map { out[$0 * 2] }
    }

    /// The largest distance to the same sine sampled directly at 44.1 kHz.
    private func error(_ frequency: Double, from hz: UInt32) throws -> Float {
        let out = try resampledSine(frequency, from: hz)
        return out.indices.map { index in
            let ideal = 0.5 * sin(2 * Double.pi * frequency * Double(index + 200) / Double(Self.rate))
            return abs(out[index] - Float(ideal))
        }.max() ?? 1
    }

    @Test func downsamplingKeepsTheAudibleBand() throws {
        #expect(try error(1000, from: 48000) < 1e-3)
        #expect(try error(10000, from: 48000) < 1e-3)
    }

    @Test func upsamplingKeepsTheAudibleBand() throws {
        #expect(try error(1000, from: 24000) < 1e-3)
        #expect(try error(5000, from: 24000) < 1e-3)
    }

    @Test func downsamplingDoesNotAliasWhatTheDeviceCannotPlay() throws {
        // 23 kHz is above 44.1 kHz's Nyquist; it would fold down to 21.1 kHz.
        let out = try resampledSine(23000, from: 48000)
        let rms = (out.map { $0 * $0 }.reduce(0, +) / Float(out.count)).squareRoot()
        #expect(rms < 1e-3)
    }

    @Test func sameRatePassesSamplesThrough() throws {
        let engine = AudioEngine(offlineRate: Self.rate)
        let ramp = (0..<100).map { Float($0) / 100 }
        try engine.loadEffect(slot: 0, samples: ramp, rate: Self.rate)
        engine.triggerEffect(slot: 0)
        let out = engine.render(frames: 100)
        let left = stride(from: 0, to: 200, by: 2).map { out[$0] }
        let right = stride(from: 1, to: 200, by: 2).map { out[$0] }
        #expect(left == ramp)
        #expect(right == ramp)
    }

    @Test func aStreamedStemSoundsLikeTheWholeDecodedFile() throws {
        let frames = 14000  // past several window refills, short of the fixture's end (0.34 s)
        let stem = AudioEngine(offlineRate: Self.rate)
        _ = try stem.addStem(encoded: Self.fixture)
        stem.play()
        let streamed = stem.render(frames: frames)

        let effect = AudioEngine(offlineRate: Self.rate)
        try effect.loadEffect(slot: 0, encoded: Self.fixture)
        effect.triggerEffect(slot: 0)
        let whole = effect.render(frames: frames)

        let difference = zip(streamed, whole).map { abs($0 - $1) }.max() ?? 1
        #expect(difference < 1e-4)
    }
}
