import Foundation
import Testing
@testable import BeatTrainCore

struct SongINIParserTests {

    @Test func parsesStandardFields() {
        let parsed = SongINIParser.parse(iniText: """
        [Song]
        name = Through the Fire and Flames
        artist = DragonForce
        album = Inhuman Rampage
        diff_drums = 6
        pro_drums = True
        delay = 250
        """)
        #expect(parsed.title == "Through the Fire and Flames")
        #expect(parsed.artist == "DragonForce")
        #expect(parsed.album == "Inhuman Rampage")
        #expect(parsed.drumDifficulty == 6)
        #expect(parsed.hasProDrums == true)
        #expect(parsed.chartDelayMilliseconds == 250)
    }

    @Test func stripsQuotesAndComments() {
        let parsed = SongINIParser.parse(iniText: """
        ; a comment
        # another comment
        name = "Quoted Title"
        artist = Some Band
        """)
        #expect(parsed.title == "Quoted Title")
        #expect(parsed.artist == "Some Band")
    }

    @Test func missingFieldsAreNilOrDefault() {
        let parsed = SongINIParser.parse(iniText: "[Song]\nname = Only Name")
        #expect(parsed.title == "Only Name")
        #expect(parsed.artist == nil)        // caller applies "Unknown Artist"
        #expect(parsed.album == nil)
        #expect(parsed.drumDifficulty == nil)
        #expect(parsed.hasProDrums == false)
        #expect(parsed.chartDelayMilliseconds == 0)
    }

    @Test func emptyValueTreatedAsMissing() {
        let parsed = SongINIParser.parse(iniText: "name =    \nartist = Band")
        #expect(parsed.title == nil)
        #expect(parsed.artist == "Band")
    }

    @Test func decodesUTF8DataOverGarbledEncodings() {
        let data = Data("[Song]\nname = Café\nartist = Beat\n".utf8)
        let text = SongINIParser.decodeText(from: data)
        #expect(text != nil)
        #expect(SongINIParser.parse(iniText: text ?? "").title == "Café")
    }

    @Test func decodesWindows1252() {
        // "Don’t Stop €" with the cp1252 quote (0x92) and euro sign (0x80).
        let data = Data("[Song]\nname = Don".utf8) + Data([0x92]) + Data("t Stop ".utf8) + Data([0x80])
            + Data("\nartist = Beat\n".utf8)
        let text = SongINIParser.decodeText(from: data)
        #expect(SongINIParser.parse(iniText: text ?? "").title == "Don\u{2019}t Stop \u{20AC}")
    }
}
