# Standalone Swift program started by SD-card autorun

Beat-Train runs on the MPC Sample as its own program, not as a mod inside the stock
app: an SD-card autorun package stops `ac50.service`, runs Beat-Train from `/run`, and
`ExecStopPost` brings the stock app back. It draws to the display with DRM/KMS dumb
buffers and reads the panel through the "Control Surface" rawmidi device, the same
interfaces the stock app uses.

The code stays in Swift so that `BeatTrainCore` (parsers, TempoMap, DrumKit, hit
judging, 58 tests) is reused from the original Beat-Train code unchanged. It is built with the Swift
Static Linux SDK into one static musl binary, so it does not depend on the device's
glibc or libraries. Only the platform layer (screen, input, audio) is new.

## Considered options

- **LD_PRELOAD mod in the stock app** (as SampQOL OS and AM Mod do): rejected; Beat-Train
  needs the whole screen and all pads, and hooking a closed binary ties us to one exact
  app build.
- **Rewrite in C/C++**: rejected; it throws away the tested core for no runtime gain.
- **Wait for Akai's announced SDK** (Oct 2026): not available yet. The platform layer is
  kept behind `MPCHardware`, so it can move to the SDK later.

## Consequences

- Tied to firmware 1.3.0.x until verified on others (runner salt, panel protocol).
- One autorun package per card: Beat-Train and SampQOL OS need separate cards. A
  boot menu such as mpc-boot-thingy can hold several (not tested with Beat-Train yet).
- Builds for the device need the swift.org toolchain (Docker container); Xcode's
  compiler cannot use the Static Linux SDK.

## Update 2026-11-03: the core is a copy, not shared

`BeatTrainCore` began as a copy of the original Beat-Train game's models, not as a
package both games use, and the two have diverged:

- Hit judging here matches lane and row (`DrumHitJudge.judgeInput(target:)`), so kick
  and snare no longer hit each other's notes. The original still matches the lane alone.
- The Linux build imports `FoundationEssentials` instead of `Foundation`.
- `GameSession`, `PlayerSettings`, `SongLibrary`, `SongINIParser` and
  `DrumChartLoader` exist only here.
- `MetronomeScheduler`, `HitEvent` and `HitEventRingBuffer` were unused here and
  were removed.

A fix in one copy does not reach the other. Making `BeatTrainCore` one Swift
package that both apps depend on is still open; until then, port fixes by hand.
