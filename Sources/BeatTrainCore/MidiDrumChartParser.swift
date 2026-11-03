#if canImport(FoundationEssentials)
import FoundationEssentials  // no ICU: keeps the static Linux binary small
#else
import Foundation
#endif

enum MidiDrumChartParserError: Error, LocalizedError {
    case invalidHeader
    case invalidTrackChunk
    case unsupportedTimeDivision
    case malformedVariableLengthQuantity

    var errorDescription: String? {
        switch self {
        case .invalidHeader:
            return "Invalid MIDI header."
        case .invalidTrackChunk:
            return "Invalid MIDI track chunk."
        case .unsupportedTimeDivision:
            return "Unsupported MIDI time division (SMPTE)."
        case .malformedVariableLengthQuantity:
            return "Malformed MIDI variable-length quantity."
        }
    }
}

/// Parses Standard MIDI Files into a `DrumChart`. Operates on in-memory `Data`;
/// file reading is `DrumChartLoader`'s job. Tick↔seconds lives in `TempoMap`,
/// drum-colour placement in `DrumTargetMap`.
enum MidiDrumChartParser {
    static func parse(data: Data, difficulty: DrumDifficulty = .expert) throws -> DrumChart {
        let parsed = try parseTracks(data: data)
        let tempoMap = try TempoMap(ppq: parsed.ppq, changes: parsed.tempoChanges)

        let notes = parsed.noteOns
            .compactMap { event -> DrumNoteEvent? in
                guard let target = mapTarget(from: event.note, difficulty: difficulty) else { return nil }
                return DrumNoteEvent(
                    tick: event.tick,
                    timeSec: tempoMap.seconds(forTick: event.tick),
                    target: target,
                    velocity: event.velocity
                )
            }
            .sorted { lhs, rhs in lhs.tick < rhs.tick }

        return DrumChart(tempoMap: tempoMap, notes: notes)
    }

    /// Difficulties that actually contain drum notes. Parses the file once and
    /// inspects note ranges per difficulty; requires a usable tempo map (an
    /// untimeable chart yields no playable difficulties — the error propagates).
    static func availableDifficulties(data: Data) throws -> [DrumDifficulty] {
        let parsed = try parseTracks(data: data)
        _ = try TempoMap(ppq: parsed.ppq, changes: parsed.tempoChanges)
        return DrumDifficulty.allCases.filter { difficulty in
            parsed.noteOns.contains { mapTarget(from: $0.note, difficulty: difficulty) != nil }
        }
    }

    // MARK: - Parsing

    private struct ParsedFile {
        let ppq: Int
        let tempoChanges: [(tick: Int, bpm: Double)]
        let noteOns: [RawNoteOnEvent]
    }

    private static func parseTracks(data: Data) throws -> ParsedFile {
        var reader = DataReader(data: data)
        let header = try parseHeader(&reader)
        guard header.division > 0 else {
            throw MidiDrumChartParserError.unsupportedTimeDivision
        }

        var tracks: [ParsedTrack] = []
        for _ in 0..<header.trackCount {
            tracks.append(try parseTrack(&reader))
        }

        let selectedTracks = selectDrumTracks(from: tracks)
        let rawTempos = tracks
            .flatMap(\.tempoEvents)
            .sorted { $0.tick < $1.tick }
        let tempoChanges = rawTempos.map {
            (tick: $0.tick, bpm: 60_000_000.0 / Double($0.microsecondsPerQuarter))
        }
        let noteOns = selectedTracks.flatMap(\.noteOnEvents)

        return ParsedFile(ppq: header.division, tempoChanges: tempoChanges, noteOns: noteOns)
    }

    private static func parseHeader(_ reader: inout DataReader) throws -> MidiHeader {
        guard try reader.readASCII(4) == "MThd" else {
            throw MidiDrumChartParserError.invalidHeader
        }
        let headerLength = try reader.readUInt32()
        guard headerLength >= 6 else {
            throw MidiDrumChartParserError.invalidHeader
        }

        let format = try reader.readUInt16()
        let trackCount = try reader.readUInt16()
        let division = Int16(bitPattern: try reader.readUInt16())

        if headerLength > 6 {
            try reader.skip(Int(headerLength - 6))
        }

        return MidiHeader(format: format, trackCount: Int(trackCount), division: Int(division))
    }

    private static func parseTrack(_ reader: inout DataReader) throws -> ParsedTrack {
        guard try reader.readASCII(4) == "MTrk" else {
            throw MidiDrumChartParserError.invalidTrackChunk
        }

        let trackLength = Int(try reader.readUInt32())
        let trackEnd = reader.offset + trackLength
        guard trackEnd <= reader.data.count else {
            throw MidiDrumChartParserError.invalidTrackChunk
        }

        var absoluteTick = 0
        var runningStatus: UInt8?
        var trackName: String?
        var tempos: [RawTempoEvent] = []
        var noteOns: [RawNoteOnEvent] = []

        while reader.offset < trackEnd {
            let delta = try reader.readVariableLengthQuantity()
            absoluteTick += delta

            let firstByte = try reader.peekByte()

            if firstByte == 0xFF {
                _ = try reader.readByte()
                let metaType = try reader.readByte()
                let length = try reader.readVariableLengthQuantity()
                let payload = try reader.readData(length: length)
                runningStatus = nil

                switch metaType {
                case 0x03:
                    if let name = String(data: payload, encoding: .utf8), !name.isEmpty {
                        trackName = name
                    } else if let nameLatin = String(data: payload, encoding: .isoLatin1), !nameLatin.isEmpty {
                        trackName = nameLatin
                    }
                case 0x51:
                    if payload.count == 3 {
                        let mpqn = Int(payload[payload.startIndex]) << 16
                            | Int(payload[payload.startIndex.advanced(by: 1)]) << 8
                            | Int(payload[payload.startIndex.advanced(by: 2)])
                        tempos.append(RawTempoEvent(tick: absoluteTick, microsecondsPerQuarter: mpqn))
                    }
                default:
                    break
                }
                continue
            }

            if firstByte == 0xF0 || firstByte == 0xF7 {
                _ = try reader.readByte()
                let length = try reader.readVariableLengthQuantity()
                try reader.skip(length)
                runningStatus = nil
                continue
            }

            let status: UInt8
            if firstByte & 0x80 != 0 {
                status = try reader.readByte()
                runningStatus = status
            } else if let rs = runningStatus {
                status = rs
            } else {
                throw MidiDrumChartParserError.invalidTrackChunk
            }

            let eventType = status & 0xF0
            let channel = Int(status & 0x0F)

            let dataLength: Int
            switch eventType {
            case 0xC0, 0xD0:
                dataLength = 1
            default:
                dataLength = 2
            }

            let data1 = try reader.readByte()
            let data2: UInt8 = dataLength == 2 ? try reader.readByte() : 0

            if eventType == 0x90, data2 > 0 {
                noteOns.append(
                    RawNoteOnEvent(
                        tick: absoluteTick,
                        channel: channel,
                        note: data1,
                        velocity: data2
                    )
                )
            }
        }

        if reader.offset < trackEnd {
            try reader.skip(trackEnd - reader.offset)
        }

        return ParsedTrack(name: trackName, tempoEvents: tempos, noteOnEvents: noteOns)
    }

    private static func selectDrumTracks(from tracks: [ParsedTrack]) -> [ParsedTrack] {
        let namedDrumTracks = tracks.filter { track in
            guard let name = track.name?.uppercased() else { return false }
            return name.contains("PART DRUMS") || name.contains("PART DRUM")
        }

        if !namedDrumTracks.isEmpty {
            return namedDrumTracks
        }

        // Fallback for files missing names: channel 10 (index 9) note activity.
        return tracks.filter { track in
            track.noteOnEvents.contains(where: { $0.channel == 9 })
        }
    }

    /// Translates a MIDI note to a canonical drum lane (note − difficulty base) and
    /// looks up its target in `DrumTargetMap`.
    private static func mapTarget(from note: UInt8, difficulty: DrumDifficulty) -> DrumTarget? {
        DrumTargetMap.target(forCanonicalLane: Int(note) - Int(difficulty.midiBaseNote))
    }
}

private struct MidiHeader {
    let format: UInt16
    let trackCount: Int
    let division: Int
}

private struct ParsedTrack {
    let name: String?
    let tempoEvents: [RawTempoEvent]
    let noteOnEvents: [RawNoteOnEvent]
}

private struct RawTempoEvent {
    let tick: Int
    let microsecondsPerQuarter: Int
}

private struct RawNoteOnEvent {
    let tick: Int
    let channel: Int
    let note: UInt8
    let velocity: UInt8
}

private struct DataReader {
    let data: Data
    var offset: Int = 0

    mutating func readByte() throws -> UInt8 {
        guard offset < data.count else { throw MidiDrumChartParserError.invalidTrackChunk }
        let value = data[data.startIndex.advanced(by: offset)]
        offset += 1
        return value
    }

    mutating func peekByte() throws -> UInt8 {
        guard offset < data.count else { throw MidiDrumChartParserError.invalidTrackChunk }
        return data[data.startIndex.advanced(by: offset)]
    }

    mutating func readASCII(_ count: Int) throws -> String {
        let bytes = try readData(length: count)
        return String(decoding: bytes, as: UTF8.self)
    }

    mutating func readUInt16() throws -> UInt16 {
        let b1 = UInt16(try readByte())
        let b2 = UInt16(try readByte())
        return (b1 << 8) | b2
    }

    mutating func readUInt32() throws -> UInt32 {
        let b1 = UInt32(try readByte())
        let b2 = UInt32(try readByte())
        let b3 = UInt32(try readByte())
        let b4 = UInt32(try readByte())
        return (b1 << 24) | (b2 << 16) | (b3 << 8) | b4
    }

    mutating func readVariableLengthQuantity() throws -> Int {
        var value = 0
        for _ in 0..<4 {
            let byte = Int(try readByte())
            value = (value << 7) | (byte & 0x7F)
            if (byte & 0x80) == 0 {
                return value
            }
        }
        throw MidiDrumChartParserError.malformedVariableLengthQuantity
    }

    mutating func readData(length: Int) throws -> Data {
        guard length >= 0, offset + length <= data.count else {
            throw MidiDrumChartParserError.invalidTrackChunk
        }
        let range = offset..<(offset + length)
        offset += length
        return data.subdata(in: range)
    }

    mutating func skip(_ count: Int) throws {
        guard count >= 0, offset + count <= data.count else {
            throw MidiDrumChartParserError.invalidTrackChunk
        }
        offset += count
    }
}
