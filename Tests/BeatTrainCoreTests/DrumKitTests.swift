import Testing
@testable import BeatTrainCore

struct DrumVoiceTests {

    @Test func canonicalTargetRoundTrips() {
        for voice in DrumVoice.allCases {
            guard let target = voice.canonicalTarget else {
                #expect(voice == .off)
                continue
            }
            #expect(DrumVoice(canonicalTarget: target) == voice)
        }
    }

    @Test func offHasNoCanonicalTarget() {
        #expect(DrumVoice.off.canonicalTarget == nil)
    }

    @Test func unmappedTargetHasNoVoice() {
        // (1, .bottom) is a layout slot but not a canonical voice position.
        #expect(DrumVoice(canonicalTarget: DrumTarget(lane: 1, row: .bottom)) == nil)
    }
}

struct DrumKitTests {

    @Test func padLayoutRoundTrips() {
        for pad in 0..<DrumKit.padCount {
            let target = DrumKit.layoutTarget(forPad: pad)
            #expect(DrumKit.pad(forLayout: target) == pad)
        }
    }

    @Test func defaultKitLeavesCanonicalTargetsUnchanged() {
        let kit = DrumKit()
        for voice in DrumVoice.allCases {
            guard let canonical = voice.canonicalTarget else { continue }
            #expect(kit.target(remapping: canonical) == canonical)
        }
    }

    @Test func offPadProducesNoLane() {
        let kit = DrumKit() // pads 1 and 2 are .off by default
        #expect(kit.lane(forPad: 1) == nil)
        #expect(kit.lane(forPad: 2) == nil)
    }

    @Test func voicedPadResolvesToItsLane() {
        let kit = DrumKit()
        // pad 0 = kick → lane 0, pad 4 = red → lane 0, pad 5 = yellow → lane 1
        #expect(kit.lane(forPad: 0) == 0)
        #expect(kit.lane(forPad: 4) == 0)
        #expect(kit.lane(forPad: 5) == 1)
        #expect(kit.lane(forPad: 7) == 3) // orange
    }

    @Test func reassigningPadMovesTheVoice() {
        // Player moves "red" from its default pad 4 to pad 6 (layout lane 2).
        var voices = DrumKit.defaultPadVoices
        voices[4] = .off
        voices[6] = .red
        let kit = DrumKit(padVoices: voices)

        // A chart's canonical red note (lane 0, top) now lands on lane 2.
        let red = DrumTarget(lane: 0, row: .top)
        #expect(kit.target(remapping: red).lane == 2)
        #expect(kit.lane(forPad: 6) == 2)
    }

    @Test func customNoteToPadIsHonored() {
        // Note 60 isn't in the default GM/PadMapper map; bind it to pad 0 (kick).
        let kit = DrumKit(noteToPad: [60: 0])
        #expect(kit.lane(forNote: 60) == 0)
        #expect(kit.voice(forNote: 60) == .kick)
    }

    @Test func generalMidiFallbackForUnmappedNotes() {
        // Empty noteToPad falls back to PadMapper.defaultNoteToPad; a note outside
        // both still resolves via the GM percussion fallback (38 = snare → lane 1).
        let kit = DrumKit(noteToPad: [255: 0]) // 255 maps; 38 does not → GM fallback
        #expect(kit.lane(forNote: 38) == 1)
    }

    @Test func voiceOnTwoPadsLandsOnTheLowestPad() {
        var voices = DrumKit.defaultPadVoices
        voices[1] = .yellow   // also on pad 5
        let kit = DrumKit(padVoices: voices)
        for _ in 0..<20 {
            #expect(kit.pad(forVoice: .yellow) == 1)
        }
        #expect(kit.target(remapping: DrumTarget(lane: 1, row: .top)) == DrumTarget(lane: 1, row: .bottom))
    }
}
