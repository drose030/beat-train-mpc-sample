/// One complete MIDI message as read off a rawmidi byte stream.
public enum MIDIMessage: Equatable, Sendable {
    /// A channel message: status byte (with channel) and its one or two data bytes.
    case channel(status: UInt8, data1: UInt8, data2: UInt8)
    /// A System Exclusive message including the leading F0 and trailing F7.
    case sysex([UInt8])
    /// A single-byte system real-time message (clock, start, stop…).
    case realtime(UInt8)
}

/// Turns a raw MIDI byte stream into messages. Handles messages split across
/// reads, running status, SysEx and real-time bytes interleaved anywhere.
public struct MIDIByteParser: Sendable {
    private var status: UInt8?
    private var data: [UInt8] = []
    private var sysex: [UInt8]?

    public init() {}

    public mutating func feed<S: Sequence>(_ bytes: S) -> [MIDIMessage] where S.Element == UInt8 {
        var out: [MIDIMessage] = []
        for byte in bytes {
            if byte >= 0xF8 {
                out.append(.realtime(byte))
                continue
            }
            if byte == 0xF0 {
                sysex = [byte]
                status = nil
                continue
            }
            if byte == 0xF7 {
                if var message = sysex {
                    message.append(byte)
                    out.append(.sysex(message))
                }
                sysex = nil
                continue
            }
            if byte & 0x80 != 0 {
                // Any other status byte ends an unterminated SysEx.
                sysex = nil
                status = byte < 0xF0 ? byte : nil
                data.removeAll(keepingCapacity: true)
                continue
            }
            if sysex != nil {
                sysex!.append(byte)
                continue
            }
            guard let status else { continue }
            data.append(byte)
            if data.count == Self.dataLength(for: status) {
                out.append(.channel(status: status, data1: data[0], data2: data.count > 1 ? data[1] : 0))
                data.removeAll(keepingCapacity: true)
            }
        }
        return out
    }

    private static func dataLength(for status: UInt8) -> Int {
        switch status & 0xF0 {
        case 0xC0, 0xD0: return 1
        default: return 2
        }
    }
}
