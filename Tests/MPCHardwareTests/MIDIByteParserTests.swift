import Testing
@testable import MPCHardware

struct MIDIByteParserTests {
    @Test func parsesMessagesSplitAcrossReads() {
        var parser = MIDIByteParser()
        #expect(parser.feed([0x99, 0x25]).isEmpty)
        #expect(parser.feed([0x64]) == [.channel(status: 0x99, data1: 0x25, data2: 0x64)])
    }

    @Test func appliesRunningStatus() {
        var parser = MIDIByteParser()
        let messages = parser.feed([0x90, 0x3C, 0x64, 0x40, 0x00])
        #expect(messages == [
            .channel(status: 0x90, data1: 0x3C, data2: 0x64),
            .channel(status: 0x90, data1: 0x40, data2: 0x00),
        ])
    }

    @Test func passesRealtimeBytesThroughWithoutBreakingAMessage() {
        var parser = MIDIByteParser()
        let messages = parser.feed([0xB0, 0x10, 0xF8, 0x40])
        #expect(messages == [.realtime(0xF8), .channel(status: 0xB0, data1: 0x10, data2: 0x40)])
    }

    @Test func collectsSysex() {
        var parser = MIDIByteParser()
        let messages = parser.feed([0xF0, 0x47, 0x7F, 0x5C, 0x42, 0x00, 0x00, 0xF7, 0x80, 0x51, 0x00])
        #expect(messages == [
            .sysex([0xF0, 0x47, 0x7F, 0x5C, 0x42, 0x00, 0x00, 0xF7]),
            .channel(status: 0x80, data1: 0x51, data2: 0x00),
        ])
    }

    @Test func ignoresDataBytesWithoutStatus() {
        var parser = MIDIByteParser()
        #expect(parser.feed([0x10, 0x20, 0x30]).isEmpty)
    }
}
