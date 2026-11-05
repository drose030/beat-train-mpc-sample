# Beat-Train

A drum game: the player hits physical or virtual pads in time with a song's drum chart, scored against a scrolling note highway. Charts come from MIDI (`.mid`) or Clone-Hero-style text (`.chart`) files. This repo is its port to the Akai MPC Sample, with the game logic copied from the original Beat-Train code into `BeatTrainCore` (see ADR-0001).

## Language

### Chart domain

**DrumChart**:
The parsed, playable representation of one song at one difficulty — a `ppq`, a tempo map, and an ordered list of notes.

**Note** (`DrumNoteEvent`):
A single drum hit to be played, located at a `tick` and a derived `timeSec`, aimed at a **DrumTarget**.
_Avoid_: "hit" (that's the player's input), "event" (too generic).

**DrumTarget**:
Where a note lands on the kit — a **Lane** (0–3) plus a **Row** (top/bottom). The thing the player must strike.

**Lane**:
One of the 4 vertical columns of the note highway. Distinct from the 6 canonical drum colours.

**Row**:
Top or bottom half of a lane — encodes the 2-pad-per-lane play style.

**Stem group**:
The stems SHIFT+K1–K3 turn together: the `song` stem, the `drums`, and all the others. Changes the per-stem volumes in **PlayerSettings**, each stem keeping its distance to the rest of its group.

**Song speed**:
How fast the song plays, 50–100 %, for practising (SHIFT+FADER). Slower at the same pitch; chart time is song time, so the notes and the hit window slow down with it. Not saved; distinct from a song's tempo (**TempoMap**).

**Highway layout**:
How the note highway runs on the play screen: vertical (4 **Lanes**, notes come down, each note's halves are the two **Rows**), vertical by pad (one column per **Pad** the chart uses, in panel order) or horizontal (one row per **Pad** the chart uses, notes run right to left). A **PlayerSettings** value. Distinct from **Row**, which is part of a **DrumTarget**.

**Strike line**:
The line on the highway where a note is to be struck: chart time 0, notes to come on one side, passed ones on the other. Sits near the end the notes run to, or a quarter, a third or half way in (a **PlayerSettings** value, for both **Highway layouts**); further in shows more passed notes and less of what comes.

**Difficulty**:
Easy / Medium / Hard / Expert. In MIDI files difficulties live at different note ranges (offset by `midiBaseNote`); in `.chart` files at different `[*Drums]` sections.

**TempoMap**:
The deep module that owns tick↔seconds conversion for a chart. Built from `ppq` plus an ordered list of `(tick, bpm)` tempo changes; answers `seconds(forTick:)` and `beatTimes()`. The single source of truth that replaces the three former copies of tempo arithmetic.
_Avoid_: "tempo timeline", "tempo segments" (those are its internals).

**DrumTargetMap**:
The single canonical table mapping a drum lane (0=kick, 1=red, 2=yellow, 3=blue, 4=orange, 5=green) to a **DrumTarget**. Both parsers translate their raw note encoding to this canonical 0–5 index, then look up here. A 4-lane chart's green lane goes to orange when it is a cymbal and to green when it is a floor tom, read from the Clone Hero pro-drums markers: MIDI tom marker 112 (unmarked = cymbal); `.chart` cymbal marker `N 68` on the same tick (unmarked = tom, but only on a pro chart: song.ini `pro_drums = true` or any cymbal marker; a non-pro `.chart` green stays orange). 5-lane charts map straight.

**SongINIParser**:
Pure parsing of a `song.ini`'s text into metadata fields (title, artist, album, drum difficulty, pro-drums, delay). No file I/O — **SongLibrary** reads the bytes, picks an encoding, applies folder-name defaults, and discovers the notes/audio files.

**Parser**:
Turns raw file bytes into a **DrumChart**. Two adapters — the MIDI parser and the Chart parser — share **TempoMap** and **DrumTargetMap** but own their own format decoding. File I/O lives only in **DrumChartLoader**, never in a parser.

### Kit & input domain

**DrumVoice**:
The drum a pad represents — `kick`, `red`, `yellow`, `blue`, `orange`, `green`, or `off` (unassigned). The 6-colour standard plus kick. (Renamed from the former `DrumInputRole`.)
_Avoid_: "role", "colour" (colour doesn't cover kick/off).

**Pad**:
One of the 8 strike positions (index 0–7): pads 0–3 are the bottom row, 4–7 the top row, of the 4 **Lanes**.

**DrumHitJudge / Judgement**:
Pure hit-detection. Given the chart notes, note states, the **DrumKit** and the **TimingConfiguration**, it returns a **Judgement** (`hit(noteIndex:)` or `overhit`) and the indices of auto-missed notes — without mutating state or touching audio. A strike counts only for notes at its pad's **DrumTarget** (lane *and* row), so kick and snare in the same lane do not hit each other's notes (the original game's copy still matches the lane alone). The interface is the test surface for gameplay timing.

**ScoreState**:
The running tally (hits, misses, overhits, streak, max streak) as a value type advanced by `registerHit` / `registerOverhit` / `registerMisses`. An overhit counts as both an overhit and a miss and breaks the streak.

**GameplayFeedback / FeedbackDirector**:
The bridge from a pure **Judgement** to side effects. The director translates a judgement (or batch of auto-misses) into `GameplayFeedback` actions (flash a lane, mute/unmute drums, play the miss cue); the app flashes the lanes and **SongPlayback** plays the audio parts. The gameplay-audio/visual policy lives in this one pure place.

**TimingConfiguration**:
The hit-timing rules as one value type with invariants enforced at construction: the total hit window, its front/back split (`back = total − front`), and the player's timing offset. Derived from the stored settings; the single owner of the clamping constants. Distinct from a song's **chart delay** (per-song metadata, combined at the call site).

**GameSession**:
One play-through of a **DrumChart**: the note states and the **ScoreState**, advanced by pad strikes (`strike(pad:at:)`) and by time (`advance(to:)`), returning **GameplayFeedback**. The judging and scoring flow as a value type the MPC app drives.

**SongLibrary**:
Finds the songs below a folder (every folder with a `song.ini` and a chart) and reads them into `SongMetadata`.

**PlayerSettings**:
The player's settings that outlive a session (timing offset, hit window, metronome / miss sound / stem volumes, Pad→**DrumVoice** assignment, **Highway layout**, **Strike line** position), as JSON in `BeatTrain/settings.json` on the card.

**DrumKit**:
The single value type that owns kit geometry — the **Pad**↔**DrumTarget** layout and the **DrumVoice**↔**DrumTarget** canonical bijection — plus the player's two configuration maps: Pad→**DrumVoice** (which voice each pad plays) and Note→**Pad** (which pad a MIDI note triggers). Answers every "where does this land / what colour is it" question. Pure (Foundation only); colour lives in a separate extension (`Theme.swift`).

### MPC Sample platform domain

**Control Surface**:
The MPC Sample's top panel (pads, buttons, knobs, encoder), read and lit through the ALSA rawmidi device of that name. Speaks MIDI-shaped frames (`ControlSurfaceProtocol`). Only one process can own it, so the stock app is stopped while Beat-Train runs.

**Panel pads** (`PanelPads`, `PanelLights`):
The one owner of panel-pad numbering: which **Pad** a panel pad plays, the "PAD n" number shown for a Pad, the Pads as laid out on the panel, and the 16 panel colours (sent only when they change). The app speaks **Pads** only; panel pad numbers stop at this module.

**Panel pad**:
One of the MPC's 16 physical pads, numbered 0–15 from bottom left to top right. Distinct from a **Pad** (Beat-Train's 8 strike positions): panel pads 0–3 (bottom row) are **Pads** 4–7 (the top row: snare, hi-hat, tom, cymbal), panel pads 4–7 are **Pads** 0–3 (kick, –, –, floor tom); panel pads 8–15 are unused.
_Avoid_: "pad" alone when the panel pad is meant.

**Autorun package**:
The `autorun/` folder on the SD card (`autorun.json`, `autorun.sh`, `autorun.check`) that the firmware runs as root. Beat-Train's package swaps the stock app for Beat-Train and back, changing only `/run`.

**Stock app**:
Akai's `MPC Sample` program, run by `ac50.service`.

### MPC app (`Sources/beattrain`)

**SongPlayback**:
The music of the song being played and its clock: the stems in the audio engine, the count-in, pause and restart, metronome clicks and the miss feedback (drum mute, miss cue). The one owner of "what time is it in the chart" — the engine position once the count-in is over (stems or not), a timer without an engine; the chart delay and timing offset apply either way.
_Avoid_: "audio" for this (that is the engine underneath).

**SettingsKeeper**:
The player's settings while the app runs: the one way to change them (settings line, encoder step, knob turn, pad voice), which knob turns which setting (`knobs`, the source of the K1–K3 labels), and saving a moment after the last change through a **SettingsStorage** adapter (`SettingsFile` on the card; in memory in tests).

**ControlHints**:
What the controls do on the current screen, as the screen shows it: the B1–B3 labels and the footer (none while playing; the K1–K3 bar is on every screen). Kept next to the input handlers, so a label and its action change together.

**Splash**:
The start picture (one of the original Beat-Train splash screens) and its rules: on screen for a fixed time, a press ends it only after a minimum, knobs pass under it.

**StartupPaths**:
Where things are when Beat-Train starts: the song folders (`--songs`, `$BEATTRAIN_SONGS`, `BeatTrain/Songs` or `Songs` on each card under `/media`) and `settings.json` in the `BeatTrain` folder of the first card.

**Lifecycle**:
Running, asking to shut down, quitting to the stock app, or powering off. Every way out goes through `quit(powerOff:)`, which stops the song and saves the settings; the exit code (10 = power off) is what `session.sh` reads.

## Relationships

- A **DrumChart** has one **TempoMap** and many **Notes**
- A **Note** aims at exactly one **DrumTarget** (one **Lane** + one **Row**)
- A **Parser** produces a **DrumChart**; **DrumChartLoader** picks the parser by file extension and is the only place that reads files
- Both **Parsers** depend on **TempoMap** and **DrumTargetMap**
- A **DrumKit** maps **Note** → **Pad** → **DrumVoice** → **DrumTarget** → **Lane**; both gameplay and pad setup ask the same kit

## Flagged ambiguities

- A chart with **zero** tempo events is unplayable (no tick→seconds basis) — the parser must surface this as an error, not silently assume 120 BPM. A chart whose first tempo event simply isn't at tick 0 is fine: the leading segment is backfilled with the first known BPM.
- The Note→**Pad** mapping the player sets in pad setup was formerly ignored during gameplay (gameplay used a static default). Resolved: gameplay and setup share one Note→**Pad** mapping via **DrumKit**.

## Example dialogue

> **Dev:** "When the MIDI parser reads a note-on, how does it know which **DrumTarget** it is?"
> **Domain expert:** "It subtracts the difficulty's `midiBaseNote` to get the canonical drum lane 0–5, then asks the **DrumTargetMap**. The `.chart` parser gets the same 0–5 differently but asks the same map — that's the point of pulling it out."
