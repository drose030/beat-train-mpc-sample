# Development

Building, packaging, testing and how Beat-Train runs on the MPC Sample. For
installing and playing, see the [README](../README.md).

Firmware: built for MPC Sample **1.3.0.12** (the autorun checksum salt and the
panel protocol come from that version). Domain terms are in
[CONTEXT.md](../CONTEXT.md), decisions in [adr/](adr/).

## Layout

| Path | What |
|---|---|
| `Sources/BeatTrainCore` | Game logic, copied from the original Beat-Train code and since diverged (see ADR-0001; FoundationEssentials on Linux, Foundation on Apple platforms): parsers, TempoMap, DrumKit, hit judging, GameSession, SongLibrary, PlayerSettings |
| `Sources/MPCHardware` | Display (DRM/KMS), control surface (rawmidi), audio engine, canvas and 5×7 font |
| `Sources/CMPCHardware` | C: DRM and rawmidi ioctls, the audio engine (ALSA PCM without alsa-lib, stem mixer), decoders: [minimp3](https://github.com/lieff/minimp3) (CC0, in `minimp3/`), [stb_vorbis](https://github.com/nothings/stb) (public domain or MIT, in `stb_vorbis/`), WAV in `decoder.c` |
| `Sources/beattrain` | The game: screens and input (`BeatTrainApp`, `Screens`), song playback and clock (`SongPlayback`), settings and knobs (`SettingsKeeper`), panel pad numbering and lights (`PanelPads`), start picture, quit and power-off (`Lifecycle`) — see `CONTEXT.md` |
| `Sources/beattrain-hwtest` | Hardware test program |
| `packaging/autorun` | The SD-card autorun scripts |
| `packaging/images` | The two splash screens, 320×240 binary PPM (the game reads them without an image decoder) |
| `scripts/` | Linux cross-build and packaging |

## Build

Tests, previews of the screens and a chart check run on the Mac:

```bash
swift test
swift run beattrain --songs path/to/Songs --preview /tmp/preview   # PPM per screen
swift run beattrain --songs path/to/Songs --list                   # charts per song
swift run beattrain --songs path/to/Songs --demo /tmp/demo        # frames for the README's GIFs
```

The MPC build needs Docker running. It builds a static aarch64 Linux binary in
the official `swift:6.4.2` container (Xcode's compiler cannot use the Static
Linux SDK). On Linux the code imports only `FoundationEssentials`, not
`Foundation`: full Foundation links ICU's 34 MB of locale data, so the binary
would be 55 MB instead of 11 MB. Use stdlib or libc where Essentials lacks
something (`trimmed()` in BeatTrainCore, `stat`, `fsync`):

```bash
SONGS_DIR=path/to/Songs scripts/package-autorun.sh
```

This writes `dist/card/` (what goes on the card: `autorun/` and
`BeatTrain/Songs/`), the same as `dist/beattrain-card.zip` for the lab, and
`dist/beattrain-mpc-sample.zip`, the release download: `autorun/` and an empty
`BeatTrain/Songs/`, never songs. `SONGS_CHARTS_ONLY=1`
copies only `song.ini`, charts and album art (small, for the lab).
`scripts/package-autorun.sh beattrain-hwtest` packages the hardware test instead.

## Gameplay details

The rules behind the README's short version.

K1–K3 move their setting by how far they turn (the MPC does not report knob
positions at start, so a saved value would otherwise jump to the knob). Outside
a song the bottom line names them, and K2 and K3 sound the level they set;
over a running song they stay silent.

**Settings** (B2 in the song list): timing offset, hit window and its early part
(the original game's settings), metronome and miss sound volume, and a volume per
stem. Turn the encoder to pick a line, push to edit it, turn to change it, push
or STOP when done; ERASE or B1 puts the line back to its default; STOP or B3 returns
and saves. The metronome clicks on the song's beats (the chart's beat grid), placed
to the sample by the audio thread.

**Pad setup** (B3 in the song list): hit one of pads 1–8 to select it, turn the
encoder to choose its sound (kick, snare, hi-hat, tom, cymbal, floor tom, off),
ERASE or B1 goes back to the defaults, STOP or B3 returns and saves. As in the original
game, a sound's notes fall in the lane of the pad that plays it; a sound on two
pads plays on both, its notes fall over the lower-numbered one. A hit counts
only for notes of its own pad row: kick (pad 5) and snare (pad 1) share lane 1
but not their notes (the original game judges by lane alone).

After the last note the music plays on to its end ("SONG END" on the highway),
then the results come; STOP shows them at once.

The pads light in their drum colour and flash when struck. The two rows are
swapped against the original game (snare row at the bottom); the highway draws each
note's upper half for the upper pad row. Hit window and pad assignment are the
original defaults (120 ms, 50 ms early). All settings are saved in
`BeatTrain/settings.json` on the card: when leaving the settings or pad setup,
2 s after the last change, and on every way out. The game clock is the
audio actually heard (the device's buffer delay is taken out), also for songs
without stems, so the timing offset starts at 0; turn K1 if hits feel early or
late.

## Test in the lab

[virtual-mpc-sample](https://github.com/orrpunk-art/virtual-mpc-sample) runs the
stock firmware in QEMU with a browser panel. It needs the firmware partitions;
`scripts/extract-az0x.py` unpacks them from the `Update.img` inside Akai's
"MPC Sample 1.3.0 Updater.app" (the lab's `inputs.sha256` checks the result):

```bash
python3 scripts/extract-az0x.py "MPC Sample 1.3.0 Updater.app/Contents/Resources/Update.img" ../virtual-mpc-sample/firmware
```

Then, in the lab folder: `python3 lab.py build`, `python3 lab.py run`, and with the
stock app up:

```bash
python3 lab.py autorun path/to/beat-train-mpc-sample/dist/beattrain-card.zip --no-reboot
```

Press **F1** in the panel page (B1, "Start"). Use `--no-reboot`: after a reboot
the firmware shows no question, and the lab waits for the stock app, which
Beat-Train has stopped (it resets the VM after 4 min). In the hardware test,
`BEATTRAIN_TRACE=1` logs the raw panel bytes to the session log.

## How it runs

`autorun.sh` (run as root by the firmware's script runner) copies the binary to
`/run/beattrain` (RAM, the card is mounted `noexec`), checks its SHA-256 and
starts the transient unit `beattrain.service`. `session.sh` in that unit stops
`ac50.service` (the stock app), runs Beat-Train, and the unit's `ExecStopPost`
starts `ac50.service` again, also after a crash. The power key is the RK817
PMIC's input device (`rk805-pwrkey`; gpio-keys in the lab), found, as libinput
does for the stock app, by its KEY_POWER capability. After YES on it the
app exits with code 10; `session.sh` copies the log to the card and runs
`systemctl poweroff`, as the stock app powers off itself.

The stock app switches the Control Surface rawmidi to timestamped framing, and
that setting survives its exit; `ControlSurface` sets plain byte mode on open.

Audio opens the PCM the stock app uses (`/dev/snd/by-path/platform-sound`) with
its setup, 4 channels S32_LE 44.1 kHz (outputs 1-2 and 3-4 get the same mix). A
real-time thread decodes the stems from memory, resamples them to 44.1 kHz and
mixes them; MAIN VOLUME is applied in software, as by the stock app. The
resampler is a 32-tap windowed sinc (Kaiser) with its cutoff at the lower of
the two rates, so 48 kHz stems do not alias; 44.1 kHz stems pass through. Sound
effects (miss, click) go through the same filter and the same decoders. The
format comes from the first bytes (`OggS`, `RIFF…WAVE`, else MP3); a stem
named in several formats is taken as `.mp3`, then `.ogg`, then `.wav`. WAV:
8/16/24/32-bit PCM and 32/64-bit float, also as WAVE_FORMAT_EXTENSIBLE; past
two channels only the first two play. The whole file stays in RAM.
In the lab, a 6-stem 48 kHz song: MP3 ~2 % CPU and 55 MB RAM, Ogg Vorbis
~2.4 % of one core and 117 MB RAM (the Ogg files are twice the size).

## Sources

- [virtual-mpc-sample](https://github.com/orrpunk-art/virtual-mpc-sample): hardware map, panel protocol, autorun format, QEMU lab
- [mpc-sample-root-ssh](https://github.com/orrpunk-art/mpc-sample-root-ssh): a hardware-validated autorun package
