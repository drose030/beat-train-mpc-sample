/// One audio file of a song folder: the whole song, or one part of it. The
/// original game's stems, in its order; all present ones play together.
public enum Stem: String, CaseIterable, Sendable {
    case song, drums, guitar, bass, rhythm, vocals, keys, crowd
}
