// Hardware bring-up for the MPC Sample: draws a test screen, shows every pad,
// button, knob and encoder event, and lights the pads. SHIFT + STOP exits.
//
//   beattrain-hwtest                 run on the device (stock app stopped)
//   beattrain-hwtest --ppm FILE      render a sample frame to a PPM file and exit

import MPCHardware

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

nonisolated(unsafe) var stopRequested: sig_atomic_t = 0

func log(_ line: String) {
    print(line)
    fflush(nil)  // all streams; glibc's `stdout` is a global var Swift 6 rejects
}

struct HWTestState {
    var padVelocity = [UInt8](repeating: 0, count: 16)
    var padHitAt = [Double](repeating: -10, count: 16)
    var padHeld = [Bool](repeating: false, count: 16)
    var controls: [PanelControl: UInt8] = [:]
    var encoder = 0
    var heldButtons: Set<PanelButton> = []
    var lastLines: [String] = []
    var frames = 0
    var fps = 0.0
    var status = ""

    mutating func note(_ line: String) {
        lastLines.append(line)
        if lastLines.count > 7 { lastLines.removeFirst() }
        log(line)
    }
}

enum Palette {
    static let background = Color(rgb: 0x0B0E14)
    static let panel = Color(rgb: 0x1A1F2B)
    static let text = Color(rgb: 0xE6E9F0)
    static let dim = Color(rgb: 0x7A8194)
    static let accent = Color(rgb: 0xFF8A1F)
    static let hit = Color(rgb: 0xFFB000)
    static let bar = Color(rgb: 0x3FA7FF)
    static let padIdle = Color(r: 0, g: 0, b: 24)
}

func render(_ state: HWTestState, now: Double, into canvas: inout Canvas) {
    canvas.clear(Palette.background)
    canvas.fillRect(x: 0, y: 0, width: canvas.width, height: 14, Palette.panel)
    canvas.drawText("BEAT-TRAIN", x: 4, y: 3, Palette.accent)
    canvas.drawText("HW TEST", x: 70, y: 3, Palette.text)
    let info = "\(canvas.width)x\(canvas.height) \(Int(state.fps.rounded()))fps"
    canvas.drawText(info, x: canvas.width - Canvas.textWidth(info) - 4, y: 3, Palette.dim)

    // Pads: pad 1 bottom left, pad 16 top right, as on the device.
    let size = 34, gap = 4, originX = 6, originY = 20
    for pad in 0..<16 {
        let col = pad % 4, row = 3 - pad / 4
        let x = originX + col * (size + gap), y = originY + row * (size + gap)
        let age = now - state.padHitAt[pad]
        let flash = max(0, 1 - age / 0.35)
        let strength = Double(state.padVelocity[pad]) / 127
        let fill = Palette.panel.mixed(with: Palette.hit, amount: flash * (0.35 + 0.65 * strength))
        canvas.fillRect(x: x, y: y, width: size, height: size, fill)
        canvas.strokeRect(x: x, y: y, width: size, height: size, state.padHeld[pad] ? Palette.text : Palette.dim)
        canvas.drawText("\(pad + 1)", x: x + 3, y: y + 3, Palette.text)
        if state.padVelocity[pad] > 0 {
            canvas.drawText("\(state.padVelocity[pad])", x: x + 3, y: y + size - 10, Palette.dim)
        }
    }

    // Knobs and fader as bars, the encoder as a counter.
    let barsX = 166
    var y = 22
    for control in PanelControl.allCases {
        let value = state.controls[control]
        canvas.drawText(control.name, x: barsX, y: y, Palette.dim)
        let barX = barsX + 44, barW = 100
        canvas.strokeRect(x: barX, y: y - 1, width: barW, height: 9, Palette.dim)
        if let value {
            canvas.fillRect(x: barX + 1, y: y, width: (barW - 2) * Int(value) / 127, height: 7, Palette.bar)
        }
        y += 13
    }
    canvas.drawText("ENC", x: barsX, y: y, Palette.dim)
    canvas.drawText("\(state.encoder)", x: barsX + 44, y: y, Palette.text)
    y += 13
    let held = state.heldButtons.map(\.name).sorted().joined(separator: " ")
    canvas.drawText(held.isEmpty ? "-" : String(held.prefix(24)), x: barsX, y: y, Palette.accent)

    // Event log.
    var logY = 178
    canvas.fillRect(x: 0, y: logY - 4, width: canvas.width, height: 1, Palette.panel)
    for line in state.lastLines.suffix(5) {
        canvas.drawText(String(line.prefix(52)), x: 4, y: logY, Palette.text)
        logY += 10
    }
    if !state.status.isEmpty {
        canvas.drawText(String(state.status.prefix(52)), x: 4, y: canvas.height - 10, Palette.accent)
    } else {
        canvas.drawText("SHIFT+STOP: back to MPC", x: 4, y: canvas.height - 10, Palette.dim)
    }
}

func renderPreview(to path: String) -> Int32 {
    var state = HWTestState()
    let now = 10.0
    state.padVelocity[0] = 127; state.padHitAt[0] = now
    state.padVelocity[5] = 64; state.padHitAt[5] = now - 0.1; state.padHeld[5] = true
    state.padVelocity[14] = 20; state.padHitAt[14] = now - 0.2
    state.controls = [.k1: 32, .k2: 64, .k3: 127, .mainVolume: 100, .fader: 10]
    state.encoder = -3
    state.heldButtons = [.shift]
    state.fps = 42
    for line in ["pad 1 down vel 127", "pad 6 down vel 64", "K2 = 64", "SHIFT down", "encoder -1"] {
        state.lastLines.append(line)
    }
    var canvas = Canvas(width: 320, height: 240)
    render(state, now: now, into: &canvas)
    let data = canvas.ppmData()
    guard let file = fopen(path, "wb") else {
        log("cannot write \(path)")
        return 1
    }
    fwrite(data, 1, data.count, file)
    fclose(file)
    log("wrote \(path)")
    return 0
}

func run() -> Int32 {
    signal(SIGTERM) { _ in stopRequested = 1 }
    signal(SIGINT) { _ in stopRequested = 1 }

    var state = HWTestState()

    let display: Display?
    do {
        display = try Display()
        log("display \(display!.width)x\(display!.height)")
    } catch {
        log("display error: \(error)")
        display = nil
    }

    let surface: ControlSurface?
    do {
        let opened = try ControlSurface()
        if getenv("BEATTRAIN_TRACE") != nil {
            opened.trace = { bytes in
                log("rx " + bytes.map { String($0, radix: 16, uppercase: true) }.joined(separator: " "))
            }
        }
        try opened.sendInit()
        for pad in 0..<16 { try opened.send(ControlSurfaceProtocol.padColor(pad: pad, Palette.padIdle)) }
        log("control surface \(opened.devicePath)")
        surface = opened
    } catch {
        state.status = "pads: \(error)"
        log("control surface error: \(error)")
        surface = nil
    }

    if display == nil && surface == nil { return 2 }

    var canvas = display?.makeCanvas() ?? Canvas(width: 320, height: 240)
    var fpsWindowStart = monotonicSeconds()
    var fpsFrames = 0
    // Not every DRM driver blocks on the flip (virtio-gpu returns at once), so frames
    // are paced here; the time until the next frame is spent waiting for input.
    let frameInterval = 1.0 / 60
    var nextFrame = monotonicSeconds()

    while stopRequested == 0 {
        let untilFrame = max(0, nextFrame - monotonicSeconds())
        if surface == nil {
            usleep(UInt32(untilFrame * 1_000_000))
        }
        if let surface {
            let events: [ControlEvent]
            do {
                events = try surface.poll(timeoutMs: Int32((untilFrame * 1000).rounded(.up)))
            } catch {
                state.status = "\(error)"
                events = []
            }
            let now = monotonicSeconds()
            for event in events {
                switch event {
                case let .padDown(pad, velocity):
                    state.padVelocity[pad] = velocity
                    state.padHitAt[pad] = now
                    state.padHeld[pad] = true
                    state.note("pad \(pad + 1) down vel \(velocity)")
                    try? surface.send(ControlSurfaceProtocol.padColor(pad: pad, Palette.hit))
                case let .padUp(pad):
                    state.padHeld[pad] = false
                    try? surface.send(ControlSurfaceProtocol.padColor(pad: pad, Palette.padIdle))
                case let .padPressure(pad, pressure):
                    state.padVelocity[pad] = max(state.padVelocity[pad], pressure)
                case let .button(button, pressed):
                    if pressed {
                        state.heldButtons.insert(button)
                        state.note("\(button.name) down")
                    } else {
                        state.heldButtons.remove(button)
                    }
                    try? surface.send(ControlSurfaceProtocol.buttonLED(button, state: pressed ? 2 : 0))
                    if pressed && button == .stop && state.heldButtons.contains(.shift) {
                        stopRequested = 1
                    }
                case let .encoder(delta):
                    state.encoder += delta
                    state.note("encoder \(delta > 0 ? "+" : "")\(delta)")
                case let .control(control, value):
                    state.controls[control] = value
                }
            }
        }

        let now = monotonicSeconds()
        if let display, now >= nextFrame {
            nextFrame = max(nextFrame + frameInterval, now)
            render(state, now: now, into: &canvas)
            do {
                try display.present(canvas)
            } catch {
                log("present error: \(error)")
                usleep(16_000)
            }
            fpsFrames += 1
            if now - fpsWindowStart >= 1 {
                state.fps = Double(fpsFrames) / (now - fpsWindowStart)
                fpsFrames = 0
                fpsWindowStart = now
            }
        }
    }

    if let surface {
        for pad in 0..<16 { try? surface.send(ControlSurfaceProtocol.padColor(pad: pad, .black)) }
    }
    log("exit")
    return 0
}

let arguments = CommandLine.arguments
if arguments.count == 3 && arguments[1] == "--ppm" {
    exit(renderPreview(to: arguments[2]))
}
exit(run())
