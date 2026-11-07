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
One of the 4 columns a **DrumTarget** sits in, as on the four-lane highway (a pad column on the panel). Distinct from the 6 canonical drum colours, and from the columns of the by-pad highway (one per **Pad**).

**Row**:
Top or bottom half of a lane — encodes the 2-pad-per-lane play style.

**Difficulty**:
Easy / Medium / Hard / Expert. In MIDI files difficulties live at different note ranges (offset by `midiBaseNote`); in `.chart` files at different `[*Drums]` sections.

**TempoMap**:
The deep module that owns tick↔seconds conversion for a chart. Built from `ppq` plus an ordered list of `(tick, bpm)` tempo changes; answers `seconds(forTick:)` and `beatTimes()`. The single source of truth for tempo arithmetic.
_Avoid_: "tempo timeline", "tempo segments" (those are its internals).

**DrumTargetMap**:
The single canonical table mapping a drum lane (0=kick, 1=red, 2=yellow, 3=blue, 4=orange, 5=green) to a **DrumTarget**. Both parsers translate their raw note encoding to this canonical 0–5 index, then look up here. A 4-lane chart's green lane goes to orange when it is a cymbal and to green when it is a floor tom, read from the Clone Hero pro-drums markers: MIDI tom marker 112 (unmarked = cymbal); `.chart` cymbal marker `N 68` on the same tick (unmarked = tom, but only on a pro chart: song.ini `pro_drums = true` or any cymbal marker; a non-pro `.chart` green stays orange). 5-lane charts map straight.

**SongINIParser**:
Pure parsing of a `song.ini`'s text into metadata fields (title, artist, album, drum difficulty, pro-drums, delay). No file I/O — **SongLibrary** reads the bytes, picks an encoding, applies folder-name defaults, and discovers the notes/audio files.

**Parser**:
Turns raw file bytes into a **DrumChart**. Two adapters — the MIDI parser and the Chart parser — share **TempoMap** and **DrumTargetMap** but own their own format decoding. File I/O lives only in **DrumChartLoader**, never in a parser.

### Kit & input domain

**DrumVoice**:
The drum a pad represents — `kick`, `red`, `yellow`, `blue`, `orange`, `green`, or `off` (unassigned). The 6-colour standard plus kick.
_Avoid_: "role", "colour" (colour doesn't cover kick/off).

**Pad**:
One of the 8 strike positions (index 0–7): pads 0–3 are the bottom row, 4–7 the top row, of the 4 **Lanes**.

**DrumHitJudge / Judgement**:
Pure hit-detection. Given the chart notes, note states, the **DrumKit** and the **TimingConfiguration**, it returns a **Judgement** (`hit(noteIndex:)` or `overhit`) and the indices of auto-missed notes — without mutating state or touching audio. A strike counts only for notes at its pad's **DrumTarget** (lane *and* row), so kick and snare in the same lane do not hit each other's notes (the original game's copy still matches the lane alone). The interface is the test surface for gameplay timing.

**ScoreState**:
The running tally (hits, misses, overhits, streak, max streak) as a value type advanced by `registerHit` / `registerOverhit` / `registerMisses`. An overhit counts as both an overhit and a miss and breaks the streak.

**GameplayFeedback / FeedbackDirector**:
The bridge from a pure **Judgement** to side effects. The director translates a judgement (or batch of auto-misses) into `GameplayFeedback` actions (flash the note's **DrumTarget** green or red, mute/unmute drums, play the miss cue); the app's **Pad feedback** shows the flashes and **SongPlayback** plays the audio parts. The gameplay-audio/visual policy lives in this one pure place.

**TimingConfiguration**:
The hit-timing rules as one value type with invariants enforced at construction: the total hit window, its front/back split (`back = total − front`), and the player's timing offset. Derived from the stored settings; the single owner of the clamping constants. Distinct from a song's **chart delay** (per-song metadata, combined at the call site).

**GameSession**:
One play-through of a **DrumChart**: the note states and the **ScoreState**, advanced by pad strikes (`strike(pad:at:)`) and by time (`advance(to:)`), returning **GameplayFeedback**. The judging and scoring flow as a value type the MPC app drives.

**SongLibrary**:
Finds the songs below a folder (every folder with a `song.ini` and a chart) and reads them into `SongMetadata`.

**PlayerSettings**:
The player's settings that outlive a session (timing offset, hit window, metronome / miss sound / stem volumes, **Pad sounds** volume, Pad→**DrumVoice** assignment, **Highway layout**, **Strike line** position), as JSON in `BeatTrain/settings.json` on the card.

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
The music of the song being played: the stems in the audio engine, start, pause and restart, metronome clicks and the miss feedback (drum mute, miss cue). The one owner of "what time is it in the chart", through its **Song clock**.
_Avoid_: "audio" for this (that is the engine underneath).

**Song clock** (`SongClock`):
Where a song stands in time and from it the chart time: the count-in, pause and the 3-2-1 back from the settings, the **Song speed**, the chart delay and the timing offset (scaled with the speed). Its song seconds come from the engine position once the count-in is over (stems or not), else from a timer; tests step either.

**Heard clock** (`heard_clock.c`):
In the audio engine: which song frame is being heard, from notes of which song frame went out at which device frame and the device's delay. **Song clock** reads it as the engine position.

**Time stretch** (`stretch.c`):
In the audio engine: the mixed stems played slower at the same pitch (WSOLA), for the **Song speed**. At full speed the song passes through unchanged.

**Stem** (`Stem`):
One audio file of a song folder: `song`, `drums`, `guitar`, `bass`, `rhythm`, `vocals`, `keys` or `crowd` (the original game's set). Volumes per stem are kept by these names in **PlayerSettings**.

**SettingsKeeper**:
The player's settings while the app runs: the one way to change them (settings line, encoder step, knob turn, pad voice), which knob turns which setting (`knobs`, the source of the K1–K3 labels) and which **Stem group** with SHIFT held (`mixKnobs`), and saving a moment after the last change through a **SettingsStorage** adapter (`SettingsFile` on the card; in memory in tests).

**Relative control** (`RelativeControl`):
A knob or the fader setting a value by how far it moves since its last report, not to where it stands (the MPC does not report where knobs stand at start). The first report only tells where it stands; small moves add up; a value changed elsewhere is where it goes on from. K1–K3 (with SHIFT or not) and SHIFT+FADER work this way.

**ControlHints**:
What the controls do on the current screen, as the screen shows it: the B1–B3 labels and the footer (none while playing; the K1–K3 bar is on every screen). Kept next to the input handlers, so a label and its action change together.

**Splash**:
The start picture (one of the original Beat-Train splash screens) and its rules: on screen for a fixed time, a press ends it only after a minimum, knobs pass under it.

**StartupPaths**:
Where things are when Beat-Train starts: the song folders (`--songs`, `$BEATTRAIN_SONGS`, `BeatTrain/Songs` or `Songs` on each card under `/media`) and `settings.json` in the `BeatTrain` folder of the first card.

**Lifecycle**:
Running, asking to shut down, quitting to the stock app, or powering off. Every way out goes through `quit(powerOff:)`, which stops the song and saves the settings; the exit code (10 = power off) is what `session.sh` reads.

**Highway** (`Highway`):
The play screen's note highway as geometry, for a **Highway layout** and **Strike line**: its lanes and the **Pads** each shows, where a chart time lies along it, and which notes and beat lines are on it at a moment. The screen paints what it says.

**Pad feedback** (`PadFeedback`):
What the play screen shows of strikes, for a moment each, kept per **Pad**: which pads were just struck (their lights, panel maps and lanes) and how each pad's last note was judged (green or red at the strike line). The four-lane highway asks per **Lane**.

**Play-through** (`PlayThrough`):
A song played by script as a player would: picked in the song list and started, its notes struck as they come due, some left to miss. Previews, the README's animations and the app tests play this way.

**Highway layout**:
How the note highway runs on the play screen: vertical (4 **Lanes**, notes come down, each note's halves are the two **Rows**), vertical by pad (one column per **Pad** the chart uses, in panel order) or horizontal (one row per **Pad** the chart uses, notes run right to left). A **PlayerSettings** value. Distinct from **Row**, which is part of a **DrumTarget**.

**Strike line**:
The line on the **Highway** where a note is to be struck: chart time 0, notes to come on one side, passed ones on the other. Sits near the end the notes run to, or a quarter, a third or half way in (a **PlayerSettings** value, for every **Highway layout**); further in shows more passed notes and less of what comes.

**Song speed**:
How fast the song plays, 50–100 %, for practising (SHIFT+FADER). Slower at the same pitch; chart time is song time, so the notes and the hit window slow down with it. Not saved; distinct from a song's tempo (**TempoMap**).

**Pad sounds**:
A song's own drum hits, one per **DrumVoice**, in its `sounds/` folder (picked in Trackyard). With their volume up in **PlayerSettings**, a strike plays its pad's voice; the `drums` **Stem** keeps its own volume, so it can be turned down to hear only the pads. Distinct from the miss cue and the metronome click, the other one-shot sounds.

**Stem group**:
The **Stems** SHIFT+K1–K3 turn together: the `song` stem, the `drums`, and all the others. Changes the per-stem volumes in **PlayerSettings**, each stem keeping its distance to the rest of its group.

## Relationships

- A **DrumChart** has one **TempoMap** and many **Notes**
- A **Note** aims at exactly one **DrumTarget** (one **Lane** + one **Row**)
- A **Parser** produces a **DrumChart**; **DrumChartLoader** picks the parser by file extension and is the only place that reads files
- Both **Parsers** depend on **TempoMap** and **DrumTargetMap**
- A **DrumKit** maps **Note** → **Pad** → **DrumVoice** → **DrumTarget** → **Lane**; both gameplay and pad setup ask the same kit

## Flagged ambiguities

- A chart with **zero** tempo events is unplayable (no tick→seconds basis) — the parser must surface this as an error, not silently assume 120 BPM. A chart whose first tempo event simply isn't at tick 0 is fine: the leading segment is backfilled with the first known BPM.

## Example dialogue

> **Dev:** "When the MIDI parser reads a note-on, how does it know which **DrumTarget** it is?"
> **Domain expert:** "It subtracts the difficulty's `midiBaseNote` to get the canonical drum lane 0–5, then asks the **DrumTargetMap**. The `.chart` parser gets the same 0–5 differently but asks the same map — that's the point of pulling it out."
