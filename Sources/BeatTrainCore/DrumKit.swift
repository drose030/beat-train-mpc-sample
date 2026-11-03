#if canImport(FoundationEssentials)
import FoundationEssentials  // no ICU: keeps the static Linux binary small
#else
import Foundation
#endif

/// The single source of truth for kit geometry and the player's mapping
/// configuration.
///
/// It composes three relationships into one navigable chain
/// `Note → Pad → DrumVoice → DrumTarget → Lane`:
///
/// - **Pad layout** (fixed): pads 0–3 are the bottom row, 4–7 the top row, of the
///   4 lanes.
/// - **Voice↔target** (fixed): each `DrumVoice`'s canonical highway position.
/// - **Player config** (two maps): Pad→`DrumVoice` (which voice each pad plays)
///   and Note→Pad (which pad a MIDI note fires).
///
/// Pure value type: loading/saving the two config maps is the caller's job.
public struct DrumKit: Equatable, Sendable {
    /// Which voice each pad plays. Empty falls back to `defaultPadVoices`.
    public let padVoices: [Int: DrumVoice]
    /// Which pad a MIDI note fires. Empty falls back to `PadMapper.defaultNoteToPad`.
    public let noteToPad: [UInt8: Int]

    public static let padCount = 8

    public static let defaultPadVoices: [Int: DrumVoice] = [
        4: .red, 5: .yellow, 6: .blue, 7: .orange,
        0: .kick, 1: .off, 2: .off, 3: .green,
    ]

    public init(padVoices: [Int: DrumVoice] = DrumKit.defaultPadVoices,
         noteToPad: [UInt8: Int] = PadMapper.defaultNoteToPad) {
        self.padVoices = padVoices.isEmpty ? DrumKit.defaultPadVoices : padVoices
        self.noteToPad = noteToPad.isEmpty ? PadMapper.defaultNoteToPad : noteToPad
    }

    // MARK: - Fixed pad layout

    /// The layout slot of a pad: lane `pad % 4`, bottom row for 0–3, top row for 4–7.
    public static func layoutTarget(forPad pad: Int) -> DrumTarget {
        DrumTarget(lane: max(0, min(3, pad % 4)), row: pad < 4 ? .bottom : .top)
    }

    /// The pad occupying a layout slot — inverse of `layoutTarget(forPad:)`.
    public static func pad(forLayout target: DrumTarget) -> Int {
        target.row == .bottom ? target.lane : target.lane + 4
    }

    // MARK: - Voice queries

    public func voice(forPad pad: Int) -> DrumVoice {
        padVoices[pad] ?? .off
    }

    /// The lowest-numbered pad assigned this voice, if any. (Not the dictionary's
    /// first match: its order changes from run to run.)
    func pad(forVoice voice: DrumVoice) -> Int? {
        padVoices.filter { $0.value == voice }.map(\.key).min()
    }

    func voice(forNote note: UInt8) -> DrumVoice? {
        guard let pad = noteToPad[note] else { return nil }
        return voice(forPad: pad)
    }

    func pad(forNote note: UInt8) -> Int? {
        noteToPad[note]
    }

    // MARK: - Target / lane resolution

    /// Where a voice's notes land: the layout slot of the pad currently holding it
    /// (so reassigning pads moves the voice), falling back to its canonical position.
    func target(forVoice voice: DrumVoice) -> DrumTarget {
        if let pad = pad(forVoice: voice) {
            return DrumKit.layoutTarget(forPad: pad)
        }
        return voice.canonicalTarget ?? DrumTarget(lane: 0, row: .bottom)
    }

    /// The slot (lane and row) a pad's hits register on. `nil` when the pad is
    /// explicitly `.off`.
    public func target(forPad pad: Int) -> DrumTarget? {
        guard let voice = padVoices[pad] else {
            return DrumKit.layoutTarget(forPad: pad)
        }
        if voice == .off { return nil }
        return target(forVoice: voice)
    }

    /// The lane a pad's hits register on. `nil` when the pad is explicitly `.off`.
    public func lane(forPad pad: Int) -> Int? {
        target(forPad: pad)?.lane
    }

    /// The lane a MIDI note registers on, via the Note→Pad→voice chain, with a
    /// General-MIDI percussion fallback for notes outside the configured mapping.
    func lane(forNote note: UInt8) -> Int? {
        if let pad = noteToPad[note] {
            return lane(forPad: pad)
        }
        return DrumKit.generalMidiFallbackLane(note)
    }

    /// Remaps a chart note's canonical target through the player's pad assignment,
    /// so chart notes and input land on the same lane. Untouched when the canonical
    /// voice isn't assigned to a pad.
    public func target(remapping canonical: DrumTarget) -> DrumTarget {
        guard let voice = DrumVoice(canonicalTarget: canonical),
              pad(forVoice: voice) != nil else {
            return canonical
        }
        return target(forVoice: voice)
    }

    private static func generalMidiFallbackLane(_ note: UInt8) -> Int? {
        switch note {
        case 35, 36: return 0
        case 37, 38, 39, 40: return 1
        case 41, 42, 44, 45, 46: return 2
        case 47, 48, 49, 50: return 3
        default: return nil
        }
    }
}
