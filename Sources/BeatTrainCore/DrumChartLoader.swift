#if canImport(FoundationEssentials)
import FoundationEssentials  // no ICU: keeps the static Linux binary small
#else
import Foundation
#endif

public enum DrumChartLoaderError: Error, LocalizedError {
    case unsupportedFormat(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedFormat(ext):
            return "Unsupported chart format: .\(ext)"
        }
    }
}

/// The single file-I/O boundary for chart parsing: reads the bytes off disk and
/// dispatches to the matching in-memory parser by file extension. The parsers
/// themselves never touch the filesystem, so they can be tested on literal inputs.
public enum DrumChartLoader {
    public static func availableDifficulties(from fileURL: URL) throws -> [DrumDifficulty] {
        let data = try Data(contentsOf: fileURL)
        switch fileURL.pathExtension.lowercased() {
        case "mid", "midi":
            return try MidiDrumChartParser.availableDifficulties(data: data)
        case "chart":
            return try ChartDrumChartParser.availableDifficulties(data: data)
        default:
            return []
        }
    }

    /// `proDrums` is song.ini's `pro_drums`; only `.chart` files need it (see
    /// `ChartDrumChartParser`), MIDI carries its own tom markers.
    public static func parse(from fileURL: URL, difficulty: DrumDifficulty, proDrums: Bool = false) throws -> DrumChart {
        let data = try Data(contentsOf: fileURL)
        switch fileURL.pathExtension.lowercased() {
        case "mid", "midi":
            return try MidiDrumChartParser.parse(data: data, difficulty: difficulty)
        case "chart":
            return try ChartDrumChartParser.parse(data: data, difficulty: difficulty, proDrums: proDrums)
        default:
            throw DrumChartLoaderError.unsupportedFormat(fileURL.pathExtension)
        }
    }
}
