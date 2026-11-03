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
        let chart = try ChartDrumChartParser.parse(data: data(expertChart), difficulty: .expert)
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
        """), difficulty: .expert)
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
            """), difficulty: .expert)
        }
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
}
