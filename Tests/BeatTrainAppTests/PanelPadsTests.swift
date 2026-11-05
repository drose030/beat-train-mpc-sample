@testable import BeatTrainCore
import MPCHardware
import Testing
@testable import beattrain

/// Panel pad numbering and lights, through `PanelPads` and `PanelLights`.
struct PanelPadsTests {
    @Test func rowsAreSwappedAgainstTheOriginalLayout() {
        // The bottom panel row plays Beat-Train's top row (snare first), the second row the bottom row.
        #expect(PanelPads.pad(forPanelPad: 0) == 4)
        #expect(PanelPads.pad(forPanelPad: 3) == 7)
        #expect(PanelPads.pad(forPanelPad: 4) == 0)
        #expect(PanelPads.pad(forPanelPad: 7) == 3)
        for panelPad in 8..<16 { #expect(PanelPads.pad(forPanelPad: panelPad) == nil) }
        for pad in 0..<8 { #expect(PanelPads.pad(forPanelPad: PanelPads.panelPad(forPad: pad)) == pad) }
        #expect(PanelPads.label(forPad: 0) == "PAD 5", "the kick")
        #expect(PanelPads.rows == [[0, 1, 2, 3], [4, 5, 6, 7]], "kick row above, snare row below")
    }

    @Test func lightsSendOnlyChangesAndLeavePads9To16Dark() {
        var lights = PanelLights()
        var colors = [Color](repeating: .white, count: 8)
        let first = lights.changes(to: colors)
        #expect(first.count == 16)
        #expect(first.filter { $0.panelPad >= 8 }.allSatisfy { $0.color == .black })
        #expect(lights.changes(to: colors).isEmpty)
        colors[0] = .black                        // the kick, panel pad 5
        let next = lights.changes(to: colors)
        #expect(next.count == 1 && next[0].panelPad == 4)
        #expect(lights.off().count == 16)
        #expect(lights.changes(to: [Color](repeating: .black, count: 8)).isEmpty)
    }
}
