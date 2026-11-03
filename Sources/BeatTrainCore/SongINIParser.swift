#if canImport(FoundationEssentials)
import FoundationEssentials  // no ICU: keeps the static Linux binary small
#else
import Foundation
#endif

/// The metadata fields read from a `song.ini`. Defaults that need the folder name
/// (title, artist) are applied by the caller, so these stay optional.
struct ParsedSongINI: Equatable {
    let title: String?
    let artist: String?
    let album: String?
    let drumDifficulty: Int?
    let hasProDrums: Bool
    let chartDelayMilliseconds: Double
}

/// Pure `song.ini` parsing: text → metadata fields, with no file I/O, so it is
/// testable on string literals. Byte→text decoding (which needs `Data`) is kept to
/// the thin `decodeText(from:)` step; the structure-scoring it relies on is pure.
enum SongINIParser {
    static func parse(iniText text: String) -> ParsedSongINI {
        let normalized = text
            .replacing("\u{FEFF}", with: "")
            .replacing("\r\n", with: "\n")
            .replacing("\r", with: "\n")

        var values: [String: String] = [:]
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmed()
            if trimmed.isEmpty || trimmed.hasPrefix(";") || trimmed.hasPrefix("#") || trimmed.hasPrefix("[") {
                continue
            }
            guard let equalIndex = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<equalIndex].trimmed().lowercased()
            let rawValue = trimmed[trimmed.index(after: equalIndex)...].trimmed()
            values[key] = unquote(rawValue)
        }

        return ParsedSongINI(
            title: firstNonEmpty(values["name"]),
            artist: firstNonEmpty(values["artist"]),
            album: firstNonEmpty(values["album"]),
            drumDifficulty: Int(values["diff_drums"] ?? ""),
            hasProDrums: (values["pro_drums"] ?? "").lowercased() == "true",
            chartDelayMilliseconds: Double(values["delay"] ?? "") ?? 0
        )
    }

    /// Picks the most plausible decoding of raw `song.ini` bytes by scoring each
    /// candidate encoding against INI structure.
    static func decodeText(from data: Data) -> String? {
        let encodings: [String.Encoding] = [
            .utf8, .utf16LittleEndian, .utf16BigEndian, .utf16, .isoLatin1,
        ]
        let candidates = encodings.map { String(data: data, encoding: $0) } + [decodeWindows1252(data)]
        var bestText: String?
        var bestScore = Int.min
        for candidate in candidates {
            if let text = candidate, !text.isEmpty {
                let score = decodeScore(text)
                if score > bestScore {
                    bestScore = score
                    bestText = text
                }
            }
        }
        return bestText
    }

    /// Windows-1252 by hand: FoundationEssentials (the Linux build) cannot decode it.
    static func decodeWindows1252(_ data: Data) -> String {
        // 0x80–0x9F; the rest is Latin-1. Unassigned bytes stay control characters.
        let high: [UInt32] = [
            0x20AC, 0x81, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
            0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x8D, 0x017D, 0x8F,
            0x90, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
            0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x9D, 0x017E, 0x0178,
        ]
        var text = String.UnicodeScalarView()
        for byte in data {
            let value = (0x80...0x9F).contains(byte) ? high[Int(byte) - 0x80] : UInt32(byte)
            text.append(Unicode.Scalar(value)!)
        }
        return String(text)
    }

    /// Heuristic plausibility of a decoded `song.ini`: rewards `key = value` lines and
    /// expected keywords, penalises control characters from a wrong encoding.
    static func decodeScore(_ text: String) -> Int {
        let lower = text.lowercased()
        let lines = lower.split(separator: "\n", omittingEmptySubsequences: false)

        let equalCount = lines.reduce(into: 0) { partialResult, line in
            if line.contains("=") { partialResult += 1 }
        }

        var keywordScore = 0
        if lower.contains("[song]") { keywordScore += 40 }
        if lower.contains("name") { keywordScore += 20 }
        if lower.contains("artist") { keywordScore += 20 }
        if lower.contains("album") { keywordScore += 20 }

        let controlPenalty = lower.unicodeScalars.reduce(into: 0) { partialResult, scalar in
            if scalar.value < 9 || (scalar.value > 13 && scalar.value < 32) || (0x80...0x9F).contains(scalar.value) {
                partialResult += 1
            }
        } * 3

        return (equalCount * 10) + keywordScore - controlPenalty
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        if value.hasPrefix("\""), value.hasSuffix("\"") {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    private static func firstNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmed()
        return trimmed.isEmpty ? nil : trimmed
    }
}
