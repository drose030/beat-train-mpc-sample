/// A knob or the fader as it sets a value: it reports where it stands (0–127), and
/// the value moves by how far it went since its last report, not to where it
/// stands. The MPC does not report where its knobs stand at start, so a saved
/// value would otherwise jump to the knob; a fader left anywhere does not make a
/// value jump either. The first report only tells where it stands.
struct RelativeControl {
    private var last: UInt8?
    /// The value it has moved to, before rounding to the value's step: small turns
    /// add up.
    private var unrounded: Double?

    /// The control stands at `value`: `current` moved by how far it went since its
    /// last report (`travel` for its whole way), kept in `range`, not yet rounded to
    /// `step`. Nil for its first report.
    mutating func move(to value: UInt8, from current: Double, step: Double, travel: Double, range: ClosedRange<Double>) -> Double? {
        defer { last = value }
        guard let last else { return nil }
        var moved = unrounded ?? current
        // Changed elsewhere (the settings screen, ERASE, the control's other use):
        // go on from there.
        if abs(moved - current) >= step { moved = current }
        moved = min(max(moved + Double(Int(value) - Int(last)) / 127 * travel, range.lowerBound), range.upperBound)
        unrounded = moved
        return moved
    }

    /// The control stands at `value` and sets nothing (the fader without SHIFT).
    mutating func follow(to value: UInt8) {
        last = value
        unrounded = nil
    }
}
