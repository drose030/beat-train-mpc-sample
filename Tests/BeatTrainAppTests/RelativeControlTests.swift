import Testing
@testable import beattrain

/// A knob or the fader moving a value by how far it goes.
struct RelativeControlTests {
    @Test func itMovesByHowFarItWentNotToWhereItStands() {
        var control = RelativeControl()
        #expect(control.move(to: 100, from: 0.5, step: 0.05, travel: 1, range: 0...1) == nil, "the first report only tells where it stands")
        let moved = control.move(to: 113, from: 0.5, step: 0.05, travel: 1, range: 0...1)
        #expect(moved.map { abs($0 - 0.6) < 0.01 } == true)
    }

    @Test func smallTurnsAddUpAndItStopsAtTheEnds() {
        var control = RelativeControl()
        _ = control.move(to: 0, from: 0, step: 0.05, travel: 1, range: 0...1)
        // Four reports of 2/127 each: 0.016 apiece, below a step, 0.063 together.
        var value = 0.0
        for position in [2, 4, 6, 8] as [UInt8] {
            let moved = control.move(to: position, from: value, step: 0.05, travel: 1, range: 0...1)!
            value = (moved / 0.05).rounded(.down) * 0.05
        }
        #expect(value == 0.05)
        #expect(control.move(to: 127, from: 0.05, step: 0.05, travel: 5, range: 0...1) == 1)
    }

    @Test func aValueChangedElsewhereIsWhereItGoesOnFrom() {
        var control = RelativeControl()
        _ = control.move(to: 0, from: 0, step: 0.05, travel: 1, range: 0...1)
        _ = control.move(to: 10, from: 0, step: 0.05, travel: 1, range: 0...1)
        let moved = control.move(to: 10, from: 0.5, step: 0.05, travel: 1, range: 0...1)
        #expect(moved == 0.5, "set to 50 % meanwhile")
    }

    @Test func followingSetsNothingButMovesTheReference() {
        var control = RelativeControl()
        control.follow(to: 127)
        let moved = control.move(to: 64, from: 1, step: 0.05, travel: 0.5, range: 0.5...1)
        #expect(moved.map { abs($0 - 0.752) < 0.001 } == true)
    }
}
