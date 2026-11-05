#if canImport(FoundationEssentials)
import FoundationEssentials  // no ICU: keeps the static Linux binary small
#else
import Foundation
#endif
import MPCHardware

/// The start picture: one of the original Beat-Train splash screens, on screen for
/// `shownSec`, or until a press once `minimumSec` have passed (a hand still on the
/// panel would skip it at once).
struct Splash {
    static let shownSec = 2.0
    static let minimumSec = 1.5
    /// The pictures next to the executable: 320×240 binary PPM, so no image decoder is needed.
    static let files = ["splash1.ppm", "splash2.ppm"]

    let image: Canvas
    let since: Double

    /// What an event does while the picture is up.
    enum Effect: Equatable {
        /// Works as usual (knobs, releases).
        case passes
        /// Ignored: a press before `minimumSec`.
        case swallowed
        /// Ends the picture, and only that.
        case ends
    }

    /// One of `files` in `directory`, picked at random as in the original game; nil when
    /// none can be read.
    static func load(from directory: URL, now: Double) -> Splash? {
        files.shuffled().lazy.compactMap { name in
            (try? Data(contentsOf: directory.appendingPathComponent(name))).flatMap { Canvas(ppm: [UInt8]($0)) }
        }.first.map { Splash(image: $0, since: now) }
    }

    func isOver(now: Double) -> Bool {
        now >= since + Self.shownSec
    }

    func effect(of event: ControlEvent, now: Double) -> Effect {
        switch event {
        // The panel reports the encoder with delta 0 at start; that is no turn.
        case .button(_, pressed: true), .padDown, .encoder(delta: 1...), .encoder(delta: ...(-1)):
            now >= since + Self.minimumSec ? .ends : .swallowed
        default:
            .passes
        }
    }

    /// The picture, centred, with the version on a dark plate in the bottom right
    /// corner.
    func draw(into canvas: inout Canvas) {
        canvas.draw(image, x: (canvas.width - image.width) / 2, y: (canvas.height - image.height) / 2)
        let text = "v\(BeatTrainApp.version)"
        let width = Canvas.textWidth(text) + 5
        canvas.fillRect(x: canvas.width - width, y: canvas.height - 12, width: width, height: 12, .black)
        canvas.drawText(text, x: canvas.width - width + 3, y: canvas.height - 10, .white)
    }
}
