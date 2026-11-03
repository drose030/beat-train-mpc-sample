import Foundation
import Testing
@testable import MPCHardware

/// Ogg Vorbis and WAV stems and effects, offline. The Ogg fixtures are a 1 kHz
/// sine, 0.5 s (ffmpeg's `sine` source): mono at 44.1 kHz with peak 1/8 (oggenc),
/// and stereo at 48 kHz with peak 1/8 / √2 (ffmpeg's vorbis encoder after `-ac 2`).
struct DecoderTests {
    private static let rate: UInt32 = 44100

    private static func fixture(_ name: String) -> [UInt8] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(name)")
        return [UInt8]((try? Data(contentsOf: url)) ?? Data())
    }

    private func play(_ encoded: [UInt8], frames: Int) throws -> (engine: AudioEngine, samples: [Float]) {
        let engine = AudioEngine(offlineRate: Self.rate)
        try engine.addStem(encoded: encoded)
        engine.play()
        return (engine, engine.render(frames: frames))
    }

    /// Frequency from the upward zero crossings of the left channel in `frames`:
    /// whole cycles between the first and the last one.
    private func frequency(_ samples: [Float], frames: Range<Int>) -> Double {
        let crossings = frames.dropFirst().filter { samples[($0 - 1) * 2] < 0 && samples[$0 * 2] >= 0 }
        guard let first = crossings.first, let last = crossings.last, last > first else { return 0 }
        return Double(crossings.count - 1) * Double(Self.rate) / Double(last - first)
    }

    private func rms(_ samples: [Float], frames: Range<Int>) -> Double {
        let sum = frames.reduce(0.0) { $0 + Double(samples[$1 * 2] * samples[$1 * 2]) }
        return (sum / Double(frames.count)).squareRoot()
    }

    // MARK: - Ogg Vorbis

    @Test(arguments: [("sine1k-mono-44100.ogg", 0.125), ("sine1k-stereo-48000.ogg", 0.125 / 2.0.squareRoot())])
    func oggPlaysItsSine(name: String, peak: Double) throws {
        let (engine, samples) = try play(Self.fixture(name), frames: 17640)
        #expect(abs(engine.duration - 0.5) < 0.01)
        let middle = 4410..<17640
        #expect(abs(frequency(samples, frames: middle) - 1000) < 1)
        #expect(abs(rms(samples, frames: middle) - peak / 2.0.squareRoot()) < 0.005)
        let sidesDiffer = middle.contains { abs(samples[$0 * 2] - samples[$0 * 2 + 1]) > 1e-3 }
        #expect(!sidesDiffer, "the same sine on both sides")
    }

    @Test func oggStemFinishesAndRewinds() throws {
        let (engine, first) = try play(Self.fixture("sine1k-mono-44100.ogg"), frames: 2048)
        var rendered = 2048
        while !engine.isFinished && rendered < 44100 {
            _ = engine.render(frames: 512)
            rendered += 512
        }
        #expect(engine.isFinished)
        #expect(abs(Double(rendered) / Double(Self.rate) - 0.5) < 0.02)
        engine.rewind()
        engine.play()
        #expect(engine.render(frames: 2048) == first)
    }

    @Test func oggLoadsAsEffect() throws {
        let engine = AudioEngine(offlineRate: Self.rate)
        try engine.loadEffect(slot: 0, encoded: Self.fixture("sine1k-stereo-48000.ogg"))
        engine.triggerEffect(slot: 0)
        let samples = engine.render(frames: 8820)
        #expect(abs(frequency(samples, frames: 2205..<8820) - 1000) < 1)
    }

    // MARK: - WAV

    /// A WAV of `frames` (one array of channel values each), with a LIST chunk of
    /// odd length before `data` to exercise the chunk walk and its pad byte.
    private static func wav(format: UInt16, bits: UInt16, channels: Int, frames: [[Double]], extensible: Bool = false) -> [UInt8] {
        func le(_ value: UInt64, _ bytes: Int) -> [UInt8] { (0..<bytes).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) } }
        let bytes = Int(bits) / 8
        var body: [UInt8] = []
        for frame in frames {
            for value in frame {
                switch (format, bits) {
                case (3, 32): body += le(UInt64(Float(value).bitPattern), 4)
                case (3, 64): body += le(value.bitPattern, 8)
                case (_, 8): body.append(UInt8(Int((value * 128).rounded()) + 128))
                default:
                    let scaled = Int64((value * Double(Int64(1) << (bits - 1))).rounded())
                    body += le(UInt64(bitPattern: scaled), bytes)
                }
            }
        }
        let block = channels * bytes
        var fmt = le(UInt64(extensible ? 0xFFFE : format), 2) + le(UInt64(channels), 2) + le(UInt64(rate), 4)
            + le(UInt64(Int(rate) * block), 4) + le(UInt64(block), 2) + le(UInt64(bits), 2)
        if extensible {
            fmt += le(22, 2) + le(UInt64(bits), 2) + le(0, 4) + le(UInt64(format), 2)
                + [0x00, 0x00, 0x00, 0x00, 0x10, 0x00, 0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71]
        }
        var chunks: [UInt8] = Array("fmt ".utf8) + le(UInt64(fmt.count), 4) + fmt
        chunks += Array("LIST".utf8) + le(3, 4) + [1, 2, 3, 0]
        chunks += Array("data".utf8) + le(UInt64(body.count), 4) + body
        return Array("RIFF".utf8) + le(UInt64(4 + chunks.count), 4) + Array("WAVE".utf8) + chunks
    }

    /// 441 Hz at 0.5 on the left, the right at -0.25 of it, the rest 0.9.
    private static func sineFrames(channels: Int, count: Int = 1000) -> [[Double]] {
        (0..<count).map { f in
            let left = 0.5 * sin(2 * Double.pi * 441 * Double(f) / Double(rate))
            return (0..<channels).map { [left, -0.5 * left][safe: $0] ?? 0.9 }
        }
    }

    struct WAVCase: CustomTestStringConvertible, Sendable {
        let format: UInt16, bits: UInt16, channels: Int, extensible: Bool, tolerance: Float
        var testDescription: String { "format \(format), \(bits) bit, \(channels) ch\(extensible ? ", extensible" : "")" }
    }

    @Test(arguments: [
        WAVCase(format: 1, bits: 16, channels: 2, extensible: false, tolerance: 1e-4),
        WAVCase(format: 1, bits: 24, channels: 2, extensible: false, tolerance: 1e-6),
        WAVCase(format: 1, bits: 32, channels: 1, extensible: false, tolerance: 1e-6),
        WAVCase(format: 1, bits: 8, channels: 1, extensible: false, tolerance: 1e-2),
        WAVCase(format: 3, bits: 32, channels: 2, extensible: false, tolerance: 1e-6),
        WAVCase(format: 3, bits: 64, channels: 1, extensible: false, tolerance: 1e-6),
        WAVCase(format: 1, bits: 16, channels: 2, extensible: true, tolerance: 1e-4),
        WAVCase(format: 1, bits: 16, channels: 4, extensible: true, tolerance: 1e-4),
    ])
    func wavPlaysAsWritten(_ wavCase: WAVCase) throws {
        let frames = Self.sineFrames(channels: wavCase.channels)
        let encoded = Self.wav(format: wavCase.format, bits: wavCase.bits, channels: wavCase.channels, frames: frames, extensible: wavCase.extensible)
        let (engine, samples) = try play(encoded, frames: frames.count + 10)
        #expect(abs(engine.duration - Double(frames.count) / Double(Self.rate)) < 1e-9)
        var worst: Float = 0
        for (f, frame) in frames.enumerated() {
            // Mono on both sides; past two channels only the first two count.
            let right = frame.count > 1 ? frame[1] : frame[0]
            worst = max(worst, abs(samples[f * 2] - Float(frame[0])), abs(samples[f * 2 + 1] - Float(right)))
        }
        #expect(worst <= wavCase.tolerance)
        #expect(samples[(frames.count + 5) * 2] == 0, "silence after the end")
    }

    @Test func wavAtAnotherRateIsResampled() throws {
        // 22.05 kHz, so twice the frames at the device rate.
        var encoded = Self.wav(format: 1, bits: 16, channels: 1, frames: Self.sineFrames(channels: 1, count: 2205))
        let half = UInt32(22050)
        for (offset, value) in [(24, half), (28, half * 2)] {
            for b in 0..<4 { encoded[offset + b] = UInt8(truncatingIfNeeded: value >> (8 * b)) }
        }
        let (engine, samples) = try play(encoded, frames: 4410)
        #expect(abs(engine.duration - 0.1) < 1e-6)
        #expect(abs(frequency(samples, frames: 441..<3969) - 220.5) < 1)
    }

    // MARK: - Not playable

    @Test func brokenFilesThrow() {
        let engine = AudioEngine(offlineRate: Self.rate)
        let adpcm = Self.wav(format: 2, bits: 4, channels: 1, frames: [])
        let empty = Self.wav(format: 1, bits: 16, channels: 1, frames: [])
        let noData = Array(Self.wav(format: 1, bits: 16, channels: 1, frames: [[0]]).prefix(36))
        let ogg = Array("OggS".utf8) + [UInt8](repeating: 7, count: 200)
        for bytes in [adpcm, empty, noData, ogg] {
            #expect(throws: HardwareError.self) { try engine.addStem(encoded: bytes) }
            #expect(throws: HardwareError.self) { try engine.loadEffect(slot: 0, encoded: bytes) }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
