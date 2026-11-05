#if canImport(FoundationEssentials)
import FoundationEssentials  // no ICU: keeps the static Linux binary small
#else
import Foundation
#endif

/// One play-through of a chart: the note states and the score, advanced by pad
/// strikes and by time. The judging, scoring and feedback rules as one value
/// type the MPC app (or a test) drives.
///
/// Times are chart times in seconds (see `chartTime(audioTime:chartDelayMs:timing:)`).
public struct GameSession: Sendable {
    public let chart: DrumChart
    public let kit: DrumKit
    /// May change mid-song, when the player changes the hit window in a pause.
    public var timing: TimingConfiguration
    public private(set) var score = ScoreState()
    private var noteStates: [Int: NoteJudgmentState]

    /// How long after the last note's window the session counts as finished.
    static let outroSec = 1.5

    public init(chart: DrumChart, kit: DrumKit, timing: TimingConfiguration) {
        self.chart = chart
        self.kit = kit
        self.timing = timing
        noteStates = Dictionary(uniqueKeysWithValues: chart.notes.indices.map { ($0, .pending) })
    }

    /// The chart time for an audio clock reading, as the original game computes it: the
    /// song's chart delay and the player's timing offset shift the chart against
    /// the audio. Never negative.
    public static func chartTime(audioTime: Double, chartDelayMs: Double, timing: TimingConfiguration) -> Double {
        max(0, audioTime - chartDelayMs / 1000 - timing.timingOffsetSec)
    }

    public func state(ofNote index: Int) -> NoteJudgmentState {
        noteStates[index] ?? .pending
    }

    /// The highway slot a chart note is drawn in, after the player's pad assignment.
    public func target(ofNote index: Int) -> DrumTarget {
        kit.target(remapping: chart.notes[index].target)
    }

    /// The note's colour as charted; the player's pad assignment moves where it
    /// lands (`target(ofNote:)`), not its colour.
    public func voice(ofNote index: Int) -> DrumVoice {
        DrumVoice(canonicalTarget: chart.notes[index].target) ?? .off
    }

    /// A strike on Beat-Train pad `pad` (0–7) at chart time `time`. Pads set to
    /// `.off` do nothing.
    public mutating func strike(pad: Int, at time: Double) -> [GameplayFeedback] {
        guard let target = kit.target(forPad: pad) else { return [] }
        let judgement = DrumHitJudge.judgeInput(
            target: target,
            atTime: time,
            notes: chart.notes,
            noteStates: noteStates,
            kit: kit,
            timing: timing
        )
        switch judgement {
        case let .hit(noteIndex):
            noteStates[noteIndex] = .hit
            score.registerHit()
        case .overhit:
            score.registerOverhit()
        }
        return GameplayFeedbackDirector.feedback(for: judgement, lane: target.lane)
    }

    /// Marks the notes whose window has passed at `time` as missed.
    public mutating func advance(to time: Double) -> [GameplayFeedback] {
        let missed = DrumHitJudge.autoMissedNoteIndices(
            now: time,
            notes: chart.notes,
            noteStates: noteStates,
            timing: timing
        )
        guard !missed.isEmpty else { return [] }
        for index in missed {
            noteStates[index] = .missed
        }
        score.registerMisses(missed.count)
        return GameplayFeedbackDirector.feedbackForAutoMisses(lanes: missed.map { target(ofNote: $0).lane })
    }

    /// True once every note is judged and the outro has passed.
    public func isFinished(at time: Double) -> Bool {
        let last = chart.notes.last?.timeSec ?? 0
        return time > last + timing.hitWindowBackSec + Self.outroSec
    }

    /// Share of all the chart's notes that were hit, 0–1 (0 for an empty chart).
    public var accuracy: Double {
        chart.notes.isEmpty ? 0 : Double(score.hits) / Double(chart.notes.count)
    }

    /// Share of the notes judged so far that were hit, 0–1 (0 before any). Unlike
    /// `accuracy` it does not count the notes still to come.
    public var runningAccuracy: Double {
        let judged = noteStates.values.lazy.filter { $0 != .pending }.count
        return judged == 0 ? 0 : Double(score.hits) / Double(judged)
    }
}
