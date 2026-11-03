import Foundation
import Testing
@testable import beattrain

/// Song folders and the settings file at start, through `StartupPaths`.
struct StartupPathsTests {
    @Test func songsArgumentsWinOverEverythingElse() {
        let roots = StartupPaths.songRoots(arguments: ["beattrain", "--songs", "/a", "--songs", "/b"], environmentSongs: "/env",
                                           mediaRoot: "/nonexistent")
        #expect(roots == ["/a", "/b"])
    }

    @Test func cardsAreScannedForBeatTrainSongsAndSongs() throws {
        let media = FileManager.default.temporaryDirectory.appendingPathComponent("beattrain-media-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: media) }
        for folder in ["B/Songs", "A/BeatTrain/Songs", "C/Other"] {
            try FileManager.default.createDirectory(at: media.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        let roots = StartupPaths.songRoots(arguments: ["beattrain"], environmentSongs: "/env", mediaRoot: media.path)
        #expect(roots == ["/env", "\(media.path)/A/BeatTrain/Songs", "\(media.path)/B/Songs"])
    }

    @Test func settingsLiveInTheBeatTrainFolderOfTheFirstCard() {
        #expect(StartupPaths.settingsURL(for: ["/media/64GB/BeatTrain/Songs", "/x"])?.path == "/media/64GB/BeatTrain/settings.json")
        #expect(StartupPaths.settingsURL(for: ["/media/card/Songs"])?.path == "/media/card/BeatTrain/settings.json")
        #expect(StartupPaths.settingsURL(for: []) == nil)
    }
}
