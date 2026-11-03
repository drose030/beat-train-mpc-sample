/// An XRGB8888 colour as the display expects it (`0x00RRGGBB`).
public struct Color: Equatable, Sendable {
    public var rgb: UInt32

    public init(rgb: UInt32) {
        self.rgb = rgb & 0x00FF_FFFF
    }

    public init(r: UInt8, g: UInt8, b: UInt8) {
        rgb = UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b)
    }

    public var r: UInt8 { UInt8(truncatingIfNeeded: rgb >> 16) }
    public var g: UInt8 { UInt8(truncatingIfNeeded: rgb >> 8) }
    public var b: UInt8 { UInt8(truncatingIfNeeded: rgb) }

    /// Linear blend towards `other`; `amount` 0 keeps self, 1 gives `other`.
    public func mixed(with other: Color, amount: Double) -> Color {
        let t = min(max(amount, 0), 1)
        func lerp(_ a: UInt8, _ b: UInt8) -> UInt8 {
            UInt8((Double(a) + (Double(b) - Double(a)) * t).rounded())
        }
        return Color(r: lerp(r, other.r), g: lerp(g, other.g), b: lerp(b, other.b))
    }

    public static let black = Color(rgb: 0x000000)
    public static let white = Color(rgb: 0xFFFFFF)
}

/// A software framebuffer. Everything on the MPC screen is drawn here first and
/// then handed to `Display.present`, so drawing is testable off-device.
public struct Canvas: Sendable {
    public let width: Int
    public let height: Int
    public private(set) var pixels: [UInt32]

    public init(width: Int, height: Int, fill: Color = .black) {
        self.width = width
        self.height = height
        pixels = Array(repeating: fill.rgb, count: width * height)
    }

    public func pixel(x: Int, y: Int) -> Color {
        Color(rgb: pixels[y * width + x])
    }

    public mutating func clear(_ color: Color) {
        for i in pixels.indices { pixels[i] = color.rgb }
    }

    /// Clipped to the canvas.
    public mutating func fillRect(x: Int, y: Int, width w: Int, height h: Int, _ color: Color) {
        let x0 = max(x, 0), y0 = max(y, 0)
        let x1 = min(x + w, width), y1 = min(y + h, height)
        guard x0 < x1, y0 < y1 else { return }
        for row in y0..<y1 {
            let base = row * width
            for col in x0..<x1 { pixels[base + col] = color.rgb }
        }
    }

    /// One-pixel outline of the rectangle.
    public mutating func strokeRect(x: Int, y: Int, width w: Int, height h: Int, _ color: Color) {
        fillRect(x: x, y: y, width: w, height: 1, color)
        fillRect(x: x, y: y + h - 1, width: w, height: 1, color)
        fillRect(x: x, y: y, width: 1, height: h, color)
        fillRect(x: x + w - 1, y: y, width: 1, height: h, color)
    }

    /// Draws ASCII text with the 5×7 font; each glyph is 6 × `scale` pixels wide
    /// and 8 × `scale` high including spacing. Returns the x after the last glyph.
    @discardableResult
    public mutating func drawText(_ text: String, x: Int, y: Int, scale: Int = 1, _ color: Color) -> Int {
        var cursor = x
        for scalar in text.unicodeScalars {
            let columns = Font5x7.glyph(for: scalar)
            for (col, bits) in columns.enumerated() {
                for row in 0..<7 where bits & (1 << row) != 0 {
                    fillRect(x: cursor + col * scale, y: y + row * scale, width: scale, height: scale, color)
                }
            }
            cursor += Font5x7.advance * scale
        }
        return cursor
    }

    public static func textWidth(_ text: String, scale: Int = 1) -> Int {
        text.unicodeScalars.count * Font5x7.advance * scale
    }

    /// A canvas from a binary PPM (P6) with 8-bit channels, as `ppmData` writes
    /// it; nil when it is not one.
    public init?(ppm data: [UInt8]) {
        // Header: "P6", width, height, maxval, separated by whitespace and comments.
        var fields: [Int] = []
        var index = 2
        guard data.starts(with: Array("P6".utf8)) else { return nil }
        while fields.count < 3, index < data.count {
            let byte = data[index]
            if byte == UInt8(ascii: "#") {
                while index < data.count, data[index] != UInt8(ascii: "\n") { index += 1 }
            } else if (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) {
                var value = 0
                while index < data.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(data[index]) {
                    value = value * 10 + Int(data[index] - UInt8(ascii: "0"))
                    guard value < 1 << 16 else { return nil }
                    index += 1
                }
                fields.append(value)
                continue
            } else if !(byte == 0x20 || (0x09...0x0D).contains(byte)) {
                return nil
            }
            index += 1
        }
        index += 1  // the single whitespace before the pixels
        guard fields.count == 3, fields[0] > 0, fields[1] > 0, fields[2] == 255,
              data.count - index >= fields[0] * fields[1] * 3 else { return nil }
        width = fields[0]
        height = fields[1]
        pixels = (0..<width * height).map { i in
            let p = index + i * 3
            return UInt32(data[p]) << 16 | UInt32(data[p + 1]) << 8 | UInt32(data[p + 2])
        }
    }

    /// Copies `image` with its top left corner at (`x`, `y`), clipped to the canvas.
    public mutating func draw(_ image: Canvas, x: Int, y: Int) {
        for row in max(0, -y)..<min(image.height, height - y) {
            for col in max(0, -x)..<min(image.width, width - x) {
                pixels[(y + row) * width + x + col] = image.pixels[row * image.width + col]
            }
        }
    }

    /// Binary PPM (P6) of the canvas, for previews off-device.
    public func ppmData() -> [UInt8] {
        var out = Array("P6\n\(width) \(height)\n255\n".utf8)
        out.reserveCapacity(out.count + pixels.count * 3)
        for p in pixels {
            out.append(UInt8(truncatingIfNeeded: p >> 16))
            out.append(UInt8(truncatingIfNeeded: p >> 8))
            out.append(UInt8(truncatingIfNeeded: p))
        }
        return out
    }
}
