import BeatTrainCore

/// One line of the settings screen: which `PlayerSettings` value it shows, its
/// range, step and text. Some are on a knob too (`SettingsKeeper.knobs`).
enum SettingsItem: Equatable {
    case timingOffset
    case hitWindow
    case earlyWindow
    case metronome
    case missSound
    case highway
    case strikeLine
    case stem(String)

    static let all: [SettingsItem] = [.timingOffset, .hitWindow, .earlyWindow, .metronome, .missSound, .highway, .strikeLine]
        + SongPlayback.stemNames.map { .stem($0) }

    var title: String {
        switch self {
        case .timingOffset: "TIMING OFFSET"
        case .hitWindow: "HIT WINDOW"
        case .earlyWindow: "  EARLY PART"
        case .metronome: "METRONOME"
        case .missSound: "MISS SOUND"
        case .highway: "HIGHWAY"
        case .strikeLine: "  STRIKE LINE"
        case let .stem(name): "STEM \(name.uppercased())"
        }
    }

    /// What a step of the encoder changes.
    var step: Double {
        switch self {
        case .timingOffset, .hitWindow, .earlyWindow: 5
        case .metronome, .missSound, .stem: 0.05
        case .highway, .strikeLine: 1
        }
    }

    /// How much a full turn of a knob changes (for K1–K3).
    var fullTurn: Double {
        switch self {
        case .timingOffset: 2 * TimingConfiguration.offsetRangeMs
        case .hitWindow, .earlyWindow: 200
        case .metronome, .missSound, .stem, .highway: 1
        case .strikeLine: Double(StrikeLinePosition.allCases.count - 1)
        }
    }

    func range(in settings: PlayerSettings) -> ClosedRange<Double> {
        switch self {
        case .timingOffset:
            -TimingConfiguration.offsetRangeMs...TimingConfiguration.offsetRangeMs
        case .hitWindow:
            TimingConfiguration.minTotalSec * 1000...TimingConfiguration.maxTotalSec * 1000
        case .earlyWindow:
            0...TimingConfiguration.maxFront(forTotal: settings.hitWindowMs / 1000) * 1000
        case .metronome, .missSound, .stem, .highway:
            0...1
        case .strikeLine:
            0...Double(StrikeLinePosition.allCases.count - 1)
        }
    }

    func value(in settings: PlayerSettings) -> Double {
        switch self {
        case .timingOffset: settings.timingOffsetMs
        case .hitWindow: settings.hitWindowMs
        case .earlyWindow: settings.earlyWindowMs
        case .metronome: settings.metronomeVolume
        case .missSound: settings.missSoundVolume
        case .highway: settings.highwayLayout == .horizontal ? 1 : 0
        case .strikeLine: Double(StrikeLinePosition.allCases.firstIndex(of: settings.strikeLine) ?? 0)
        case let .stem(name): settings.stemVolume(name)
        }
    }

    /// Sets the value, rounded to the step; `PlayerSettings` keeps it in range.
    func set(_ value: Double, in settings: inout PlayerSettings) {
        let rounded = (value / step).rounded() * step
        switch self {
        case .timingOffset: settings.timingOffsetMs = rounded
        case .hitWindow: settings.hitWindowMs = rounded
        case .earlyWindow: settings.earlyWindowMs = rounded
        case .metronome: settings.metronomeVolume = rounded
        case .missSound: settings.missSoundVolume = rounded
        case .highway: settings.highwayLayout = rounded >= 1 ? .horizontal : .vertical
        case .strikeLine:
            let positions = StrikeLinePosition.allCases
            settings.strikeLine = positions[min(max(Int(rounded), 0), positions.count - 1)]
        case let .stem(name): settings.stemVolumes[name] = rounded
        }
    }

    func defaultValue() -> Double {
        value(in: PlayerSettings())
    }

    func text(in settings: PlayerSettings) -> String {
        let value = value(in: settings)
        switch self {
        case .timingOffset: return "\(BeatTrainApp.signed(value)) MS"
        case .hitWindow, .earlyWindow: return "\(Int(value.rounded())) MS"
        case .highway: return settings.highwayLayout == .horizontal ? "HORIZONTAL" : "VERTICAL"
        case .strikeLine:
            switch settings.strikeLine {
            case .edge: return settings.highwayLayout == .horizontal ? "LEFT" : "BOTTOM"
            case .quarter: return "1/4"
            case .third: return "1/3"
            case .middle: return "MIDDLE"
            }
        case .metronome, .missSound, .stem:
            return value == 0 ? "OFF" : "\(Int((value * 100).rounded()))%"
        }
    }
}
