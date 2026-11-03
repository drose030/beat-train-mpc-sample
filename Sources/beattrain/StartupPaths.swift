import BeatTrainCore
#if canImport(FoundationEssentials)
import FoundationEssentials  // no ICU: keeps the static Linux binary small
#else
import Foundation
#endif

/// Where things are on the device when Beat-Train starts: the song folders and
/// the settings file.
enum StartupPaths {
    /// Song folders to scan: `--songs` arguments, else `$BEATTRAIN_SONGS` plus
    /// `BeatTrain/Songs` (or `Songs`) on every card mounted below `mediaRoot`.
    static func songRoots(arguments: [String], environmentSongs: String?, mediaRoot: String = "/media") -> [String] {
        var roots: [String] = []
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            if argument == "--songs", let path = iterator.next() { roots.append(path) }
        }
        if !roots.isEmpty { return roots }
        if let environmentSongs { roots.append(environmentSongs) }
        let cards = (try? FileManager.default.contentsOfDirectory(atPath: mediaRoot)) ?? []
        for card in cards.sorted() {
            for sub in ["BeatTrain/Songs", "Songs"] {
                let path = "\(mediaRoot)/\(card)/\(sub)"
                if SongLibrary.isDirectory(atPath: path) { roots.append(path) }
            }
        }
        return roots
    }

    /// `settings.json` in the `BeatTrain` folder of the first song folder's card:
    /// next to `BeatTrain/Songs`, or in a new `BeatTrain` folder beside `Songs`.
    static func settingsURL(for roots: [String]) -> URL? {
        guard let first = roots.first else { return nil }
        let parent = URL(fileURLWithPath: first).deletingLastPathComponent()
        let folder = parent.lastPathComponent == "BeatTrain" ? parent : parent.appendingPathComponent("BeatTrain")
        return folder.appendingPathComponent("settings.json")
    }
}
