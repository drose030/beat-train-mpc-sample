import CMPCHardware

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

public enum HardwareError: Error, CustomStringConvertible {
    case notFound(String)
    case system(String, errno: Int32)
    case display(String)

    public var description: String {
        switch self {
        case let .notFound(what): "not found: \(what)"
        case let .system(what, code): "\(what): \(String(cString: strerror(code)))"
        case let .display(message): "display: \(message)"
        }
    }
}

/// The MPC Sample's pads, buttons and knobs: an ALSA rawmidi device on the panel
/// UART, named "Control Surface". Only one process can own it, so the stock app
/// must be stopped first.
public final class ControlSurface {
    /// Rawmidi names the stock app looks for, in order.
    public static let deviceNames = ["Control Surface", "MIDI UART", "SerialMIDI"]

    public let devicePath: String
    private let fd: Int32
    private var parser = MIDIByteParser()
    /// Called with every chunk of raw bytes read from the panel, for debugging.
    public var trace: (([UInt8]) -> Void)?

    public init(devicePath: String) throws {
        let fd = open(devicePath, O_RDWR | O_NONBLOCK)
        guard fd >= 0 else { throw HardwareError.system("open \(devicePath)", errno: errno) }
        let rc = cmpc_rawmidi_set_byte_mode(fd)
        if rc < 0 {
            close(fd)
            throw HardwareError.system("byte mode \(devicePath)", errno: -rc)
        }
        self.devicePath = devicePath
        self.fd = fd
    }

    /// Finds the control surface by name in `/proc/asound` and opens it.
    public convenience init() throws {
        guard let path = Self.findDevice() else {
            throw HardwareError.notFound("rawmidi \(Self.deviceNames.joined(separator: " / "))")
        }
        try self.init(devicePath: path)
    }

    deinit {
        close(fd)
    }

    /// `/proc/asound/cardN/midiM` starts with the rawmidi name; the device node is
    /// `/dev/snd/midiCNDM`.
    public static func findDevice(procRoot: String = "/proc/asound") -> String? {
        var candidates: [(name: String, path: String)] = []
        for card in 0..<8 {
            for device in 0..<4 {
                let info = "\(procRoot)/card\(card)/midi\(device)"
                guard let text = readTextFile(info) else { continue }
                let name = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
                candidates.append((name.trimmingCharacters(), "/dev/snd/midiC\(card)D\(device)"))
            }
        }
        for wanted in deviceNames {
            if let hit = candidates.first(where: { $0.name == wanted }) { return hit.path }
        }
        return nil
    }

    /// Sends the start-up request so the panel reports its knob positions.
    public func sendInit() throws {
        try send(ControlSurfaceProtocol.initRequest)
    }

    public func send(_ bytes: [UInt8]) throws {
        var offset = 0
        while offset < bytes.count {
            let written = bytes[offset...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            if written < 0 {
                if errno == EINTR { continue }
                if errno == EAGAIN {
                    usleep(1000)
                    continue
                }
                throw HardwareError.system("write \(devicePath)", errno: errno)
            }
            offset += written
        }
    }

    /// Waits up to `timeoutMs` for input and returns all events read so far.
    public func poll(timeoutMs: Int32) throws -> [ControlEvent] {
        var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let ready = withUnsafeMutablePointer(to: &pfd) { Glue.poll($0, 1, timeoutMs) }
        if ready < 0 {
            if errno == EINTR { return [] }
            throw HardwareError.system("poll \(devicePath)", errno: errno)
        }
        var events: [ControlEvent] = []
        var buffer = [UInt8](repeating: 0, count: 256)
        while true {
            let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if count > 0 {
                trace?(Array(buffer[0..<count]))
                for message in parser.feed(buffer[0..<count]) {
                    if let event = ControlSurfaceProtocol.decode(message) { events.append(event) }
                }
                continue
            }
            if count < 0 && errno != EAGAIN && errno != EINTR {
                throw HardwareError.system("read \(devicePath)", errno: errno)
            }
            return events
        }
    }
}

/// Disambiguates libc functions shadowed by method names.
enum Glue {
    static func poll(_ fds: UnsafeMutablePointer<pollfd>, _ count: Int, _ timeout: Int32) -> Int32 {
        #if canImport(Darwin)
        Darwin.poll(fds, UInt32(count), timeout)
        #elseif canImport(Musl)
        Musl.poll(fds, nfds_t(count), timeout)
        #else
        Glibc.poll(fds, nfds_t(count), timeout)
        #endif
    }
}

func readTextFile(_ path: String) -> String? {
    guard let file = fopen(path, "r") else { return nil }
    defer { fclose(file) }
    var bytes: [UInt8] = []
    var chunk = [UInt8](repeating: 0, count: 512)
    while true {
        let count = fread(&chunk, 1, chunk.count, file)
        if count <= 0 { break }
        bytes.append(contentsOf: chunk[0..<count])
    }
    return String(decoding: bytes, as: UTF8.self)
}

extension String {
    func trimmingCharacters() -> String {
        var scalars = Substring(self)
        while let first = scalars.first, first.isWhitespace { scalars.removeFirst() }
        while let last = scalars.last, last.isWhitespace { scalars.removeLast() }
        return String(scalars)
    }
}
