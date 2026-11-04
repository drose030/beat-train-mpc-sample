#if canImport(FoundationEssentials)
import FoundationEssentials  // no ICU: keeps the static Linux binary small
#else
import Foundation
#endif

public struct SongMetadata: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let artist: String
    public let album: String?
    public let hasDrumTrack: Bool
    public let drumDifficulty: Int?
    public let hasProDrums: Bool
    public let chartDelayMilliseconds: Double
    public let songFolderURL: URL
    public let notesURL: URL?
    public let audioURL: URL?
}

extension SongMetadata {
    var albumArtURL: URL? {
        let candidates = ["album.jpg", "album.jpeg", "album.png", "cover.jpg", "cover.jpeg", "cover.png"]
        for name in candidates {
            let url = songFolderURL.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }
}

