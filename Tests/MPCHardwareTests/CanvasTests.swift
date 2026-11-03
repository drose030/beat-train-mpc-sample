import Testing
@testable import MPCHardware

struct CanvasTests {
    @Test func fillRectIsClippedToTheCanvas() {
        var canvas = Canvas(width: 4, height: 3)
        canvas.fillRect(x: -2, y: 1, width: 4, height: 10, .white)
        #expect(canvas.pixel(x: 0, y: 0) == .black)
        #expect(canvas.pixel(x: 1, y: 2) == .white)
        #expect(canvas.pixel(x: 2, y: 1) == .black)
    }

    @Test func drawTextAdvancesSixPixelsPerGlyph() {
        var canvas = Canvas(width: 20, height: 8)
        let end = canvas.drawText("I!", x: 1, y: 0, .white)
        #expect(end == 13)
        // 'I' has its full-height bar in column 2.
        #expect(canvas.pixel(x: 3, y: 3) == .white)
        #expect(canvas.pixel(x: 1, y: 3) == .black)
    }

    @Test func ppmHasHeaderAndRGBTriples() {
        var canvas = Canvas(width: 2, height: 1)
        canvas.fillRect(x: 1, y: 0, width: 1, height: 1, Color(r: 1, g: 2, b: 3))
        let ppm = canvas.ppmData()
        #expect(Array(ppm.suffix(6)) == [0, 0, 0, 1, 2, 3])
        #expect(String(decoding: ppm.prefix(11), as: UTF8.self) == "P6\n2 1\n255\n")
    }

    @Test func ppmReadsBackWhatItWrote() throws {
        var canvas = Canvas(width: 3, height: 2)
        canvas.fillRect(x: 1, y: 1, width: 2, height: 1, Color(r: 10, g: 200, b: 30))
        let read = try #require(Canvas(ppm: canvas.ppmData()))
        #expect(read.width == 3 && read.height == 2)
        #expect(read.pixels == canvas.pixels)
        // Comments and other whitespace in the header, as image tools write them.
        let tool = Array("P6 # made elsewhere\n3\t2\r\n255\n".utf8) + Array(canvas.ppmData().suffix(18))
        #expect(Canvas(ppm: tool)?.pixels == canvas.pixels)
    }

    @Test func ppmRejectsOtherFiles() {
        #expect(Canvas(ppm: Array("P3\n1 1\n255\n0 0 0".utf8)) == nil, "text PPM")
        #expect(Canvas(ppm: Array("P6\n1 1\n65535\n".utf8) + [0, 0, 0, 0, 0, 0]) == nil, "16-bit")
        #expect(Canvas(ppm: Array("P6\n2 2\n255\n".utf8) + [0, 0, 0]) == nil, "too short")
        #expect(Canvas(ppm: []) == nil)
    }

    @Test func drawCopiesAnImageClipped() {
        var canvas = Canvas(width: 4, height: 3)
        let image = Canvas(width: 2, height: 2, fill: .white)
        canvas.draw(image, x: 3, y: -1)
        #expect(canvas.pixel(x: 3, y: 0) == .white)
        #expect(canvas.pixel(x: 3, y: 1) == .black)
        #expect(canvas.pixel(x: 2, y: 0) == .black)
    }

    @Test func colorMixInterpolates() {
        #expect(Color.black.mixed(with: .white, amount: 0.5) == Color(r: 128, g: 128, b: 128))
    }
}
