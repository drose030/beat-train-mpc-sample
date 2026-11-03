#if canImport(FoundationEssentials)
import FoundationEssentials  // no ICU: keeps the static Linux binary small
#else
import Foundation
#endif

/// A single feedback action triggered by gameplay — the bridge between the pure
/// judging logic and the side-effecting view/audio layer.
public enum GameplayFeedback: Equatable, Sendable {
    case flashLane(lane: Int, isHit: Bool)
    case setDrumsMuted(Bool)
    case playMissSFX
}

/// Translates a `Judgement` (or a batch of auto-misses) into the feedback actions
/// that should follow. The gameplay-audio/visual *policy* — "on hit, unmute the
/// drums; on miss, mute them and play the miss cue" — lives here in one pure place.
enum GameplayFeedbackDirector {
    static func feedback(for judgement: HitJudgement, lane: Int) -> [GameplayFeedback] {
        switch judgement {
        case .hit:
            return [.flashLane(lane: lane, isHit: true), .setDrumsMuted(false)]
        case .overhit:
            return [.flashLane(lane: lane, isHit: false), .setDrumsMuted(true), .playMissSFX]
        }
    }

    static func feedbackForAutoMisses(lanes: [Int]) -> [GameplayFeedback] {
        guard !lanes.isEmpty else { return [] }
        return lanes.map { .flashLane(lane: $0, isHit: false) } + [.setDrumsMuted(true), .playMissSFX]
    }
}
