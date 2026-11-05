import MPCHardware
import Testing

/// What goes out to the panel: only what changed, strip by strip, in order.
struct ChangedStripsTests {
    @Test func nothingChangedSendsNothing() {
        let frame = Canvas(width: 320, height: 240)
        #expect(Display.changedStrips(from: frame, to: frame, sweep: .rows).isEmpty)
    }

    @Test func rowsGoTopToBottomEachAsNarrowAsWhatChanged() {
        let old = Canvas(width: 320, height: 240)
        var new = old
        new.fillRect(x: 100, y: 20, width: 10, height: 2, .white)   // in the second band
        new.fillRect(x: 5, y: 200, width: 1, height: 1, .white)
        new.fillRect(x: 300, y: 205, width: 4, height: 1, .white)  // the same band as the last
        let rects = Display.changedStrips(from: old, to: new, sweep: .rows)
        #expect(rects.map(\.x) == [100, 5])
        #expect(rects.map(\.y) == [16, 192])
        #expect(rects.map(\.width) == [10, 299])
        #expect(rects.map(\.height) == [16, 16], "whole bands")
    }

    @Test func columnsGoLeftToRightEachAsShortAsWhatChanged() {
        let old = Canvas(width: 320, height: 240)
        var new = old
        // A note moving sideways across two strips.
        new.fillRect(x: 40, y: 100, width: 10, height: 20, .white)
        let rects = Display.changedStrips(from: old, to: new, sweep: .columns)
        #expect(rects.map(\.x) == [32, 48])
        #expect(rects.allSatisfy { $0.y == 100 && $0.height == 20 && $0.width == 16 })
    }

    @Test func theLastStripIsCutAtTheEdge() {
        let old = Canvas(width: 20, height: 20)
        var new = old
        new.fillRect(x: 19, y: 19, width: 1, height: 1, .white)
        let rects = Display.changedStrips(from: old, to: new, sweep: .columns)
        #expect(rects.count == 1 && rects[0].x == 16 && rects[0].width == 4)
    }
}
