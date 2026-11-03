#if canImport(FoundationEssentials)
import FoundationEssentials  // no ICU: keeps the static Linux binary small
#else
import Foundation
#endif

/// The single canonical table mapping a standard drum lane to a `DrumTarget`
/// (lane + row on the 4-lane highway).
///
/// Canonical drum lanes follow the 6-colour standard:
/// `0 = kick, 1 = red, 2 = yellow, 3 = blue, 4 = orange, 5 = green`.
///
/// Each parser translates its own raw note encoding to this canonical index
/// (MIDI subtracts the difficulty's `midiBaseNote`; `.chart` uses the raw note
/// number, plus a `32 → kick` quirk) and then looks up here. This keeps the
/// "which colour lands where" decision in one place.
enum DrumTargetMap {
    static func target(forCanonicalLane lane: Int) -> DrumTarget? {
        switch lane {
        case 0: return DrumTarget(lane: 0, row: .bottom) // kick
        case 1: return DrumTarget(lane: 0, row: .top)    // red
        case 2: return DrumTarget(lane: 1, row: .top)    // yellow
        case 3: return DrumTarget(lane: 2, row: .top)    // blue
        case 4: return DrumTarget(lane: 3, row: .top)    // orange
        case 5: return DrumTarget(lane: 3, row: .bottom) // green
        default: return nil
        }
    }
}
