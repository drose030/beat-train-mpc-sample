#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

/// The power key on the rear panel. On the MPC Sample it is the RK817 PMIC's
/// key (`rk805-pwrkey`), in the QEMU lab a gpio-keys device; like the stock app
/// (through libinput) this reads every input device that has KEY_POWER. The stock
/// app asks before it shuts down on a press; holding the key powers off in
/// hardware.
public final class PowerButton {
    public let devicePaths: [String]
    private let fds: [Int32]

    /// Opens every `/dev/input/eventN` whose sysfs key capabilities include KEY_POWER.
    public init(inputRoot: String = "/dev/input", sysRoot: String = "/sys/class/input") throws {
        var paths: [String] = []
        var fds: [Int32] = []
        for name in Self.directoryNames(inputRoot).sorted() where name.hasPrefix("event") {
            guard let caps = readTextFile("\(sysRoot)/\(name)/device/capabilities/key"),
                  Self.hasPowerKey(capabilities: caps)
            else { continue }
            let path = "\(inputRoot)/\(name)"
            let fd = open(path, O_RDONLY | O_NONBLOCK)
            guard fd >= 0 else { continue }
            paths.append(path)
            fds.append(fd)
        }
        guard !fds.isEmpty else { throw HardwareError.notFound("input device with KEY_POWER") }
        devicePaths = paths
        self.fds = fds
    }

    deinit {
        fds.forEach { close($0) }
    }

    /// Whether the key went down since the last call. Never blocks.
    public func pollPressed() -> Bool {
        var pressed = false
        var buffer = [UInt8](repeating: 0, count: Self.eventSize * 16)
        for fd in fds {
            while true {
                let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
                guard count > 0 else { break }
                pressed = Self.containsPress(buffer.prefix(count)) || pressed
            }
        }
        return pressed
    }

    private static func directoryNames(_ path: String) -> [String] {
        guard let dir = opendir(path) else { return [] }
        defer { closedir(dir) }
        var names: [String] = []
        while let entry = readdir(dir) {
            names.append(withUnsafeBytes(of: entry.pointee.d_name) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) })
        }
        return names
    }

    /// Whether a sysfs `capabilities/key` bitmap has KEY_POWER: hex words of the
    /// kernel's `long` (64 bits here), most significant first.
    static func hasPowerKey(capabilities: String) -> Bool {
        let words = capabilities.split(whereSeparator: { $0 == " " || $0 == "\n" }).reversed().map { UInt64($0, radix: 16) ?? 0 }
        let word = Int(keyPower) / 64
        return word < words.count && words[word] & (1 << (UInt64(keyPower) % 64)) != 0
    }

    /// `struct input_event` on 64-bit Linux: a 16-byte timeval, then type (u16),
    /// code (u16) and value (s32), little-endian.
    static let eventSize = 24
    static let evKey: UInt16 = 1
    static let keyPower: UInt16 = 116

    /// Whether `bytes` (whole input events) hold a KEY_POWER press.
    static func containsPress(_ bytes: ArraySlice<UInt8>) -> Bool {
        let bytes = Array(bytes)
        func u16(_ at: Int) -> UInt16 { UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8 }
        return stride(from: 0, to: bytes.count - eventSize + 1, by: eventSize).contains { event in
            u16(event + 16) == evKey && u16(event + 18) == keyPower && bytes[event + 20] == 1
                && bytes[event + 21] == 0 && bytes[event + 22] == 0 && bytes[event + 23] == 0
        }
    }
}
