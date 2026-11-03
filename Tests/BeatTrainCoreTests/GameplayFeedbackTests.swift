import Testing
@testable import BeatTrainCore

struct GameplayFeedbackTests {

    @Test func hitUnmutesDrumsAndFlashesGreen() {
        let feedback = GameplayFeedbackDirector.feedback(for: .hit(noteIndex: 3), lane: 2)
        #expect(feedback == [.flashLane(lane: 2, isHit: true), .setDrumsMuted(false)])
    }

    @Test func overhitMutesDrumsPlaysSFXAndFlashesRed() {
        let feedback = GameplayFeedbackDirector.feedback(for: .overhit, lane: 1)
        #expect(feedback == [.flashLane(lane: 1, isHit: false), .setDrumsMuted(true), .playMissSFX])
    }

    @Test func autoMissesFlashEachLaneThenMuteAndSFX() {
        let feedback = GameplayFeedbackDirector.feedbackForAutoMisses(lanes: [0, 3])
        #expect(feedback == [
            .flashLane(lane: 0, isHit: false),
            .flashLane(lane: 3, isHit: false),
            .setDrumsMuted(true),
            .playMissSFX,
        ])
    }

    @Test func noAutoMissesProducesNoFeedback() {
        #expect(GameplayFeedbackDirector.feedbackForAutoMisses(lanes: []).isEmpty)
    }
}
