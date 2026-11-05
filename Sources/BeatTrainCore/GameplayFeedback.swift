#if canImport(FoundationEssentials)
import FoundationEssentials  // no ICU: keeps the static Linux binary small
#else
import Foundation
#endif

/// A single feedback action triggered by gameplay — the bridge between the pure
/// judging logic and the side-effecting view/audio layer.
public enum GameplayFeedback: Equatable, Sendable {
    /// A judgement to show on the highway, at the slot of the note (or of the
    /// struck pad, for an overhit).
    case flashTarget(DrumTarget, isHit: Bool)
    case setDrumsMuted(Bool)
    case playMissSFX
}

/// Translates a `Judgement` (or a batch of auto-misses) into the feedback actions
/// that should follow. The gameplay-audio/visual *policy* — "on hit, unmute the
/// drums; on miss, mute them and play the miss cue" — lives here in one pure place.
enum GameplayFeedbackDirector {
    static func feedback(for judgement: HitJudgement, target: DrumTarget) -> [GameplayFeedback] {
        switch judgement {
        case .hit:
            return [.flashTarget(target, isHit: true), .setDrumsMuted(false)]
        case .overhit:
            return [.flashTarget(target, isHit: false), .setDrumsMuted(true), .playMissSFX]
        }
    }

    static func feedbackForAutoMisses(targets: [DrumTarget]) -> [GameplayFeedback] {
        guard !targets.isEmpty else { return [] }
        return targets.map { .flashTarget($0, isHit: false) } + [.setDrumsMuted(true), .playMissSFX]
    }
}
