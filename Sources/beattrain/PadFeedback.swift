import BeatTrainCore

/// What the play screen shows of the player's strikes, for a moment each: which
/// pads were just struck and how each pad's last note was judged. Kept per **Pad**,
/// so the pad lights and every highway layout show the same; the four-lane highway
/// asks per **Lane**.
struct PadFeedback {
    /// How long a struck pad stays lit (its light, its panel map, its lane on the
    /// by-pad and horizontal highways).
    static let strikeSec = 0.12
    /// How long a strike tints its lane on the four-lane highway.
    static let laneSec = 0.1
    /// How long a judgement shows at the strike line.
    static let judgementSec = 0.15

    private var struckAt = [Double](repeating: -.infinity, count: DrumKit.padCount)
    private var judgedAt = [Double](repeating: -.infinity, count: DrumKit.padCount)
    private var wasHit = [Bool](repeating: false, count: DrumKit.padCount)

    mutating func strike(pad: Int, at now: Double) {
        struckAt[pad] = now
    }

    /// A judgement from the session, on the pad whose slot `target` is: the note's
    /// for a hit or a missed note, the struck pad's for an overhit.
    mutating func judge(_ target: DrumTarget, isHit: Bool, at now: Double) {
        let pad = DrumKit.pad(forLayout: target)
        judgedAt[pad] = now
        wasHit[pad] = isHit
    }

    func isStruck(pad: Int, at now: Double) -> Bool {
        struckAt[pad] + Self.strikeSec > now
    }

    /// The pad's judgement while it shows: `true` hit, `false` miss.
    func judgement(ofPad pad: Int, at now: Double) -> Bool? {
        judgedAt[pad] + Self.judgementSec > now ? wasHit[pad] : nil
    }

    /// The pad last struck in `lane` while the lane is tinted.
    func struckPad(inLane lane: Int, at now: Double) -> Int? {
        guard let pad = Self.pads(inLane: lane).max(by: { struckAt[$0] < struckAt[$1] }) else { return nil }
        return struckAt[pad] + Self.laneSec > now ? pad : nil
    }

    /// The last judgement in `lane` while it shows.
    func judgement(ofLane lane: Int, at now: Double) -> Bool? {
        guard let pad = Self.pads(inLane: lane).max(by: { judgedAt[$0] < judgedAt[$1] }) else { return nil }
        return judgement(ofPad: pad, at: now)
    }

    private static func pads(inLane lane: Int) -> [Int] {
        (0..<DrumKit.padCount).filter { DrumKit.layoutTarget(forPad: $0).lane == lane }
    }
}
