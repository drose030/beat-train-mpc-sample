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

/// The player's settings that outlive a session, kept as JSON (on the MPC in
/// `BeatTrain/settings.json` on the card). Missing or unreadable files and missing
/// keys fall back to the defaults, so older and newer files both load. Values are
/// clamped to their ranges.
public struct PlayerSettings: Codable, Equatable, Sendable {
    /// See `TimingConfiguration.timingOffsetMs`.
    public var timingOffsetMs: Double {
        didSet { timingOffsetMs = TimingConfiguration.clampOffsetMs(timingOffsetMs) }
    }
    /// The whole hit window (see `TimingConfiguration.hitWindowTotalSec`), in ms.
    public var hitWindowMs: Double {
        didSet {
            hitWindowMs = TimingConfiguration.clampTotal(hitWindowMs / 1000) * 1000
            earlyWindowMs = TimingConfiguration.clampFront(earlyWindowMs / 1000, total: hitWindowMs / 1000) * 1000
        }
    }
    /// The part of the hit window before a note (`hitWindowFrontSec`), in ms.
    public var earlyWindowMs: Double {
        didSet { earlyWindowMs = TimingConfiguration.clampFront(earlyWindowMs / 1000, total: hitWindowMs / 1000) * 1000 }
    }
    /// Metronome click volume, 0–1; 0 is off.
    public var metronomeVolume: Double {
        didSet { metronomeVolume = Self.clampVolume(metronomeVolume) }
    }
    /// Miss sound volume, 0–1; 0 is off.
    public var missSoundVolume: Double {
        didSet { missSoundVolume = Self.clampVolume(missSoundVolume) }
    }
    /// Volume per stem name ("drums", "vocals"…), 0–1; a missing stem is at 1.
    public var stemVolumes: [String: Double] {
        didSet { stemVolumes = stemVolumes.mapValues(Self.clampVolume) }
    }
    /// Which voice each of the eight pads plays (see `DrumKit.padVoices`).
    public var padVoices: [Int: DrumVoice]

    public static let defaultHitWindowMs = 120.0
    public static let defaultEarlyWindowMs = 50.0
    public static let defaultMissSoundVolume = 1.0

    public init(
        timingOffsetMs: Double = 0,
        hitWindowMs: Double = PlayerSettings.defaultHitWindowMs,
        earlyWindowMs: Double = PlayerSettings.defaultEarlyWindowMs,
        metronomeVolume: Double = 0,
        missSoundVolume: Double = PlayerSettings.defaultMissSoundVolume,
        stemVolumes: [String: Double] = [:],
        padVoices: [Int: DrumVoice] = DrumKit.defaultPadVoices
    ) {
        // Through the same clamps as later changes (didSet does not run in init).
        let timing = TimingConfiguration(totalSec: hitWindowMs / 1000, frontSec: earlyWindowMs / 1000, offsetMs: timingOffsetMs)
        self.timingOffsetMs = timing.timingOffsetMs
        self.hitWindowMs = timing.hitWindowTotalSec * 1000
        self.earlyWindowMs = timing.hitWindowFrontSec * 1000
        self.metronomeVolume = Self.clampVolume(metronomeVolume)
        self.missSoundVolume = Self.clampVolume(missSoundVolume)
        self.stemVolumes = stemVolumes.mapValues(Self.clampVolume)
        self.padVoices = padVoices
    }

    public var kit: DrumKit {
        DrumKit(padVoices: padVoices)
    }

    public var timing: TimingConfiguration {
        TimingConfiguration(totalSec: hitWindowMs / 1000, frontSec: earlyWindowMs / 1000, offsetMs: timingOffsetMs)
    }

    public func stemVolume(_ stem: String) -> Double {
        stemVolumes[stem] ?? 1
    }

    static func clampVolume(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private enum CodingKeys: String, CodingKey {
        case timingOffsetMs, hitWindowMs, earlyWindowMs, metronomeVolume, missSoundVolume, stemVolumes, padVoices
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ type: T.Type, _ key: CodingKeys) -> T? {
            (try? container.decodeIfPresent(type, forKey: key)) ?? nil
        }
        // Pads are stored as {"0": "kick", ...}; unknown pads or voices are skipped
        // and missing pads keep their default.
        var voices = DrumKit.defaultPadVoices
        for (key, name) in value([String: String].self, .padVoices) ?? [:] {
            if let pad = Int(key), (0..<DrumKit.padCount).contains(pad), let voice = DrumVoice(rawValue: name) {
                voices[pad] = voice
            }
        }
        self.init(
            timingOffsetMs: value(Double.self, .timingOffsetMs) ?? 0,
            hitWindowMs: value(Double.self, .hitWindowMs) ?? Self.defaultHitWindowMs,
            earlyWindowMs: value(Double.self, .earlyWindowMs) ?? Self.defaultEarlyWindowMs,
            metronomeVolume: value(Double.self, .metronomeVolume) ?? 0,
            missSoundVolume: value(Double.self, .missSoundVolume) ?? Self.defaultMissSoundVolume,
            stemVolumes: value([String: Double].self, .stemVolumes) ?? [:],
            padVoices: voices
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timingOffsetMs, forKey: .timingOffsetMs)
        try container.encode(hitWindowMs, forKey: .hitWindowMs)
        try container.encode(earlyWindowMs, forKey: .earlyWindowMs)
        try container.encode(metronomeVolume, forKey: .metronomeVolume)
        try container.encode(missSoundVolume, forKey: .missSoundVolume)
        try container.encode(stemVolumes, forKey: .stemVolumes)
        try container.encode(
            Dictionary(uniqueKeysWithValues: padVoices.map { (String($0.key), $0.value.rawValue) }),
            forKey: .padVoices
        )
    }

    /// The settings in `url`, or the defaults.
    public static func load(from url: URL) -> PlayerSettings {
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(PlayerSettings.self, from: data)
        else {
            return PlayerSettings()
        }
        return settings
    }

    /// Writes the settings to `url` (via a temporary file, so a power loss leaves
    /// the old or the new file, never half of one).
    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
        // Flush it to the card now; it may be pulled out soon after.
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }
}
