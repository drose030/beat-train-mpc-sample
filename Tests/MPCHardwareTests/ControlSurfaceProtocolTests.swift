import Testing
@testable import MPCHardware

struct ControlSurfaceProtocolTests {
    @Test func decodesPadHitsAndReleasesInPanelNumbering() {
        #expect(ControlSurfaceProtocol.decode(.channel(status: 0x99, data1: 37, data2: 100)) == .padDown(pad: 0, velocity: 100))
        #expect(ControlSurfaceProtocol.decode(.channel(status: 0x99, data1: 53, data2: 1)) == .padDown(pad: 15, velocity: 1))
        #expect(ControlSurfaceProtocol.decode(.channel(status: 0x89, data1: 82, data2: 0)) == .padUp(pad: 3))
        #expect(ControlSurfaceProtocol.decode(.channel(status: 0x99, data1: 42, data2: 0)) == .padUp(pad: 2))
    }

    @Test func padNotesAreUnique() {
        #expect(Set(ControlSurfaceProtocol.padNotes).count == 16)
    }

    @Test func decodesButtons() {
        #expect(ControlSurfaceProtocol.decode(.channel(status: 0x90, data1: 81, data2: 0x7F)) == .button(.stop, pressed: true))
        #expect(ControlSurfaceProtocol.decode(.channel(status: 0x80, data1: 49, data2: 0)) == .button(.shift, pressed: false))
        #expect(ControlSurfaceProtocol.decode(.channel(status: 0x90, data1: 111, data2: 0x7F)) == .button(.dataPush, pressed: true))
        #expect(ControlSurfaceProtocol.decode(.channel(status: 0x90, data1: 120, data2: 0x7F)) == nil)
    }

    @Test func decodesEncoderAsSignedDelta() {
        #expect(ControlSurfaceProtocol.decode(.channel(status: 0xB0, data1: 100, data2: 0x01)) == .encoder(delta: 1))
        #expect(ControlSurfaceProtocol.decode(.channel(status: 0xB0, data1: 100, data2: 0x7F)) == .encoder(delta: -1))
    }

    @Test func decodesAbsoluteControls() {
        #expect(ControlSurfaceProtocol.decode(.channel(status: 0xB0, data1: 16, data2: 64)) == .control(.k1, value: 64))
        #expect(ControlSurfaceProtocol.decode(.channel(status: 0xB0, data1: 20, data2: 127)) == .control(.fader, value: 127))
    }

    @Test func encodesPadColorAsSevenBitSysex() {
        let frame = ControlSurfaceProtocol.padColor(pad: 3, Color(r: 255, g: 32, b: 0))
        #expect(frame == [0xF0, 0x47, 0x7F, 0x5C, 0x65, 0x00, 0x04, 0x03, 0x7F, 0x10, 0x00, 0xF7])
    }
}
