import BeatTrainCore
import Foundation
import Testing
@testable import beattrain

/// Changes, knobs and saving, through `SettingsKeeper`'s interface.
struct SettingsKeeperTests {
    @Test func everyKnobHasALineAndAName() {
        #expect(SettingsKeeper.knobs.map(\.control) == [.k1, .k2, .k3])
        #expect(SettingsKeeper.knobName(for: .timingOffset) == "K1")
        #expect(SettingsKeeper.knobName(for: .missSound) == "K3")
        #expect(SettingsKeeper.knobName(for: .hitWindow) == nil)
        for knob in SettingsKeeper.knobs { #expect(SettingsItem.all.contains(knob.item)) }
    }

    @Test func changesReportWhatChangedOnlyWhenSomethingDid() {
        let keeper = SettingsKeeper(storage: nil)
        var changed: [SettingsItem?] = []
        keeper.onChange = { changed.append($0) }
        keeper.set(.metronome, to: 0.52, now: 0)
        #expect(keeper.current.metronomeVolume == 0.5, "rounded to the 5 % step")
        keeper.set(.metronome, to: 0.5, now: 0)
        keeper.set(.metronome, to: 3, now: 0)
        #expect(keeper.current.metronomeVolume == 1, "kept in range")
        keeper.setVoice(.green, forPad: 1, now: 0)
        #expect(changed == [.metronome, .metronome, nil])
    }

    @Test func aKnobsFirstReportOnlyTellsWhereItStands() {
        let keeper = SettingsKeeper(storage: nil)
        #expect(keeper.turn(.k2, to: 90, now: 0) == nil)
        #expect(keeper.current.metronomeVolume == 0)
        #expect(keeper.turn(.k2, to: 103, now: 0) == .metronome)
        #expect(keeper.current.metronomeVolume == 0.1)
        #expect(keeper.turn(.mainVolume, to: 5, now: 0) == nil, "not a settings knob")
    }

    @Test func savesAMomentAfterTheLastChangeOrAtOnce() {
        let storage = MemorySettings()
        let keeper = SettingsKeeper(storage: storage)
        keeper.set(.hitWindow, to: 150, now: 10)
        keeper.saveIfDue(now: 11.9)
        #expect(storage.saved == nil)
        keeper.saveIfDue(now: 12)
        #expect(storage.saved?.hitWindowMs == 150)
        keeper.resetPads(now: 13)
        storage.saved = nil
        keeper.saveNow()
        #expect(storage.saved == nil, "nothing changed since the last save")
        keeper.setVoice(.kick, forPad: 2, now: 14)
        keeper.saveNow()
        #expect(storage.saved?.padVoices[2] == .kick)
    }
}
