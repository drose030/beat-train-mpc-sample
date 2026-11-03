#if canImport(FoundationEssentials)
import FoundationEssentials  // no ICU: keeps the static Linux binary small
#else
import Foundation
#endif

enum ChartDrumChartParserError: Error, LocalizedError {
    case invalidFormat(String)

    var errorDescription: String? {
        switch self {
        case let .invalidFormat(reason):
            return "Invalid .chart format: \(reason)"
        }
    }
}

/// Parses Clone-Hero-style `.chart` text into a `DrumChart`. Operates on in-memory
/// `Data` (text decoding is part of the format and stays here); file reading is
/// `DrumChartLoader`'s job. Tick↔seconds lives in `TempoMap`, drum-colour placement
/// in `DrumTargetMap`. A chart with no `[SyncTrack]` tempo data is untimeable and
/// surfaces as `TempoMap.Failure.noTempo`.
enum ChartDrumChartParser {
    static func parse(data: Data, difficulty: DrumDifficulty) throws -> DrumChart {
        let parsed = try parseSections(data: data)
        let tempoMap = try TempoMap(ppq: parsed.resolution, changes: parsed.tempoChanges)

        let sectionName = "\(difficulty.chartSectionPrefix)Drums"
        let rawNotes = parsed.noteEventsBySection[sectionName] ?? []
        let notes = rawNotes.compactMap { event -> DrumNoteEvent? in
            guard let target = mapTarget(fromChartNote: event.noteNumber) else { return nil }
            return DrumNoteEvent(
                tick: event.tick,
                timeSec: tempoMap.seconds(forTick: event.tick),
                target: target,
                velocity: 100
            )
        }

        return DrumChart(tempoMap: tempoMap, notes: notes)
    }

    /// Difficulties that contain drum notes. Parses the sections once; requires a
    /// usable tempo map (an untimeable chart yields no playable difficulties).
    static func availableDifficulties(data: Data) throws -> [DrumDifficulty] {
        let parsed = try parseSections(data: data)
        _ = try TempoMap(ppq: parsed.resolution, changes: parsed.tempoChanges)
        return DrumDifficulty.allCases.filter { difficulty in
            let sectionName = "\(difficulty.chartSectionPrefix)Drums"
            guard let events = parsed.noteEventsBySection[sectionName], !events.isEmpty else { return false }
            return events.contains(where: { mapTarget(fromChartNote: $0.noteNumber) != nil })
        }
    }
}

private extension ChartDrumChartParser {
    struct ParsedChartSections {
        let resolution: Int
        let tempoChanges: [(tick: Int, bpm: Double)]
        let noteEventsBySection: [String: [ChartNoteEvent]]
    }

    struct ChartNoteEvent {
        let tick: Int
        let noteNumber: Int
    }

    static func parseSections(data: Data) throws -> ParsedChartSections {
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? String(data: data, encoding: .windowsCP1252)
        else {
            throw ChartDrumChartParserError.invalidFormat("Unable to decode text.")
        }

        let normalized = text
            .replacing("\r\n", with: "\n")
            .replacing("\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var currentSection: String?
        var inBody = false
        var resolution = 192
        var tempoChanges: [(tick: Int, bpm: Double)] = []
        var noteEventsBySection: [String: [ChartNoteEvent]] = [:]

        for rawLine in lines {
            let line = rawLine.trimmed()
            if line.isEmpty || line.hasPrefix("//") { continue }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                currentSection = String(line.dropFirst().dropLast())
                inBody = false
                continue
            }

            if line == "{" {
                inBody = true
                continue
            }

            if line == "}" {
                inBody = false
                continue
            }

            guard inBody, let section = currentSection else { continue }

            if section == "Song" {
                if let resolutionValue = parseSongResolution(from: line) {
                    resolution = max(1, resolutionValue)
                }
                continue
            }

            if section == "SyncTrack" {
                if let event = parseSyncEvent(from: line) {
                    tempoChanges.append(event)
                }
                continue
            }

            if section.hasSuffix("Drums"), let noteEvent = parseNoteEvent(from: line) {
                noteEventsBySection[section, default: []].append(noteEvent)
            }
        }

        return ParsedChartSections(
            resolution: resolution,
            tempoChanges: tempoChanges,
            noteEventsBySection: noteEventsBySection
        )
    }

    static func parseSongResolution(from line: String) -> Int? {
        let parts = line.components(separatedBy: "=")
        guard parts.count == 2 else { return nil }
        let key = parts[0].trimmed().lowercased()
        guard key == "resolution" else { return nil }
        return Int(parts[1].trimmed())
    }

    static func parseSyncEvent(from line: String) -> (tick: Int, bpm: Double)? {
        let sides = line.components(separatedBy: "=")
        guard sides.count == 2 else { return nil }
        guard let tick = Int(sides[0].trimmed()) else { return nil }
        let rhs = sides[1].trimmed()
        let tokens = rhs.split(separator: " ")
        guard tokens.count >= 2, tokens[0] == "B", let bpmTimesThousand = Double(tokens[1]) else { return nil }
        return (tick: tick, bpm: bpmTimesThousand / 1000.0)
    }

    static func parseNoteEvent(from line: String) -> ChartNoteEvent? {
        let sides = line.components(separatedBy: "=")
        guard sides.count == 2 else { return nil }
        guard let tick = Int(sides[0].trimmed()) else { return nil }
        let rhs = sides[1].trimmed()
        let tokens = rhs.split(separator: " ")
        guard tokens.count >= 3, tokens[0] == "N", let noteNumber = Int(tokens[1]) else { return nil }
        return ChartNoteEvent(tick: tick, noteNumber: noteNumber)
    }

    /// Translates a raw `.chart` drum note to a canonical drum lane (note 32 is the
    /// expert+ kick alias) and looks up its target in `DrumTargetMap`.
    static func mapTarget(fromChartNote note: Int) -> DrumTarget? {
        if note == 32 { return DrumTargetMap.target(forCanonicalLane: 0) }
        return DrumTargetMap.target(forCanonicalLane: note)
    }
}

private extension DrumDifficulty {
    var chartSectionPrefix: String {
        switch self {
        case .easy: return "Easy"
        case .medium: return "Medium"
        case .hard: return "Hard"
        case .expert: return "Expert"
        }
    }
}
