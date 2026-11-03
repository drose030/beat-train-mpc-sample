import Foundation
import Testing
@testable import BeatTrainCore

struct PlayerSettingsTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("settings-\(UUID().uuidString)")
            .appendingPathComponent("settings.json")
    }

    @Test func savesAndLoadsTheTimingOffset() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try PlayerSettings(timingOffsetMs: -35).save(to: url)
        #expect(PlayerSettings.load(from: url).timingOffsetMs == -35)
    }

    @Test func missingOrBrokenFileGivesDefaults() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(PlayerSettings.load(from: url) == PlayerSettings())
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: url)
        #expect(PlayerSettings.load(from: url) == PlayerSettings())
    }

    @Test func missingAndUnknownKeysAreTolerated() throws {
        let data = Data(#"{"somethingNew": true}"#.utf8)
        #expect(try JSONDecoder().decode(PlayerSettings.self, from: data) == PlayerSettings())
    }

    @Test func savesAndLoadsPadVoices() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var settings = PlayerSettings()
        settings.padVoices[1] = .yellow
        settings.padVoices[4] = .off
        try settings.save(to: url)
        let loaded = PlayerSettings.load(from: url)
        #expect(loaded.padVoices[1] == .yellow)
        #expect(loaded.padVoices[4] == .off)
        #expect(loaded.kit.voice(forPad: 1) == .yellow)
    }

    @Test func badPadEntriesKeepTheirDefaults() throws {
        let data = Data(#"{"padVoices": {"0": "cowbell", "9": "kick", "x": "red", "3": "blue"}}"#.utf8)
        let settings = try JSONDecoder().decode(PlayerSettings.self, from: data)
        #expect(settings.padVoices[0] == DrumKit.defaultPadVoices[0])
        #expect(settings.padVoices[3] == .blue)
        #expect(settings.padVoices.count == DrumKit.padCount)
    }

    @Test func offsetIsClampedToItsRange() throws {
        let data = Data(#"{"timingOffsetMs": 500}"#.utf8)
        #expect(try JSONDecoder().decode(PlayerSettings.self, from: data).timingOffsetMs == TimingConfiguration.offsetRangeMs)
    }

    @Test func savesAndLoadsWindowAndVolumes() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var settings = PlayerSettings()
        settings.hitWindowMs = 150
        settings.earlyWindowMs = 70
        settings.metronomeVolume = 0.6
        settings.missSoundVolume = 0
        settings.stemVolumes["vocals"] = 0.3
        try settings.save(to: url)
        let loaded = PlayerSettings.load(from: url)
        #expect(loaded == settings)
        #expect(loaded.timing.hitWindowTotalSec == 0.15)
        #expect(abs(loaded.timing.hitWindowBackSec - 0.08) < 1e-9)
        #expect(loaded.stemVolume("vocals") == 0.3)
        #expect(loaded.stemVolume("drums") == 1)
    }

    @Test func changesAreClamped() {
        var settings = PlayerSettings()
        settings.metronomeVolume = 3
        settings.stemVolumes["bass"] = -1
        settings.hitWindowMs = 1000
        settings.earlyWindowMs = 1000
        #expect(settings.metronomeVolume == 1)
        #expect(settings.stemVolume("bass") == 0)
        #expect(settings.hitWindowMs == TimingConfiguration.maxTotalSec * 1000)
        #expect(abs(settings.earlyWindowMs - (settings.hitWindowMs - TimingConfiguration.minSegmentSec * 1000)) < 1e-9)
        settings.hitWindowMs = 60
        #expect(settings.earlyWindowMs <= 50, "the early part shrinks with the window")
    }

    @Test func defaultsMatchTheOriginalGame() {
        let settings = PlayerSettings()
        #expect(settings.hitWindowMs == 120)
        #expect(settings.earlyWindowMs == 50)
        #expect(settings.metronomeVolume == 0)
        #expect(settings.missSoundVolume == 1)
    }
}
