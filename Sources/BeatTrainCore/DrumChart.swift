#if canImport(FoundationEssentials)
import FoundationEssentials  // no ICU: keeps the static Linux binary small
#else
import Foundation
#endif

public enum DrumPadRow: String, Codable, CaseIterable, Hashable, Sendable {
    case top
    case bottom
}

public enum DrumDifficulty: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case easy
    case medium
    case hard
    case expert

    public var id: String { rawValue }

    public var midiBaseNote: UInt8 {
        switch self {
        case .easy: return 60
        case .medium: return 72
        case .hard: return 84
        case .expert: return 96
        }
    }
}

public struct DrumTarget: Codable, Hashable, Sendable {
    public let lane: Int   // 0...3
    public let row: DrumPadRow

    public init(lane: Int, row: DrumPadRow) {
        self.lane = lane
        self.row = row
    }
}

public struct TempoEvent: Equatable, Hashable, Sendable {
    public let tick: Int
    public let bpm: Double
    public let timeSec: Double
}

public struct DrumNoteEvent: Equatable, Hashable, Sendable {
    public let tick: Int
    public let timeSec: Double
    public let target: DrumTarget
    public let velocity: UInt8
}

/// A parsed, playable chart for one song at one difficulty: a `TempoMap` (which owns
/// resolution and tick↔seconds conversion) plus the ordered notes.
public struct DrumChart: Equatable, Sendable {
    public let tempoMap: TempoMap
    public let notes: [DrumNoteEvent]

    public var ppq: Int { tempoMap.ppq }
}

extension DrumChart {
    /// Quarter-note beat times (seconds) across the chart, delegated to the
    /// `TempoMap`. Spans tick 0 through the last note's tick; empty when the chart
    /// has no notes.
    public func beatTimesSec() -> [Double] {
        guard let maxTick = notes.map(\.tick).max() else { return [] }
        return tempoMap.beatTimes(throughTick: maxTick)
    }
}
