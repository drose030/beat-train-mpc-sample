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

    /// Shows the canvas. Blocks until the frame is on screen (vsync-paced).
    public func present(_ canvas: Canvas) throws {
        precondition(canvas.width == width && canvas.height == height, "canvas size must match the display")
        let rc = canvas.pixels.withUnsafeBufferPointer { cmpc_display_present(handle, $0.baseAddress) }
        if rc < 0 && rc != -Int32(ETIMEDOUT) && rc != -Int32(EBUSY) {
            throw HardwareError.system("present", errno: -rc)
        }
    }
}
