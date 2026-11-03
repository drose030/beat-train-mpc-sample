#if canImport(FoundationEssentials)
import FoundationEssentials  // no ICU: keeps the static Linux binary small
#else
import Foundation
#endif

/// The hit-timing rules, with their invariants enforced in one place.
///
/// Invariants (held at construction):
/// - `hitWindowTotalSec` is clamped to `[minTotalSec, maxTotalSec]`
/// - `hitWindowFrontSec` is clamped to `[0, total - minSegmentSec]`
/// - `hitWindowBackSec` is derived as `total - front` (never below `minSegmentSec`)
/// - `timingOffsetMs` is clamped to `±offsetRangeMs`
///
/// Pure value type — derived from the three stored doubles, so there is no storage
/// migration; the UI writes raw stored values back through the same clamps.
public struct TimingConfiguration: Equatable, Sendable {
    public static let minTotalSec = 0.04
    public static let maxTotalSec = 0.30
    public static let minSegmentSec = 0.01
    public static let offsetRangeMs = 120.0

    public let hitWindowTotalSec: Double
    public let hitWindowFrontSec: Double
    public let timingOffsetMs: Double

    public var hitWindowBackSec: Double {
        max(Self.minSegmentSec, hitWindowTotalSec - hitWindowFrontSec)
    }

    public var timingOffsetSec: Double {
        timingOffsetMs / 1000.0
    }

    public init(totalSec: Double, frontSec: Double, offsetMs: Double) {
        let total = Self.clampTotal(totalSec)
        self.hitWindowTotalSec = total
        self.hitWindowFrontSec = Self.clampFront(frontSec, total: total)
        self.timingOffsetMs = Self.clampOffsetMs(offsetMs)
    }

    public static func clampTotal(_ value: Double) -> Double {
        max(minTotalSec, min(value, maxTotalSec))
    }

    /// The largest front window allowed for a given total (leaves `minSegmentSec`
    /// for the back window).
    public static func maxFront(forTotal total: Double) -> Double {
        max(0, total - minSegmentSec)
    }

    public static func clampFront(_ value: Double, total: Double) -> Double {
        min(max(0, value), maxFront(forTotal: total))
    }

    public static func clampOffsetMs(_ value: Double) -> Double {
        max(-offsetRangeMs, min(value, offsetRangeMs))
    }
}
