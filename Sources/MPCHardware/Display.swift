import CMPCHardware

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

/// The MPC Sample screen (320×240) via DRM/KMS. Draw into a `Canvas` of the
/// display's size and `present` it.
public final class Display {
    private let handle: OpaquePointer
    public let width: Int
    public let height: Int

    public init(path: String = "/dev/dri/card0") throws {
        var message = [CChar](repeating: 0, count: 256)
        guard let handle = cmpc_display_open(path, &message, message.count) else {
            throw HardwareError.display(String(decoding: message.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self))
        }
        self.handle = handle
        width = Int(cmpc_display_width(handle))
        height = Int(cmpc_display_height(handle))
    }

    deinit {
        cmpc_display_close(handle)
    }

    public func makeCanvas() -> Canvas {
        Canvas(width: width, height: height)
    }

    /// The order in which a frame goes out to the panel. Only what changed goes
    /// out, in strips (see `cmpc_display_present_strips`).
    public enum Sweep: Sendable {
        /// Strips top to bottom: for screens that move up and down.
        case rows
        /// Strips left to right: for screens that move sideways.
        case columns
    }

    /// Strip size: narrow enough that a note is rarely cut, wide enough that the
    /// per-update overhead stays small.
    public static let stripSize: UInt32 = 16

    /// What `present` sends with `old` on screen to show `new`: the changed part of
    /// each strip, in sending order, as (x, y, width, height).
    public static func changedStrips(from old: Canvas, to new: Canvas, sweep: Sweep) -> [(x: Int, y: Int, width: Int, height: Int)] {
        precondition(old.width == new.width && old.height == new.height, "frames of one size")
        let length = sweep == .columns ? new.width : new.height
        var rects = [cmpc_rect](repeating: cmpc_rect(), count: (length + Int(stripSize) - 1) / Int(stripSize))
        let count = old.pixels.withUnsafeBufferPointer { old in
            new.pixels.withUnsafeBufferPointer { now in
                cmpc_changed_strips(old.baseAddress, now.baseAddress, UInt32(new.width), UInt32(new.height),
                                    stripSize, sweep == .columns ? 1 : 0, &rects, rects.count)
            }
        }
        return rects.prefix(count).map { (Int($0.x0), Int($0.y0), Int($0.x1 - $0.x0), Int($0.y1 - $0.y0)) }
    }

    /// Shows the canvas. Blocks until the frame is on screen (vsync-paced).
    public func present(_ canvas: Canvas, sweep: Sweep = .rows) throws {
        precondition(canvas.width == width && canvas.height == height, "canvas size must match the display")
        let rc = canvas.pixels.withUnsafeBufferPointer { pixels in
            switch sweep {
            case .rows: cmpc_display_present_strips(handle, pixels.baseAddress, Self.stripSize, 0)
            case .columns: cmpc_display_present_strips(handle, pixels.baseAddress, Self.stripSize, 1)
            }
        }
        if rc < 0 && rc != -Int32(ETIMEDOUT) && rc != -Int32(EBUSY) {
            throw HardwareError.system("present", errno: -rc)
        }
    }
}
