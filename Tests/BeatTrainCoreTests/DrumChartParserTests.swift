import Foundation
import Testing
@testable import BeatTrainCore

// MARK: - DrumTargetMap

struct DrumTargetMapTests {

    @Test func mapsCanonicalDrumLanes() {
        #expect(DrumTargetMap.target(forCanonicalLane: 0) == DrumTarget(lane: 0, row: .bottom)) // kick
        #expect(DrumTargetMap.target(forCanonicalLane: 1) == DrumTarget(lane: 0, row: .top))    // red
        #expect(DrumTargetMap.target(forCanonicalLane: 2) == DrumTarget(lane: 1, row: .top))    // yellow
        #expect(DrumTargetMap.target(forCanonicalLane: 3) == DrumTarget(lane: 2, row: .top))    // blue
        #expect(DrumTargetMap.target(forCanonicalLane: 4) == DrumTarget(lane: 3, row: .top))    // orange
        #expect(DrumTargetMap.target(forCanonicalLane: 5) == DrumTarget(lane: 3, row: .bottom)) // green
    }

    @Test func rejectsOutOfRangeLanes() {
        #expect(DrumTargetMap.target(forCanonicalLane: -1) == nil)
        #expect(DrumTargetMap.target(forCanonicalLane: 6) == nil)
    }
}

// MARK: - ChartDrumChartParser (text fixtures)

struct ChartDrumChartParserTests {

    private func data(_ text: String) -> Data { Data(text.utf8) }

    private let expertChart = """
    [Song]
    {
      Resolution = 192
    }
    [SyncTrack]
    {
      0 = B 120000
    }
    [ExpertDrums]
    {
      0 = N 0 0
      192 = N 1 0
    }
    """

    @Test func parsesNotesWithCorrectTargetsAndTimes() throws {
        let chart = try ChartDrumChartParser.parse(data: data(expertChart), difficulty: .expert, proDrums: false)
        #expect(chart.ppq == 192)
        #expect(chart.notes.count == 2)
        // tick 0 → kick at 0s
        #expect(chart.notes[0].target == DrumTarget(lane: 0, row: .bottom))
        #expect(abs(chart.notes[0].timeSec - 0.0) < 1e-9)
        // tick 192 (one beat @120 BPM) → red at 0.5s
        #expect(chart.notes[1].target == DrumTarget(lane: 0, row: .top))
        #expect(abs(chart.notes[1].timeSec - 0.5) < 1e-9)
    }

    @Test func mapsExpertPlusKickAlias() throws {
        let chart = try ChartDrumChartParser.parse(data: data("""
        [Song]
        {
          Resolution = 192
        }
        [SyncTrack]
        {
          0 = B 120000
        }
        [ExpertDrums]
        {
          0 = N 32 0
        }
        """), difficulty: .expert, proDrums: false)
        #expect(chart.notes.count == 1)
        #expect(chart.notes[0].target == DrumTarget(lane: 0, row: .bottom)) // kick
    }

    @Test func reportsAvailableDifficulties() throws {
        let available = try ChartDrumChartParser.availableDifficulties(data: data(expertChart))
        #expect(available == [.expert])
    }

    @Test func throwsWhenSyncTrackMissing() {
        // No [SyncTrack] → no tempo → unplayable, surfaced as TempoMap.Failure.
        #expect(throws: TempoMap.Failure.self) {
            _ = try ChartDrumChartParser.parse(data: self.data("""
            [Song]
            {
              Resolution = 192
            }
            [ExpertDrums]
            {
              0 = N 0 0
            }
            """), difficulty: .expert, proDrums: false)
        }
    }

    // MARK: Pro-drums markers

    private let orange = DrumTarget(lane: 3, row: .top)
    private let green = DrumTarget(lane: 3, row: .bottom)

    private func chartText(_ sections: [String: String]) -> String {
        var text = """
        [Song]
        {
          Resolution = 192
        }
        [SyncTrack]
        {
          0 = B 120000
        }

        """
        for (name, body) in sections.sorted(by: { $0.key < $1.key }) {
            text += "[\(name)]\n{\n\(body)\n}\n"
        }
        return text
    }

    private func targets(_ sections: [String: String], _ difficulty: DrumDifficulty = .expert, proDrums: Bool) throws -> [DrumTarget] {
        try ChartDrumChartParser.parse(data: data(chartText(sections)), difficulty: difficulty, proDrums: proDrums)
            .notes.map(\.target)
    }

    @Test func proGreenIsFloorTomUnlessCymbalMarked() throws {
        let notes = """
          0 = N 4 0
          192 = N 4 0
          192 = N 68 0
        """
        #expect(try targets(["ExpertDrums": notes], proDrums: true) == [green, orange])
    }

    @Test func nonProGreenStaysOnOrange() throws {
        #expect(try targets(["ExpertDrums": "  0 = N 4 0"], proDrums: false) == [orange])
    }

    @Test func cymbalMarkersMakeAChartPro() throws {
        // No pro_drums flag, but the charter placed cymbal markers (here on yellow).
        let notes = """
          0 = N 4 0
          192 = N 2 0
          192 = N 66 0
        """
        #expect(try targets(["ExpertDrums": notes], proDrums: false) == [green, DrumTarget(lane: 1, row: .top)])
    }

    @Test func proMarkersApplyToOtherDifficulties() throws {
        let sections = [
            "ExpertDrums": "  0 = N 4 0",
            "HardDrums": "  0 = N 4 0\n  192 = N 4 0\n  192 = N 68 0",
        ]
        #expect(try targets(sections, .hard, proDrums: true) == [green, orange])
    }

    @Test func yellowAndBlueKeepTheirPadsInProCharts() throws {
        let notes = """
          0 = N 2 0
          0 = N 3 0
          192 = N 2 0
          192 = N 66 0
          192 = N 3 0
          192 = N 67 0
        """
        let yellow = DrumTarget(lane: 1, row: .top), blue = DrumTarget(lane: 2, row: .top)
        #expect(try targets(["ExpertDrums": notes], proDrums: true) == [yellow, blue, yellow, blue])
    }

    @Test func fiveLaneChartMapsStraight() throws {
        // N 5 in any section makes the chart 5-lane: N 4 orange, N 5 green.
        let sections = [
            "ExpertDrums": "  0 = N 4 0\n  192 = N 5 0",
            "EasyDrums": "  0 = N 4 0",
        ]
        #expect(try targets(sections, proDrums: true) == [orange, green])
        #expect(try targets(sections, .easy, proDrums: true) == [orange])
    }
}

// MARK: - MidiDrumChartParser (in-memory SMF fixtures)

struct MidiDrumChartParserTests {

    /// Builds a minimal format-0 Standard MIDI File with one "PART DRUMS" track at
    /// ppq 480. Optionally includes a 120 BPM tempo at tick 0, and places two
    /// note-ons (kick=96, red=97 for expert) at tick 480.
    private func makeSMF(includeTempo: Bool) -> Data {
        var track: [UInt8] = []
        if includeTempo {
            // delta 0, FF 51 03, 500000 µs/quarter (120 BPM) = 0x07A120
            track += [0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20]
        }
        let name = Array("PART DRUMS".utf8)
        track += [0x00, 0xFF, 0x03, UInt8(name.count)] + name
        // delta 480 (VLQ 0x83 0x60), note-on ch10 note 96 vel 100
        track += [0x83, 0x60, 0x99, 96, 100]
        // delta 0, note-on note 97 vel 100
        track += [0x00, 0x99, 97, 100]
        // delta 0, end of track
        track += [0x00, 0xFF, 0x2F, 0x00]

        var data: [UInt8] = []
        data += Array("MThd".utf8)
        data += [0x00, 0x00, 0x00, 0x06]       // header length 6
        data += [0x00, 0x00]                   // format 0
        data += [0x00, 0x01]                   // 1 track
        data += [0x01, 0xE0]                   // division 480
        data += Array("MTrk".utf8)
        let len = track.count
        data += [UInt8((len >> 24) & 0xFF), UInt8((len >> 16) & 0xFF),
                 UInt8((len >> 8) & 0xFF), UInt8(len & 0xFF)]
        data += track
        return Data(data)
    }

    @Test func parsesNotesWithTargetsAndTimes() throws {
        let chart = try MidiDrumChartParser.parse(data: makeSMF(includeTempo: true), difficulty: .expert)
        #expect(chart.ppq == 480)
        #expect(chart.notes.count == 2)
        // note 96 = canonical 0 (kick), note 97 = canonical 1 (red)
        #expect(chart.notes.contains { $0.target == DrumTarget(lane: 0, row: .bottom) })
        #expect(chart.notes.contains { $0.target == DrumTarget(lane: 0, row: .top) })
        // tick 480 @120 BPM, ppq 480 → 0.5s
        #expect(abs(chart.notes[0].timeSec - 0.5) < 1e-9)
        #expect(chart.notes[0].velocity == 100)
    }

    @Test func reportsOnlyExpertWhenNotesAtExpertBase() throws {
        let available = try MidiDrumChartParser.availableDifficulties(data: makeSMF(includeTempo: true))
        #expect(available == [.expert])
    }

    @Test func throwsWhenNoTempo() {
        #expect(throws: TempoMap.Failure.self) {
            _ = try MidiDrumChartParser.parse(data: self.makeSMF(includeTempo: false), difficulty: .expert)
        }
    }

    // MARK: Pro-drums markers

    private let orange = DrumTarget(lane: 3, row: .top)
    private let green = DrumTarget(lane: 3, row: .bottom)

    /// A MIDI event in the drum track: note-on (`velocity > 0`), note-on with
    /// velocity 0, or a real note-off (`off: true`).
    private struct Event {
        let tick: Int
        let note: UInt8
        var velocity: UInt8 = 100
        var off = false
    }

    /// One "PART DRUMS" track at ppq 480 and 120 BPM holding `events`.
    private func makeSMF(_ events: [Event]) -> Data {
        func vlq(_ value: Int) -> [UInt8] {
            var bytes = [UInt8(value & 0x7F)]
            var rest = value >> 7
            while rest > 0 {
                bytes.insert(UInt8(rest & 0x7F) | 0x80, at: 0)
                rest >>= 7
            }
            return bytes
        }
        let name = Array("PART DRUMS".utf8)
        var track: [UInt8] = [0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20]
        track += [0x00, 0xFF, 0x03, UInt8(name.count)] + name
        var tick = 0
        for event in events.sorted(by: { $0.tick < $1.tick }) {
            track += vlq(event.tick - tick)
            track += event.off ? [0x89, event.note, 0x40] : [0x99, event.note, event.velocity]
            tick = event.tick
        }
        track += [0x00, 0xFF, 0x2F, 0x00]

        var data: [UInt8] = Array("MThd".utf8) + [0, 0, 0, 6, 0, 0, 0, 1, 0x01, 0xE0]
        data += Array("MTrk".utf8)
        let len = track.count
        data += [UInt8((len >> 24) & 0xFF), UInt8((len >> 16) & 0xFF),
                 UInt8((len >> 8) & 0xFF), UInt8(len & 0xFF)]
        return Data(data + track)
    }

    private func targets(_ events: [Event], _ difficulty: DrumDifficulty = .expert) throws -> [DrumTarget] {
        try MidiDrumChartParser.parse(data: makeSMF(events), difficulty: difficulty).notes.map(\.target)
    }

    @Test func unmarkedGreenLaneIsACymbalOnOrange() throws {
        #expect(try targets([Event(tick: 0, note: 100)]) == [orange])
    }

    @Test func floorTomMarkerMovesGreenLaneToGreen() throws {
        let events = [
            Event(tick: 0, note: 112), Event(tick: 0, note: 100), Event(tick: 120, note: 112, off: true),
            Event(tick: 480, note: 100),
        ]
        #expect(try targets(events) == [green, orange])
    }

    @Test func floorTomMarkerSpansSeveralNotes() throws {
        // Marker 240..<1200, closed by a velocity-0 note-on: the note at its end is not covered.
        let events = [
            Event(tick: 0, note: 100),
            Event(tick: 240, note: 112),
            Event(tick: 240, note: 100), Event(tick: 480, note: 100), Event(tick: 960, note: 100),
            Event(tick: 1200, note: 112, velocity: 0),
            Event(tick: 1200, note: 100),
        ]
        #expect(try targets(events) == [orange, green, green, green, orange])
    }

    @Test func floorTomMarkerAppliesToEveryDifficulty() throws {
        let events = [
            Event(tick: 0, note: 112),
            Event(tick: 0, note: 100), Event(tick: 0, note: 88), Event(tick: 0, note: 76), Event(tick: 0, note: 64),
            Event(tick: 480, note: 112, off: true),
            Event(tick: 480, note: 88),
        ]
        #expect(try targets(events) == [green])
        #expect(try targets(events, .hard) == [green, orange])
        #expect(try targets(events, .medium) == [green])
        #expect(try targets(events, .easy) == [green])
    }

    @Test func yellowAndBlueKeepTheirPadsUnderTomMarkers() throws {
        let events = [
            Event(tick: 0, note: 110), Event(tick: 0, note: 111),
            Event(tick: 0, note: 98), Event(tick: 0, note: 99),
            Event(tick: 240, note: 110, off: true), Event(tick: 240, note: 111, off: true),
        ]
        let chart = try MidiDrumChartParser.parse(data: makeSMF(events), difficulty: .expert)
        #expect(Set(chart.notes.map(\.target)) == [DrumTarget(lane: 1, row: .top), DrumTarget(lane: 2, row: .top)])
    }

    @Test func fiveLaneChartIgnoresFloorTomMarker() throws {
        // Note 101 anywhere makes the chart 5-lane: 100 orange, 101 green, markers or not.
        let events = [
            Event(tick: 0, note: 112),
            Event(tick: 0, note: 100), Event(tick: 240, note: 101), Event(tick: 240, note: 88),
            Event(tick: 480, note: 112, off: true),
        ]
        #expect(try targets(events) == [orange, green])
        #expect(try targets(events, .hard) == [orange])
    }
}
