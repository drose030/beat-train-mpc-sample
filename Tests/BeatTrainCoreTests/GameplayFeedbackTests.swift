import Testing
@testable import BeatTrainCore

struct GameplayFeedbackTests {

    @Test func hitUnmutesDrumsAndFlashesGreen() {
        let feedback = GameplayFeedbackDirector.feedback(for: .hit(noteIndex: 3), target: DrumTarget(lane: 2, row: .top))
        #expect(feedback == [.flashTarget(DrumTarget(lane: 2, row: .top), isHit: true), .setDrumsMuted(false)])
    }

    @Test func overhitMutesDrumsPlaysSFXAndFlashesRed() {
        let feedback = GameplayFeedbackDirector.feedback(for: .overhit, target: DrumTarget(lane: 1, row: .bottom))
        #expect(feedback == [.flashTarget(DrumTarget(lane: 1, row: .bottom), isHit: false), .setDrumsMuted(true), .playMissSFX])
    }

    @Test func autoMissesFlashEachTargetThenMuteAndSFX() {
        let feedback = GameplayFeedbackDirector.feedbackForAutoMisses(targets: [DrumTarget(lane: 0, row: .bottom), DrumTarget(lane: 3, row: .top)])
        #expect(feedback == [
            .flashTarget(DrumTarget(lane: 0, row: .bottom), isHit: false),
            .flashTarget(DrumTarget(lane: 3, row: .top), isHit: false),
            .setDrumsMuted(true),
            .playMissSFX,
        ])
    }

    @Test func noAutoMissesProducesNoFeedback() {
        #expect(GameplayFeedbackDirector.feedbackForAutoMisses(targets: []).isEmpty)
    }
}
