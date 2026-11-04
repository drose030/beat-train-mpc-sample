#if canImport(FoundationEssentials)
import FoundationEssentials  // no ICU: keeps the static Linux binary small
#else
import Foundation
#endif
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

/// Finds the songs below a folder: every folder with a `song.ini`, read into
/// `SongMetadata`. The file-I/O counterpart of `SongINIParser`.
public enum SongLibrary {
    /// All songs below `root` that have a chart, sorted by artist, then title.
    public static func scan(root: URL) -> [SongMetadata] {
        var songs: [SongMetadata] = []
        for url in iniFiles(below: root.path, depth: 0) {
            if let song = song(atINI: url), song.notesURL != nil {
                songs.append(song)
            }
        }
        return songs.sorted {
            ($0.artist.lowercased(), $0.title.lowercased()) < ($1.artist.lowercased(), $1.title.lowercased())
        }
    }

    /// Every `song.ini` below `path`, skipping hidden entries. The depth limit
    /// stops symlink loops.
    private static func iniFiles(below path: String, depth: Int) -> [URL] {
        guard depth < 12, let names = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            return []
        }
        var found: [URL] = []
        for name in names.sorted() where !name.hasPrefix(".") {
            let child = path + "/" + name
            if isDirectory(atPath: child) {
                found += iniFiles(below: child, depth: depth + 1)
            } else if name.lowercased() == "song.ini" {
                found.append(URL(fileURLWithPath: child))
            }
        }
        return found
    }

    /// Whether `path` is a directory (following symlinks).
    public static func isDirectory(atPath path: String) -> Bool {
        var info = stat()
        return stat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
    }

    static func song(atINI iniURL: URL) -> SongMetadata? {
        guard
            let data = try? Data(contentsOf: iniURL),
            let text = SongINIParser.decodeText(from: data)
        else {
            return nil
        }

        let folderURL = iniURL.deletingLastPathComponent()
        let parsed = SongINIParser.parse(iniText: text)
        return SongMetadata(
            id: folderURL.path,
            title: parsed.title ?? folderURL.lastPathComponent,
            artist: parsed.artist ?? "Unknown Artist",
            album: parsed.album,
            hasDrumTrack: parsed.hasProDrums || parsed.drumDifficulty != nil,
            drumDifficulty: parsed.drumDifficulty,
            hasProDrums: parsed.hasProDrums,
            chartDelayMilliseconds: parsed.chartDelayMilliseconds,
            songFolderURL: folderURL,
            notesURL: firstExisting(["notes.mid", "notes.midi", "notes.chart"], in: folderURL),
            audioURL: firstExisting(["song.mp3", "song.ogg", "song.wav", "guitar.mp3", "guitar.ogg", "guitar.wav", "rhythm.mp3", "rhythm.ogg", "rhythm.wav"], in: folderURL)
        )
    }

    private static func firstExisting(_ names: [String], in folder: URL) -> URL? {
        names.lazy
            .map { folder.appendingPathComponent($0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
