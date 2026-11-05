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
}
