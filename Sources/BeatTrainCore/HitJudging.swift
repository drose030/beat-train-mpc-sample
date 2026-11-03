#if canImport(FoundationEssentials)
import FoundationEssentials  // no ICU: keeps the static Linux binary small
#else
import Foundation
#endif

public enum NoteJudgmentState: String, Hashable, Sendable {
    case pending
    case hit
    case missed
}

/// The verdict for a single player input.
public enum HitJudgement: Equatable, Sendable {
    case hit(noteIndex: Int)
    case overhit
}

/// Pure hit-detection: decides whether an input hits a note (and which) or is an
/// overhit, and which pending notes have aged past their window. No state
/// mutation, no audio — the caller applies the verdict.
enum DrumHitJudge {
    /// The nearest pending note in the window at `target`, lane and row: a kick
    /// (lane 0, bottom) is not hit from the snare pad (lane 0, top), nor the other
    /// way round.
    static func judgeInput(target: DrumTarget,
                           atTime inputTime: Double,
                           notes: [DrumNoteEvent],
                           noteStates: [Int: NoteJudgmentState],
                           kit: DrumKit,
                           timing: TimingConfiguration) -> HitJudgement {
        var bestIndex: Int?
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, note) in notes.enumerated() {
            guard kit.target(remapping: note.target) == target else { continue }
            guard (noteStates[index] ?? .pending) == .pending else { continue }

            let delta = note.timeSec - inputTime
            guard delta >= -timing.hitWindowBackSec, delta <= timing.hitWindowFrontSec else { continue }

            let distance = abs(delta)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        if let bestIndex { return .hit(noteIndex: bestIndex) }
        return .overhit
    }

    /// Indices of pending notes whose back window has elapsed at `now`.
    static func autoMissedNoteIndices(now: Double,
                                      notes: [DrumNoteEvent],
                                      noteStates: [Int: NoteJudgmentState],
                                      timing: TimingConfiguration) -> [Int] {
        var missed: [Int] = []
        for (index, note) in notes.enumerated() {
            guard (noteStates[index] ?? .pending) == .pending else { continue }
            if now - note.timeSec > timing.hitWindowBackSec {
                missed.append(index)
            }
        }
        return missed
    }
}

public struct ScoreState: Equatable, Sendable {
    public private(set) var hits = 0
    public private(set) var misses = 0
    public private(set) var overhits = 0
    public private(set) var streak = 0
    public private(set) var maxStreak = 0

    public init() {}

    mutating func registerHit() {
        hits += 1
        streak += 1
        maxStreak = max(maxStreak, streak)
    }

    /// An input that matched no note: counts as both an overhit and a miss, and
    /// breaks the streak.
    mutating func registerOverhit() {
        overhits += 1
        misses += 1
        streak = 0
    }

    /// Notes that aged out unplayed.
    mutating func registerMisses(_ count: Int) {
        guard count > 0 else { return }
        misses += count
        streak = 0
    }
}
