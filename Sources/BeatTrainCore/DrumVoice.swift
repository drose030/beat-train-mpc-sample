#if canImport(FoundationEssentials)
import FoundationEssentials  // no ICU: keeps the static Linux binary small
#else
import Foundation
#endif

/// The drum a pad represents: the 6-colour standard plus kick, plus `off`
/// (unassigned). Shared by gameplay and pad setup; persisted by its `rawValue`.
public enum DrumVoice: String, CaseIterable, Codable, Hashable, Sendable {
    case off
    case kick
    case red
    case yellow
    case blue
    case orange
    case green

    /// The canonical highway position of this voice — where it sits when the pad
    /// layout is left at its defaults. `nil` for `.off`.
    public var canonicalTarget: DrumTarget? {
        switch self {
        case .off: return nil
        case .kick: return DrumTarget(lane: 0, row: .bottom)
        case .red: return DrumTarget(lane: 0, row: .top)
        case .yellow: return DrumTarget(lane: 1, row: .top)
        case .blue: return DrumTarget(lane: 2, row: .top)
        case .orange: return DrumTarget(lane: 3, row: .top)
        case .green: return DrumTarget(lane: 3, row: .bottom)
        }
    }

    /// The voice naturally occupying a canonical target — the inverse of
    /// `canonicalTarget`, derived from it so the bijection has a single source.
    public init?(canonicalTarget target: DrumTarget) {
        guard let match = DrumVoice.allCases.first(where: { $0.canonicalTarget == target }) else {
            return nil
        }
        self = match
    }

    // MARK: - Display labels (used by pad setup UI)

    // Foundation on Linux has no String(localized:); the MPC app does not use these.
    #if canImport(Darwin)
    var instrument: String {
        switch self {
        case .off: return String(localized: "Unused")
        case .kick: return String(localized: "Bass drum")
        case .red: return String(localized: "Snare")
        case .yellow: return String(localized: "Hi-hat/tom")
        case .blue: return String(localized: "Tom/cymbal")
        case .orange: return String(localized: "Cymbal")
        case .green: return String(localized: "Floor tom")
        }
    }

    /// Short label for compact pad cells, so longer names don't shrink the font
    /// inconsistently across the grid.
    var shortInstrument: String {
        switch self {
        case .off: return String(localized: "Unused")
        case .kick: return String(localized: "Bass drum")
        case .red: return String(localized: "Snare")
        case .yellow: return String(localized: "Hi-hat")
        case .blue: return String(localized: "Tom")
        case .orange: return String(localized: "Cymbal")
        case .green: return String(localized: "Floor tom")
        }
    }

    var colorName: String {
        switch self {
        case .off: return ""
        case .kick: return String(localized: "purple")
        case .red: return String(localized: "red")
        case .yellow: return String(localized: "yellow")
        case .blue: return String(localized: "blue")
        case .orange: return String(localized: "orange")
        case .green: return String(localized: "green")
        }
    }

    var displayName: String {
        colorName.isEmpty ? instrument : "\(instrument) (\(colorName))"
    }
    #endif
}
