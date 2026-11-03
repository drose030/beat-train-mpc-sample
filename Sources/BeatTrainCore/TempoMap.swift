#if canImport(FoundationEssentials)
import FoundationEssentials  // no ICU: keeps the static Linux binary small
#else
import Foundation
#endif

/// Owns the tick↔seconds conversion for a chart.
///
/// Built from a resolution (`ppq`) plus the chart's tempo changes as `(tick, bpm)`
/// pairs in any order. The per-segment wall-clock timeline is computed once at
/// construction; lookups are then pure reads.
///
/// A chart with **zero** tempo changes has no tick→seconds basis and is unplayable —
/// construction throws `.noTempo` so callers can surface that to the user rather than
/// silently assuming a tempo. A chart whose first change merely isn't at tick 0 is
/// fine: the leading segment is backfilled with the first known BPM.
public struct TempoMap: Equatable, Sendable {
    public let ppq: Int

    /// A constant-tempo span starting at `tick` / `timeSec`, running at `bpm` until
    /// the next segment.
    struct Segment: Equatable {
        let tick: Int
        let timeSec: Double
        let bpm: Double
    }

    private let segments: [Segment]

    enum Failure: Error, LocalizedError {
        case invalidResolution
        case noTempo

        var errorDescription: String? {
            switch self {
            case .invalidResolution:
                return "Chart has an invalid tick resolution."
            case .noTempo:
                return "Chart has no tempo information and cannot be timed."
            }
        }
    }

    init(ppq: Int, changes: [(tick: Int, bpm: Double)]) throws {
        guard ppq > 0 else { throw Failure.invalidResolution }
        guard !changes.isEmpty else { throw Failure.noTempo }

        var ordered = changes.sorted { $0.tick < $1.tick }
        // Tempo data exists but not at tick 0 — backfill the leading span
        // with the first known BPM (a better guess than a fixed default).
        if ordered[0].tick != 0 {
            ordered.insert((tick: 0, bpm: ordered[0].bpm), at: 0)
        }

        var built: [Segment] = []
        var previousTick = ordered[0].tick
        var currentBPM = max(1.0, ordered[0].bpm)
        var elapsed = 0.0
        built.append(Segment(tick: previousTick, timeSec: 0, bpm: currentBPM))

        for change in ordered.dropFirst() {
            let deltaTicks = max(0, change.tick - previousTick)
            elapsed += Double(deltaTicks) / Double(ppq) * (60.0 / currentBPM)
            previousTick = change.tick
            currentBPM = max(1.0, change.bpm)
            built.append(Segment(tick: previousTick, timeSec: elapsed, bpm: currentBPM))
        }

        self.ppq = ppq
        self.segments = built
    }

    /// Wall-clock seconds at `tick`. `segments` is guaranteed non-empty with a
    /// tick-0 entry, so this always resolves.
    public func seconds(forTick tick: Int) -> Double {
        var active = segments[0]
        for segment in segments {
            if segment.tick <= tick {
                active = segment
            } else {
                break
            }
        }
        let deltaTicks = max(0, tick - active.tick)
        return active.timeSec + Double(deltaTicks) / Double(ppq) * (60.0 / active.bpm)
    }

    /// Quarter-note beat times (seconds) from tick 0 through `maxTick`. Used by the
    /// note-highway grid. Returns an empty array when `maxTick <= 0`.
    public func beatTimes(throughTick maxTick: Int) -> [Double] {
        guard maxTick > 0 else { return [] }
        var times: [Double] = []
        var tick = 0
        while tick <= maxTick {
            times.append(seconds(forTick: tick))
            tick += ppq
        }
        return times
    }

    var tempoEvents: [TempoEvent] {
        segments.map { TempoEvent(tick: $0.tick, bpm: $0.bpm, timeSec: $0.timeSec) }
    }
}
