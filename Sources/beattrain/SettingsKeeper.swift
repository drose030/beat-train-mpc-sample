import BeatTrainCore
#if canImport(FoundationEssentials)
import FoundationEssentials  // no ICU: keeps the static Linux binary small
#else
import Foundation
#endif
import MPCHardware

/// Where the player's settings are kept between starts.
protocol SettingsStorage {
    func load() -> PlayerSettings
    func save(_ settings: PlayerSettings) throws
}

/// `settings.json` on the card.
struct SettingsFile: SettingsStorage {
    let url: URL

    func load() -> PlayerSettings {
        PlayerSettings.load(from: url)
    }

    func save(_ settings: PlayerSettings) throws {
        try settings.save(to: url)
    }
}

/// The stems SHIFT+K1–K3 turn together: the song stem, the drums, all the rest.
enum StemGroup: CaseIterable {
    case song, drums, others

    var title: String {
        switch self {
        case .song: "SONG"
        case .drums: "DRUMS"
        case .others: "OTHERS"
        }
    }

    var stems: [Stem] {
        switch self {
        case .song: [.song]
        case .drums: [.drums]
        case .others: Stem.allCases.filter { $0 != .song && $0 != .drums }
        }
    }
}

/// The player's settings while the app runs: the one way to change them (by
/// settings line, encoder step, knob turn or pad voice), which knob turns which
/// setting, and saving them a moment after the last change.
final class SettingsKeeper {
    /// K1–K3 and the setting each turns, in panel order.
    static let knobs: [(control: PanelControl, item: SettingsItem)] = [
        (.k1, .timingOffset), (.k2, .metronome), (.k3, .missSound),
    ]
    /// K1–K3 with SHIFT held: the stems each turns.
    static let mixKnobs: [(control: PanelControl, group: StemGroup)] = [
        (.k1, .song), (.k2, .drums), (.k3, .others),
    ]
    /// How long after the last change the settings are saved.
    static let saveDelaySec = 2.0

    /// "K1" for the setting K1 turns.
    static func knobName(for item: SettingsItem) -> String? {
        knobs.firstIndex { $0.item == item }.map { "K\($0 + 1)" }
    }

    private(set) var current: PlayerSettings
    /// Called after every change that changed something: the settings line, or
    /// nil for the pads.
    var onChange: ((SettingsItem?) -> Void)?

    private let storage: SettingsStorage?
    private var changedAt: Double?
    /// K1–K3, the same with SHIFT held or not.
    private var knobControls: [PanelControl: RelativeControl] = [:]

    /// `storage` nil: the defaults, never saved.
    init(storage: SettingsStorage?) {
        self.storage = storage
        current = storage?.load() ?? PlayerSettings()
    }

    // MARK: - Changes

    /// Sets a line's value, rounded to its step and kept in its range.
    func set(_ item: SettingsItem, to value: Double, now: Double) {
        var settings = current
        item.set(value, in: &settings)
        commit(settings, item: item, now: now)
    }

    /// One encoder detent on a line.
    func step(_ item: SettingsItem, by delta: Int, now: Double) {
        set(item, to: item.value(in: current) + Double(delta) * item.step, now: now)
    }

    func reset(_ item: SettingsItem, now: Double) {
        set(item, to: item.defaultValue(), now: now)
    }

    /// A knob reported `value`: its setting moves by how far it turned since its
    /// last report. Returns the setting it turns; nil for a control that is no
    /// knob, and for a knob's first report, which only tells where it stands.
    @discardableResult
    func turn(_ control: PanelControl, to value: UInt8, now: Double) -> SettingsItem? {
        guard let item = Self.knobs.first(where: { $0.control == control })?.item,
              let moved = knobControls[control, default: RelativeControl()].move(
                  to: value, from: item.value(in: current), step: item.step, travel: item.fullTurn, range: item.range(in: current))
        else { return nil }
        set(item, to: moved, now: now)
        return item
    }

    /// A knob reported `value` with SHIFT held: the stems of its group move together
    /// by how far it turned (a whole turn is 0–100 %), each keeping its distance to
    /// the others. Only the stems in `present` (the song's; nil: all) move. Returns
    /// the group; nil for a control that is no knob, a knob's first report, and a
    /// group with none of its stems present.
    @discardableResult
    func turnMix(_ control: PanelControl, to value: UInt8, present: Set<Stem>?, now: Double) -> StemGroup? {
        guard let group = Self.mixKnobs.first(where: { $0.control == control })?.group else { return nil }
        let stems = group.stems.filter { present?.contains($0) ?? true }
        // The loudest stem moves as a stem's line would; the others by as much.
        let item = SettingsItem.stem(stems.first ?? .song)
        let level = level(of: group, present: present)
        guard let moved = knobControls[control, default: RelativeControl()].move(
                  to: value, from: level, step: item.step, travel: item.fullTurn, range: item.range(in: current)),
              !stems.isEmpty
        else { return nil }
        let steps = (moved / item.step).rounded() - (level / item.step).rounded()
        var settings = current
        for stem in stems {
            settings.stemVolumes[stem] = ((settings.stemVolume(stem) + steps * item.step) / item.step).rounded() * item.step
        }
        commit(settings, item: item, now: now)
        return group
    }

    /// The level SHIFT+knob shows for a group: its loudest stem in `present`.
    func level(of group: StemGroup, present: Set<Stem>?) -> Double {
        group.stems.filter { present?.contains($0) ?? true }.map(current.stemVolume).max() ?? 1
    }

    func setVoice(_ voice: DrumVoice, forPad pad: Int, now: Double) {
        var settings = current
        settings.padVoices[pad] = voice
        commit(settings, item: nil, now: now)
    }

    func resetPads(now: Double) {
        var settings = current
        settings.padVoices = DrumKit.defaultPadVoices
        commit(settings, item: nil, now: now)
    }

    private func commit(_ settings: PlayerSettings, item: SettingsItem?, now: Double) {
        guard settings != current else { return }
        current = settings
        changedAt = now
        onChange?(item)
    }

    // MARK: - Saving

    /// Saves changed settings `saveDelaySec` after the last change.
    func saveIfDue(now: Double) {
        guard let changedAt, now - changedAt >= Self.saveDelaySec else { return }
        saveNow()
    }

    /// Saves changed settings at once (leaving a screen, quitting).
    func saveNow() {
        guard changedAt != nil, let storage else { return }
        changedAt = nil
        do {
            try storage.save(current)
            log("settings saved")
        } catch {
            log("settings not saved: \(error)")
        }
    }
}
