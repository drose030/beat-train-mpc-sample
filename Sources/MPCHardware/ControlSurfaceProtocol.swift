/// A button on the MPC Sample top panel. Raw values are the note numbers the
/// panel MCU sends (`90 id 7F` press, `80 id 00` release) and, where the button
/// has one, the CC number of its LED.
public enum PanelButton: UInt8, CaseIterable, Sendable {
    case knobFX = 0
    case padFX = 1
    case sample = 6
    case seq = 7
    case erase = 9
    case noteRepeat = 11
    case screen1 = 12
    case screen2 = 13
    case screen3 = 14
    case padBank = 35
    case sampleSelect = 36
    case sixteenLevels = 40
    case mute = 43
    case shift = 49
    case tapTempo = 53
    case plus = 54
    case minus = 55
    case sampleRecord = 73
    case loop = 74
    case chop = 75
    case seqRecord = 80
    case stop = 81
    case play = 82
    case dataPush = 111

    public var name: String {
        switch self {
        case .knobFX: "KNOB FX"
        case .padFX: "PAD FX"
        case .sample: "SAMPLE"
        case .seq: "SEQ"
        case .erase: "ERASE"
        case .noteRepeat: "NOTE REPEAT"
        case .screen1: "B1"
        case .screen2: "B2"
        case .screen3: "B3"
        case .padBank: "PAD BANK"
        case .sampleSelect: "SAMPLE SELECT"
        case .sixteenLevels: "16 LEVELS"
        case .mute: "MUTE"
        case .shift: "SHIFT"
        case .tapTempo: "TAP TEMPO"
        case .plus: "+"
        case .minus: "-"
        case .sampleRecord: "SAMPLE REC"
        case .loop: "LOOP"
        case .chop: "CHOP"
        case .seqRecord: "SEQ REC"
        case .stop: "STOP"
        case .play: "PLAY"
        case .dataPush: "ENCODER PUSH"
        }
    }
}

/// An absolute 7-bit control on the panel (`B0 cc value`).
public enum PanelControl: UInt8, CaseIterable, Sendable {
    case k1 = 16
    case k2 = 17
    case k3 = 18
    case mainVolume = 19
    case fader = 20

    public var name: String {
        switch self {
        case .k1: "K1"
        case .k2: "K2"
        case .k3: "K3"
        case .mainVolume: "VOLUME"
        case .fader: "FADER"
        }
    }
}

/// Input from the MPC Sample control surface, decoded from its MIDI frames.
public enum ControlEvent: Equatable, Sendable {
    /// `pad` is 0–15 in the panel's numbering (pad 1 = bottom left, pad 16 = top right).
    case padDown(pad: Int, velocity: UInt8)
    case padUp(pad: Int)
    case padPressure(pad: Int, pressure: UInt8)
    case button(PanelButton, pressed: Bool)
    /// Data encoder turn; +1 clockwise, −1 counter-clockwise per detent.
    case encoder(delta: Int)
    case control(PanelControl, value: UInt8)
}

/// The MPC Sample panel protocol: pure translation between `MIDIMessage`s and
/// `ControlEvent`s, plus the frames the app sends to the panel.
/// Source: the community-documented protocol, verified on hardware 2026-10-22
/// (see virtual-mpc-sample `panel/controls.json`).
public enum ControlSurfaceProtocol {
    /// Note numbers of pads 1–16 (`99 note vel` hit, `89 note 00` release).
    public static let padNotes: [UInt8] = [37, 36, 42, 82, 40, 38, 46, 44, 48, 47, 45, 43, 49, 55, 51, 53]

    private static let padByNote: [UInt8: Int] = Dictionary(
        uniqueKeysWithValues: padNotes.enumerated().map { ($0.element, $0.offset) }
    )

    static let encoderCC: UInt8 = 100

    /// Sent once at start; the panel answers with the current K1–K3/volume/fader values.
    public static let initRequest: [UInt8] = [0xF0, 0x47, 0x7F, 0x5C, 0x42, 0x00, 0x00, 0xF7]

    public static func decode(_ message: MIDIMessage) -> ControlEvent? {
        guard case let .channel(status, data1, data2) = message else { return nil }
        switch status {
        case 0x99:
            guard let pad = padByNote[data1] else { return nil }
            return data2 == 0 ? .padUp(pad: pad) : .padDown(pad: pad, velocity: data2)
        case 0x89:
            guard let pad = padByNote[data1] else { return nil }
            return .padUp(pad: pad)
        case 0xA9:
            guard let pad = padByNote[data1] else { return nil }
            return .padPressure(pad: pad, pressure: data2)
        case 0x90:
            guard let button = PanelButton(rawValue: data1) else { return nil }
            return .button(button, pressed: data2 != 0)
        case 0x80:
            guard let button = PanelButton(rawValue: data1) else { return nil }
            return .button(button, pressed: false)
        case 0xB0:
            if data1 == encoderCC {
                return .encoder(delta: data2 < 64 ? Int(data2) : Int(data2) - 128)
            }
            guard let control = PanelControl(rawValue: data1) else { return nil }
            return .control(control, value: data2)
        default:
            return nil
        }
    }

    /// Sets a pad's RGB colour; components are clamped to 7 bits.
    public static func padColor(pad: Int, _ color: Color) -> [UInt8] {
        [0xF0, 0x47, 0x7F, 0x5C, 0x65, 0x00, 0x04, UInt8(pad & 0x7F),
         color.r >> 1, color.g >> 1, color.b >> 1, 0xF7]
    }

    /// Button LED: 0 off, 1 dim, 2+ bright (single-colour LEDs).
    public static func buttonLED(_ button: PanelButton, state: UInt8) -> [UInt8] {
        [0xB0, button.rawValue, state & 0x7F]
    }
}
