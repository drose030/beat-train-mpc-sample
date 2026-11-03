import Testing
@testable import MPCHardware

struct PowerButtonTests {
    /// One `input_event`: zero timestamp, then type, code and value.
    private func event(type: UInt16, code: UInt16, value: Int32) -> [UInt8] {
        [UInt8](repeating: 0, count: 16)
            + [UInt8(type & 0xFF), UInt8(type >> 8), UInt8(code & 0xFF), UInt8(code >> 8)]
            + withUnsafeBytes(of: value.littleEndian, Array.init)
    }

    @Test func aKeyDownIsAPress() {
        let bytes = event(type: 1, code: 116, value: 1) + event(type: 0, code: 0, value: 0)
        #expect(PowerButton.containsPress(bytes[...]))
    }

    @Test func releaseRepeatAndOtherKeysAreNot() {
        let release = event(type: 1, code: 116, value: 0)
        let autoRepeat = event(type: 1, code: 116, value: 2)
        let otherKey = event(type: 1, code: 115, value: 1)
        let sync = event(type: 0, code: 0, value: 0)
        #expect(!PowerButton.containsPress((release + autoRepeat + otherKey + sync)[...]))
    }

    @Test func aPressAfterOtherEventsCounts() {
        let bytes = event(type: 0, code: 0, value: 0) + event(type: 1, code: 116, value: 0) + event(type: 1, code: 116, value: 1)
        #expect(PowerButton.containsPress(bytes[...]))
    }

    @Test func powerKeyCapabilityIsBit116() {
        // rk805-pwrkey: only KEY_POWER (bit 116 = word 1, bit 52).
        #expect(PowerButton.hasPowerKey(capabilities: "10000000000000 0\n"))
        // A keyboard-like map whose second word lacks bit 52.
        #expect(!PowerButton.hasPowerKey(capabilities: "fffffffffffff 0\n"))
        #expect(!PowerButton.hasPowerKey(capabilities: "0\n"))
        // Three words: KEY_POWER still counts from the least significant end.
        #expect(PowerButton.hasPowerKey(capabilities: "1 10000000000000 0\n"))
    }
}
