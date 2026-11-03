import BeatTrainCore
import MPCHardware

/// The MPC's 16 panel pads as Beat-Train sees them: which **Pad** each plays, the
/// number printed on the panel for a Pad, and their lights. The one owner of the
/// row swap and of panel pads 9–16 being unused.
///
/// Panel pads 1–4 (the bottom row) play Beat-Train's top row (snare, hi-hat, tom,
/// cymbal), panel pads 5–8 its bottom row (kick, –, –, floor tom): swapped against
/// the original Beat-Train layout, so the snare sits nearest the player.
enum PanelPads {
    static let count = 16

    /// The Beat-Train row on the upper of the two panel rows.
    static let rowOnTop: DrumPadRow = .bottom

    /// The Pad (0–7) a panel pad (0–15) plays; nil for panel pads 9–16.
    static func pad(forPanelPad panelPad: Int) -> Int? {
        switch panelPad {
        case 0..<4: panelPad + 4
        case 4..<8: panelPad - 4
        default: nil
        }
    }

    /// The panel pad that plays a Pad; inverse of `pad(forPanelPad:)`.
    static func panelPad(forPad pad: Int) -> Int {
        pad < 4 ? pad + 4 : pad - 4
    }

    /// "PAD 5" for the kick: the pad's number as printed on the panel.
    static func label(forPad pad: Int) -> String {
        "PAD \(panelPad(forPad: pad) + 1)"
    }

    /// The Pads as they sit on the panel, upper row first, left to right.
    static let rows: [[Int]] = [4, 0].map { first in (first..<first + 4).compactMap(pad(forPanelPad:)) }

    /// The 16 panel colours for the 8 Pads' colours; panel pads 9–16 stay dark.
    static func colors(forPads padColors: [Color]) -> [Color] {
        (0..<count).map { panelPad in pad(forPanelPad: panelPad).map { padColors[$0] } ?? .black }
    }
}

/// The panel's pad lights as sent: only changes go out, the panel's UART is slow
/// (31250 baud).
struct PanelLights {
    private var sent = [Color?](repeating: nil, count: PanelPads.count)

    /// The panel pads to set, and their colours, to show the Pads' `padColors`.
    mutating func changes(to padColors: [Color]) -> [(panelPad: Int, color: Color)] {
        let wanted = PanelPads.colors(forPads: padColors)
        let changes = wanted.enumerated().filter { sent[$0.offset] != $0.element }.map { (panelPad: $0.offset, color: $0.element) }
        for change in changes { sent[change.panelPad] = change.color }
        return changes
    }

    /// Every panel pad dark, as the stock app expects to find them.
    mutating func off() -> [(panelPad: Int, color: Color)] {
        sent = Array(repeating: .black, count: PanelPads.count)
        return (0..<PanelPads.count).map { ($0, .black) }
    }
}
