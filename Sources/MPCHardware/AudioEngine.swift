import CMPCHardware

/// Song playback on the MPC Sample's audio output: MP3, Ogg Vorbis or WAV stems
/// mixed in a real-time thread, plus one-shot effects, with a clock of what is
/// actually heard.
public final class AudioEngine {
    private let handle: OpaquePointer

    /// Opens the playback device (the one the stock app uses).
    public init() throws {
        var message = [CChar](repeating: 0, count: 256)
        guard let handle = cmpc_audio_open(&message, message.count) else {
            throw HardwareError.notFound("audio: " + Self.string(message))
        }
        self.handle = handle
    }

    /// An engine without a device: `render` mixes on demand. For tests.
    public init(offlineRate rate: UInt32) {
        handle = cmpc_audio_open_offline(rate)
    }

    deinit {
        cmpc_audio_close(handle)
    }

    public var setup: String {
        String(cString: cmpc_audio_describe(handle))
    }

    /// Adds a stem, the bytes of an MP3, Ogg Vorbis or WAV file, to the song;
    /// returns its index for `setGain`.
    @discardableResult
    public func addStem(encoded: [UInt8]) throws -> Int {
        var message = [CChar](repeating: 0, count: 128)
        let index = encoded.withUnsafeBufferPointer { cmpc_audio_add_stem(handle, $0.baseAddress, $0.count, &message, message.count) }
        guard index >= 0 else { throw HardwareError.notFound("stem: " + Self.string(message)) }
        return Int(index)
    }

    /// Stops and removes the song; the position goes back to 0.
    public func clearStems() {
        cmpc_audio_clear_stems(handle)
    }

    public func setGain(_ gain: Float, forStem stem: Int) {
        cmpc_audio_set_stem_gain(handle, Int32(stem), gain)
    }

    /// Stops and puts the song back to its start, keeping the stems loaded.
    public func rewind() {
        cmpc_audio_rewind(handle)
    }

    public func play() {
        cmpc_audio_play(handle)
    }

    public func pause() {
        cmpc_audio_pause(handle)
    }

    /// Seconds of the song heard so far.
    public var position: Double {
        cmpc_audio_position(handle)
    }

    /// Since the last call: device underruns (heard as clicks), and the average and
    /// longest time mixing one device period took, in seconds.
    public func takeStats() -> (underruns: Int, mixAverage: Double, mixLongest: Double) {
        var underruns: UInt32 = 0
        var average = 0.0, longest = 0.0
        cmpc_audio_take_stats(handle, &underruns, &average, &longest)
        return (Int(underruns), average, longest)
    }

    /// Song speed, 0.5–1, at the same pitch. `position` counts song seconds, so
    /// it runs slower too.
    public var speed: Double {
        get { cmpc_audio_speed(handle) }
        set { cmpc_audio_set_speed(handle, newValue) }
    }

    /// Length of the longest stem, in seconds.
    public var duration: Double {
        cmpc_audio_duration(handle)
    }

    /// True once every stem has played to its end.
    public var isFinished: Bool {
        cmpc_audio_finished(handle) != 0
    }

    /// How many one-shot effects (miss sound, click…) can be loaded at once.
    public static let effectSlots = Int(CMPC_AUDIO_EFFECT_SLOTS)

    /// Decodes an MP3, Ogg Vorbis or WAV file's bytes into effect slot `slot`.
    public func loadEffect(slot: Int, encoded: [UInt8]) throws {
        let rc = encoded.withUnsafeBufferPointer { cmpc_audio_load_effect(handle, Int32(slot), $0.baseAddress, $0.count) }
        guard rc == 0 else { throw HardwareError.notFound("effect: not a playable MP3, Ogg Vorbis or WAV") }
    }

    /// Puts mono samples (at `rate` Hz) into effect slot `slot`.
    public func loadEffect(slot: Int, samples: [Float], rate: UInt32) throws {
        let rc = samples.withUnsafeBufferPointer { cmpc_audio_load_effect_samples(handle, Int32(slot), $0.baseAddress, $0.count, rate) }
        guard rc == 0 else { throw HardwareError.notFound("effect: no samples") }
    }

    public func setEffectGain(_ gain: Float, slot: Int) {
        cmpc_audio_set_effect_gain(handle, Int32(slot), gain)
    }

    public func triggerEffect(slot: Int) {
        cmpc_audio_trigger_effect(handle, Int32(slot))
    }

    /// Plays an effect when the song reaches `songTime` seconds, to the sample.
    public func scheduleEffect(slot: Int, atSongTime songTime: Double) {
        cmpc_audio_schedule_effect(handle, Int32(slot), songTime)
    }

    /// Overall gain, 0–1 (the MAIN VOLUME knob; the device has no hardware volume).
    public func setMaster(_ gain: Float) {
        cmpc_audio_set_master(handle, gain)
    }

    /// Mixes `frames` stereo frames (offline engines only).
    public func render(frames: Int) -> [Float] {
        var out = [Float](repeating: 0, count: frames * 2)
        out.withUnsafeMutableBufferPointer { cmpc_audio_render(handle, $0.baseAddress, frames) }
        return out
    }

    private static func string(_ chars: [CChar]) -> String {
        String(decoding: chars.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
