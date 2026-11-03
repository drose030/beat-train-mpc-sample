import Foundation
import Testing
@testable import BeatTrainCore

struct SongLibraryTests {
    private func makeSong(_ root: URL, folder: String, ini: String, chart: String?) throws {
        let dir = root.appendingPathComponent(folder)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(ini.utf8).write(to: dir.appendingPathComponent("song.ini"))
        if let chart {
            try Data().write(to: dir.appendingPathComponent(chart))
        }
    }

    @Test func findsSongsWithChartsSortedByArtistThenTitle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("songlib-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try makeSong(root, folder: "b", ini: "[song]\nname = Zeta\nartist = Alpha\n", chart: "notes.mid")
        try makeSong(root, folder: "pack/a", ini: "[song]\nname = Beta\nartist = alpha\ndelay = 120\n", chart: "notes.chart")
        try makeSong(root, folder: "c", ini: "[song]\nname = Gamma\nartist = Aardvark\n", chart: "notes.mid")
        try makeSong(root, folder: "nochart", ini: "[song]\nname = Silent\n", chart: nil)

        let songs = SongLibrary.scan(root: root)

        #expect(songs.map(\.title) == ["Gamma", "Beta", "Zeta"])
        #expect(songs[1].notesURL?.lastPathComponent == "notes.chart")
        #expect(songs[1].chartDelayMilliseconds == 120)
    }

    @Test func folderNameIsTheFallbackTitle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("songlib-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try makeSong(root, folder: "My Song", ini: "[song]\n", chart: "notes.mid")

        let songs = SongLibrary.scan(root: root)

        #expect(songs.first?.title == "My Song")
        #expect(songs.first?.artist == "Unknown Artist")
    }

    @Test func missingRootGivesNoSongs() {
        #expect(SongLibrary.scan(root: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")).isEmpty)
    }
}
