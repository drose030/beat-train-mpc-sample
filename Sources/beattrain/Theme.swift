import BeatTrainCore
import MPCHardware

enum Theme {
    static let background = Color(rgb: 0x0B0E14)
    static let panel = Color(rgb: 0x1A1F2B)
    static let highway = Color(rgb: 0x10141D)
    static let laneLine = Color(rgb: 0x232A38)
    static let beatLine = Color(rgb: 0x262E3E)
    static let text = Color(rgb: 0xE6E9F0)
    static let dim = Color(rgb: 0x7A8194)
    static let accent = Color(rgb: 0xFF8A1F)
    static let hit = Color(rgb: 0x3DDC84)
    static let miss = Color(rgb: 0xFF4D4D)
    static let selection = Color(rgb: 0x26314A)
}

extension DrumVoice {
    /// The highway and pad colour of this voice (the original game's palette).
    var color: Color {
        switch self {
        case .off: Color(rgb: 0x555B66)
        case .kick: Color(rgb: 0x9B5DE5)
        case .red: Color(rgb: 0xF0433A)
        case .yellow: Color(rgb: 0xF9C80E)
        case .blue: Color(rgb: 0x3A86FF)
        case .orange: Color(rgb: 0xFF8A1F)
        case .green: Color(rgb: 0x2DC653)
        }
    }

    /// Short name for the display.
    var label: String {
        switch self {
        case .off: "OFF"
        case .kick: "KICK"
        case .red: "SNARE"
        case .yellow: "HI-HAT"
        case .blue: "TOM"
        case .orange: "CYMBAL"
        case .green: "FLOOR TOM"
        }
    }

    /// Three or four letters, for the rows of the horizontal highway.
    var tag: String {
        switch self {
        case .off: ""
        case .kick: "KICK"
        case .red: "SNR"
        case .yellow: "HAT"
        case .blue: "TOM"
        case .orange: "CYM"
        case .green: "FLR"
        }
    }
}

/// Cuts `text` to at most `count` characters, marking the cut with "~".
func fit(_ text: String, _ count: Int) -> String {
    text.count <= count ? text : String(text.prefix(max(0, count - 1))) + "~"
}
