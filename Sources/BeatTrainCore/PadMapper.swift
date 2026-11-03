#if canImport(FoundationEssentials)
import FoundationEssentials  // no ICU: keeps the static Linux binary small
#else
import Foundation
#endif

public struct PadMapper: Sendable {
    private let noteToPad: [UInt8: Int]

    init(noteToPad: [UInt8: Int]) {
        self.noteToPad = noteToPad
    }

    public static let defaultNoteToPad: [UInt8: Int] = Dictionary(
        uniqueKeysWithValues: zip(UInt8(36)...UInt8(51), 0...15)
    )

    static let `default` = PadMapper(noteToPad: defaultNoteToPad)

    func padIndex(for note: UInt8) -> Int? {
        noteToPad[note]
    }
}

