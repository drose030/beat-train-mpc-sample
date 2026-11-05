import BeatTrainCore
import MPCHardware

/// Drawing of the screens on the 320×240 display.
extension BeatTrainApp {
    /// How the frame should go out to the panel: notes running sideways need it
    /// sent in strips, or a frame half sent cuts them in two (see `Display.Sweep`).
    var sweep: Display.Sweep {
        if splash == nil, case .playing = screen, settings.highwayLayout == .horizontal { return .columns }
        return .rows
    }

    func render(into canvas: inout Canvas, now: Double) {
        canvas.clear(Theme.background)
        if let splash {
            splash.draw(into: &canvas)
        } else {
            drawScreen(into: &canvas, now: now)
        }
        drawOverlays(into: &canvas, now: now)
    }

    private func drawScreen(into canvas: inout Canvas, now: Double) {
        switch screen {
        case .library:
            drawLibrary(into: &canvas)
        case let .difficulty(song, options, index):
            drawDifficulty(song: song, options: options, index: index, into: &canvas)
        case let .loading(song, difficulty, _):
            drawSoftKeys(into: &canvas)
            canvas.drawText(fit(song.title, 25), x: 10, y: 90, scale: 2, Theme.text)
            canvas.drawText(fit("\(song.artist) - \(difficulty.rawValue.uppercased())", 50), x: 10, y: 112, Theme.dim)
            canvas.drawText("Loading song...", x: 10, y: 140, Theme.accent)
        case let .playing(play):
            drawPlay(play, now: now, into: &canvas)
        case let .results(song, difficulty, session):
            drawResults(song: song, difficulty: difficulty, session: session, into: &canvas)
        case let .padSetup(selected, _):
            drawPadSetup(selected: selected, into: &canvas)
        case let .settings(index, editing, _):
            drawSettings(index: index, editing: editing, into: &canvas)
        }
    }

    /// Messages and the shutdown question, over any screen.
    private func drawOverlays(into canvas: inout Canvas, now: Double) {
        if let message, message.until > now {
            canvas.fillRect(x: 10, y: 104, width: 300, height: 24, Theme.panel)
            canvas.strokeRect(x: 10, y: 104, width: 300, height: 24, Theme.miss)
            canvas.drawText(fit(message.text, 48), x: 16, y: 113, Theme.text)
        }
        if lifecycle == .poweringOff {
            canvas.clear(Theme.background)
            let text = "Shutting down..."
            canvas.drawText(text, x: (canvas.width - Canvas.textWidth(text, scale: 2)) / 2, y: 112, scale: 2, Theme.text)
        } else if lifecycle == .askingToShutDown {
            drawSoftKeys(into: &canvas)
            canvas.fillRect(x: 40, y: 92, width: 240, height: 48, Theme.panel)
            canvas.strokeRect(x: 40, y: 92, width: 240, height: 48, Theme.accent)
            let text = "Do you want to shut down?"
            canvas.drawText(text, x: (canvas.width - Canvas.textWidth(text)) / 2, y: 112, Theme.text)
        }
    }

    /// The bar at the top: what B1, B2 and B3 do, each under its button.
    private func drawSoftKeys(into canvas: inout Canvas) {
        let width = canvas.width / 3
        for (slot, label) in hints.softKeys.enumerated() {
            let x = slot * width
            guard let label else { continue }
            canvas.fillRect(x: x + 2, y: 0, width: width - 4, height: 14, Theme.panel)
            canvas.fillRect(x: x + 2, y: 13, width: width - 4, height: 1, Theme.accent)
            canvas.drawText(label, x: x + (width - Canvas.textWidth(label)) / 2, y: 3, Theme.text)
        }
    }

    /// The two lines at the bottom: what the screen's controls do, and below it
    /// what the knobs do (they work on every screen).
    private func drawFooter(into canvas: inout Canvas) {
        let line = canvas.height - 27
        let right = hints.footerRight
        canvas.fillRect(x: 0, y: line, width: canvas.width, height: 12, Theme.panel)
        canvas.drawText(hints.footer.joined(separator: "  "), x: 4, y: line + 3, Theme.dim)
        canvas.drawText(right, x: canvas.width - Canvas.textWidth(right) - 4, y: line + 3, Theme.dim)
        drawKnobBar(into: &canvas)
    }

    /// What K1, K2 and K3 do: a bar at the bottom, mirroring the soft keys.
    private func drawKnobBar(into canvas: inout Canvas) {
        let width = canvas.width / 3, top = canvas.height - 14
        for (slot, label) in knobLabels.enumerated() {
            guard let label else { continue }
            let x = slot * width
            canvas.fillRect(x: x + 2, y: top, width: width - 4, height: 14, Theme.panel)
            canvas.fillRect(x: x + 2, y: top, width: width - 4, height: 1, Theme.accent)
            canvas.drawText(label, x: x + (width - Canvas.textWidth(label)) / 2, y: top + 4, Theme.text)
        }
    }

    // MARK: - Library

    private func drawLibrary(into canvas: inout Canvas) {
        drawSoftKeys(into: &canvas)
        drawFooter(into: &canvas)
        guard !songs.isEmpty else {
            var y = 40
            for line in ["No songs found.", "", "Put song folders (song.ini + notes.mid", "or notes.chart) into BeatTrain/Songs", "on the SD card.", "", "Searched:"] + songRoots.map({ fit($0, 50) }) {
                canvas.drawText(line, x: 10, y: y, Theme.text)
                y += 11
            }
            return
        }
        let rowHeight = 13, visibleRows = 15
        let first = min(max(libraryIndex - visibleRows / 2, 0), max(songs.count - visibleRows, 0))
        for row in 0..<min(visibleRows, songs.count - first) {
            let index = first + row
            let song = songs[index]
            let y = 18 + row * rowHeight
            let selected = index == libraryIndex
            if selected {
                canvas.fillRect(x: 0, y: y - 2, width: canvas.width, height: rowHeight, Theme.selection)
            }
            let end = canvas.drawText(fit(song.title, 28), x: 6, y: y + 1, selected ? Theme.accent : Theme.text)
            canvas.drawText(fit(song.artist, (canvas.width - end - 14) / 6), x: end + 8, y: y + 1, Theme.dim)
        }
        if songs.count > visibleRows {
            let trackHeight = visibleRows * rowHeight
            let thumb = max(8, trackHeight * visibleRows / songs.count)
            let offset = (trackHeight - thumb) * first / max(songs.count - visibleRows, 1)
            canvas.fillRect(x: canvas.width - 3, y: 16 + offset, width: 2, height: thumb, Theme.dim)
        }
    }

    // MARK: - Difficulty

    private func drawDifficulty(song: SongMetadata, options: [DrumDifficulty], index: Int, into canvas: inout Canvas) {
        drawSoftKeys(into: &canvas)
        drawFooter(into: &canvas)
        canvas.drawText(fit(song.title, 25), x: 10, y: 26, scale: 2, Theme.text)
        canvas.drawText(fit(song.artist, 50), x: 10, y: 48, Theme.dim)
        for (row, difficulty) in options.enumerated() {
            let y = 78 + row * 26
            let selected = row == index
            canvas.fillRect(x: 60, y: y, width: 200, height: 22, selected ? Theme.selection : Theme.panel)
            if selected { canvas.strokeRect(x: 60, y: y, width: 200, height: 22, Theme.accent) }
            let name = difficulty.rawValue.uppercased()
            canvas.drawText(name, x: 160 - Canvas.textWidth(name, scale: 2) / 2, y: y + 4, scale: 2, selected ? Theme.accent : Theme.text)
        }
    }

    // MARK: - Play

    private func drawPlay(_ play: Play, now: Double, into canvas: inout Canvas) {
        let time = playback.chartTime(now: now)
        let highway = Highway(layout: settings.highwayLayout, strikeLine: settings.strikeLine, chartPads: play.chartPads, kit: kit, screenWidth: canvas.width)
        let centerX: Int
        switch settings.highwayLayout {
        case .vertical:
            drawVerticalHighway(highway, play: play, time: time, now: now, into: &canvas)
            drawSidebar(play, time: time, into: &canvas)
            centerX = Highway.width / 2
        case .verticalByPad:
            drawVerticalByPadHighway(highway, play: play, time: time, now: now, into: &canvas)
            drawSidebar(play, time: time, into: &canvas)
            centerX = Highway.width / 2
        case .horizontal:
            drawHorizontalHighway(highway, play: play, time: time, now: now, into: &canvas)
            drawInfoLine(play, time: time, into: &canvas)
            centerX = (Highway.padMapWidth + canvas.width) / 2
        }

        // Count-in and pause, over the middle of the highway.
        if time < 0 {
            let count = "\(Int((-time).rounded(.up)))"
            canvas.drawText(count, x: centerX - Canvas.textWidth(count, scale: 5) / 2, y: 70, scale: 5, Theme.text)
        }
        if let resumesAt = playback.resumesAt {
            // Back from the settings: 3, 2, 1, then the song goes on.
            let count = "\(max(1, Int((resumesAt - now).rounded(.up))))"
            canvas.drawText(count, x: centerX - Canvas.textWidth(count, scale: 5) / 2, y: 70, scale: 5, Theme.text)
        } else if playback.isPaused {
            canvas.fillRect(x: centerX - 60, y: 80, width: 120, height: 28, Theme.panel)
            canvas.drawText("PAUSED", x: centerX - Canvas.textWidth("PAUSED", scale: 2) / 2, y: 87, scale: 2, Theme.text)
        } else if play.session.isFinished(at: time) {
            // The notes are done, the music plays on.
            canvas.fillRect(x: centerX - 80, y: 76, width: 160, height: 40, Theme.panel)
            canvas.drawText("SONG END", x: centerX - Canvas.textWidth("SONG END", scale: 2) / 2, y: 82, scale: 2, Theme.text)
            canvas.drawText("STOP: RESULTS", x: centerX - Canvas.textWidth("STOP: RESULTS") / 2, y: 102, Theme.dim)
        }
        drawSoftKeys(into: &canvas)
        drawKnobBar(into: &canvas)
    }

    /// A note in its voice's colour; struck notes pass the line in white, missed
    /// ones fade.
    private static func color(of note: Highway.Note) -> Color {
        switch note.state {
        case .hit: Theme.text
        case .missed: note.voice.color.mixed(with: Theme.highway, amount: 0.7)
        default: note.voice.color
        }
    }

    /// Notes come down four columns onto the strike line, the pads below the
    /// highway.
    private func drawVerticalHighway(_ highway: Highway, play: Play, time: Double, now: Double, into canvas: inout Canvas) {
        let strikeY = highway.strike
        let laneWidth = highway.laneSize
        canvas.fillRect(x: 0, y: 0, width: Highway.width, height: Highway.bottom, Theme.highway)
        for y in highway.beats(play.beatTimes, at: time) {
            canvas.fillRect(x: 0, y: y, width: Highway.width, height: 1, Theme.beatLine)
        }

        // Lanes: input flash, separators, target boxes.
        for lane in highway.lanes.indices {
            let x = highway.laneOrigin(lane)
            if let pad = play.padFeedback.struckPad(inLane: lane, at: now) {
                canvas.fillRect(x: x, y: 0, width: laneWidth, height: Highway.bottom, Theme.highway.mixed(with: kit.voice(forPad: pad).color, amount: 0.22))
            }
            if lane > 0 {
                canvas.fillRect(x: x, y: 0, width: 1, height: Highway.bottom, Theme.laneLine)
            }
            canvas.strokeRect(x: x + 4, y: strikeY - 11, width: laneWidth - 8, height: 22, Theme.dim)
        }

        for note in highway.notes(of: play.session, at: time) {
            let color = Self.color(of: note)
            let x = highway.laneOrigin(note.lane) + 6
            let w = laneWidth - 12
            let ghost = color.mixed(with: Theme.highway, amount: 0.8)
            // Upper half = the upper panel row, as the pads are laid out. Cut off at
            // the end of the highway, above the pads.
            for (top, isUpper) in [(note.position - 9, true), (note.position + 1, false)] {
                let height = min(8, Highway.bottom - top)
                guard height > 0 else { continue }
                canvas.fillRect(x: x, y: top, width: w, height: height, (note.target.row == PanelPads.rowOnTop) == isUpper ? color : ghost)
            }
        }

        // Strike line and judgement flashes.
        canvas.fillRect(x: 0, y: strikeY - 1, width: Highway.width, height: 2, Theme.accent)
        for lane in highway.lanes.indices {
            guard let isHit = play.padFeedback.judgement(ofLane: lane, at: now) else { continue }
            canvas.fillRect(x: highway.laneOrigin(lane) + 2, y: strikeY - 4, width: laneWidth - 4, height: 8, isHit ? Theme.hit : Theme.miss)
        }

        // Under each lane a map of the panel with its pads (those with a sound).
        for (lane, pads) in highway.lanes.enumerated() where !pads.isEmpty {
            drawPadMap(showing: pads, play: play, now: now, x: highway.laneOrigin(lane) + (laneWidth - Self.padMapSize.width) / 2,
                       y: Highway.bottom + 2, into: &canvas)
        }
    }

    /// Notes come down one column per pad the chart uses, in the order the pads sit
    /// on the panel, with a map of the panel under each.
    private func drawVerticalByPadHighway(_ highway: Highway, play: Play, time: Double, now: Double, into canvas: inout Canvas) {
        let strikeY = highway.strike
        let laneWidth = highway.laneSize
        canvas.fillRect(x: 0, y: 0, width: Highway.width, height: Highway.bottom, Theme.highway)
        for y in highway.beats(play.beatTimes, at: time) {
            canvas.fillRect(x: 0, y: y, width: Highway.width, height: 1, Theme.beatLine)
        }

        // Lanes: input flash, separator, target box with the judgement, panel map.
        for (lane, pads) in highway.lanes.enumerated() {
            let pad = pads[0]
            let x = highway.laneOrigin(lane)
            if play.padFeedback.isStruck(pad: pad, at: now) {
                canvas.fillRect(x: x, y: 0, width: laneWidth, height: Highway.bottom, Theme.highway.mixed(with: kit.voice(forPad: pad).color, amount: 0.22))
            }
            if lane > 0 {
                canvas.fillRect(x: x, y: 0, width: 1, height: Highway.bottom, Theme.laneLine)
            }
            if let isHit = play.padFeedback.judgement(ofPad: pad, at: now) {
                canvas.fillRect(x: x + 3, y: strikeY - 9, width: laneWidth - 6, height: 18, isHit ? Theme.hit : Theme.miss)
            }
            canvas.strokeRect(x: x + 3, y: strikeY - 9, width: laneWidth - 6, height: 18, Theme.dim)
            drawPadMap(showing: pads, play: play, now: now, x: x + (laneWidth - Self.padMapSize.width) / 2, y: Highway.bottom + 2, into: &canvas)
        }

        // Whole notes, cut off at the end of the highway.
        for note in highway.notes(of: play.session, at: time) {
            let top = note.position - 5
            let height = min(10, Highway.bottom - top)
            guard height > 0 else { continue }
            canvas.fillRect(x: highway.laneOrigin(note.lane) + 5, y: top, width: laneWidth - 10, height: height, Self.color(of: note))
        }
        canvas.fillRect(x: 0, y: strikeY - 1, width: Highway.width, height: 2, Theme.accent)
    }

    /// The size of `drawPadMap`: 4×2 cells of 5 px, 1 px apart.
    static let padMapSize = (width: 23, height: 11)

    /// The panel's eight pads in miniature, as they sit on the panel, with `pads` in
    /// their voices' colours (white while struck).
    private func drawPadMap(showing pads: [Int], play: Play, now: Double, x: Int, y: Int, into canvas: inout Canvas) {
        for (panelRow, row) in PanelPads.rows.enumerated() {
            for (column, cell) in row.enumerated() {
                let color = !pads.contains(cell) ? Theme.panel : (play.padFeedback.isStruck(pad: cell, at: now) ? Theme.text : kit.voice(forPad: cell).color)
                canvas.fillRect(x: x + column * 6, y: y + panelRow * 6, width: 5, height: 5, color)
            }
        }
    }

    private func drawSidebar(_ play: Play, time: Double, into canvas: inout Canvas) {
        let x = Highway.width + 6
        let chars = (canvas.width - x - 2) / 6
        let score = play.session.score
        // Below the soft key bar.
        canvas.drawText(fit(play.song.title, chars), x: x, y: 20, Theme.accent)
        canvas.drawText(fit(play.song.artist, chars), x: x, y: 30, Theme.dim)
        canvas.drawText(play.difficulty.rawValue.uppercased(), x: x, y: 40, Theme.text)

        canvas.drawText("STREAK", x: x, y: 56, Theme.dim)
        canvas.drawText("\(score.streak)", x: x, y: 66, scale: 3, Theme.text)

        let rows: [(String, String)] = [
            ("HITS", "\(score.hits)"),
            ("MISSES", "\(score.misses)"),
            ("BEST", "\(score.maxStreak)"),
            ("ACC", "\(Int((play.session.runningAccuracy * 100).rounded()))%"),
        ]
        for (row, item) in rows.enumerated() {
            let y = 96 + row * 12
            canvas.drawText(item.0, x: x, y: y, Theme.dim)
            canvas.drawText(item.1, x: canvas.width - Canvas.textWidth(item.1) - 6, y: y, Theme.text)
        }

        let last = play.session.chart.notes.last?.timeSec ?? 1
        let progress = min(max(time / max(last, 0.001), 0), 1)
        canvas.strokeRect(x: x, y: 150, width: canvas.width - x - 6, height: 6, Theme.dim)
        canvas.fillRect(x: x + 1, y: 151, width: Int(Double(canvas.width - x - 8) * progress), height: 4, Theme.accent)

        if timingOffsetMs != 0 {
            canvas.drawText("OFFSET \(Self.signed(timingOffsetMs))MS", x: x, y: 164, Theme.dim)
        }
        if !playback.hasMusic {
            canvas.drawText("NO AUDIO", x: x, y: 176, Theme.miss)
        }
        if playback.speed < 1 {
            canvas.drawText("SPEED \(Self.percent(playback.speed))", x: x, y: 188, Theme.accent)
        }
    }

    /// Notes run right to left onto the strike line, one row per pad. Struck notes
    /// stay on the row.
    private func drawHorizontalHighway(_ highway: Highway, play: Play, time: Double, now: Double, into canvas: inout Canvas) {
        let strikeX = highway.strike
        let left = Highway.padMapWidth, width = canvas.width - left
        let rowHeight = highway.laneSize
        let top = highway.laneStart, height = highway.lanesSize

        canvas.fillRect(x: left, y: top, width: width, height: height, Theme.highway)
        for x in highway.beats(play.beatTimes, at: time) {
            canvas.fillRect(x: x, y: top, width: 1, height: height, Theme.beatLine)
        }

        // Rows: input flash, separator, the panel in miniature, target box.
        for (row, pads) in highway.lanes.enumerated() {
            let pad = pads[0]
            let y = highway.laneOrigin(row)
            let voice = kit.voice(forPad: pad)
            if play.padFeedback.isStruck(pad: pad, at: now) {
                canvas.fillRect(x: left, y: y, width: width, height: rowHeight, Theme.highway.mixed(with: voice.color, amount: 0.22))
            }
            if row > 0 {
                canvas.fillRect(x: left, y: y, width: width, height: 1, Theme.laneLine)
            }
            // Which of the panel's eight pads this row is.
            let hasTag = rowHeight >= 26
            drawPadMap(showing: pads, play: play, now: now, x: 3, y: hasTag ? y + 4 : y + (rowHeight - Self.padMapSize.height) / 2, into: &canvas)
            if hasTag {
                canvas.drawText(voice.tag, x: 2, y: y + 18, Theme.dim)
            }
            let box = (x: strikeX - 7, y: y + 3, width: 14, height: rowHeight - 5)
            if let isHit = play.padFeedback.judgement(ofPad: pad, at: now) {
                canvas.fillRect(x: box.x, y: box.y, width: box.width, height: box.height, isHit ? Theme.hit : Theme.miss)
            }
            canvas.strokeRect(x: box.x, y: box.y, width: box.width, height: box.height, Theme.dim)
        }

        for note in highway.notes(of: play.session, at: time) {
            let x = note.position
            // Clipped at the panel map, which the notes pass under.
            let noteLeft = max(x - 5, left)
            guard x + 5 > noteLeft else { continue }
            canvas.fillRect(x: noteLeft, y: highway.laneOrigin(note.lane) + 5, width: x + 5 - noteLeft, height: rowHeight - 9, Self.color(of: note))
        }
        canvas.fillRect(x: strikeX - 1, y: top, width: 2, height: height, Theme.accent)
    }

    /// Above the horizontal highway: the song, then from the right streak and
    /// accuracy, the speed and a missing audio; below, the song's progress.
    private func drawInfoLine(_ play: Play, time: Double, into canvas: inout Canvas) {
        let score = play.session.score
        var edge = canvas.width - 4
        func right(_ text: String, _ color: Color) {
            edge -= Canvas.textWidth(text)
            canvas.drawText(text, x: edge, y: 18, color)
            edge -= 12
        }
        right("STREAK \(score.streak)  \(Self.percent(play.session.runningAccuracy))", Theme.text)
        if playback.speed < 1 { right("SPEED \(Self.percent(playback.speed))", Theme.accent) }
        if !playback.hasMusic { right("NO AUDIO", Theme.miss) }
        canvas.drawText(fit(play.song.title, max(0, (edge - 4) / 6)), x: 4, y: 18, Theme.accent)

        let last = play.session.chart.notes.last?.timeSec ?? 1
        let progress = min(max(time / max(last, 0.001), 0), 1)
        canvas.fillRect(x: 0, y: 28, width: canvas.width, height: 2, Theme.panel)
        canvas.fillRect(x: 0, y: 28, width: Int(Double(canvas.width) * progress), height: 2, Theme.accent)
    }

    // MARK: - Settings

    private func drawSettings(index: Int, editing: Bool, into canvas: inout Canvas) {
        drawSoftKeys(into: &canvas)
        drawFooter(into: &canvas)
        let rowHeight = 15
        // As many lines as fit above the footer; the list scrolls with the selection.
        let visible = (canvas.height - 27 - 17) / rowHeight
        let first = max(0, index - visible + 1)
        for (row, item) in SettingsItem.all.enumerated().dropFirst(first).prefix(visible) {
            let y = 17 + (row - first) * rowHeight
            let selected = row == index
            if selected {
                canvas.fillRect(x: 0, y: y, width: canvas.width, height: rowHeight - 1, Theme.selection)
                if editing { canvas.strokeRect(x: 0, y: y, width: canvas.width, height: rowHeight - 1, Theme.accent) }
            }
            let title = item.title + (SettingsKeeper.knobName(for: item).map { " (\($0))" } ?? "")
            canvas.drawText(title, x: 8, y: y + 4, selected ? Theme.text : Theme.dim)
            var value = item.text(in: settings)
            if selected && editing { value = "< \(value) >" }
            canvas.drawText(value, x: canvas.width - Canvas.textWidth(value) - 8, y: y + 4, selected && editing ? Theme.accent : Theme.text)
        }
    }

    // MARK: - Pad setup

    private func drawPadSetup(selected: Int, into canvas: inout Canvas) {
        drawSoftKeys(into: &canvas)
        drawFooter(into: &canvas)
        canvas.drawText("Hit a pad, then turn the encoder.", x: 7, y: 21, Theme.dim)
        let size = 72, height = 64, gap = 6
        // As on the device: panel pads 5-8 above, 1-4 below.
        for (row, pads) in PanelPads.rows.enumerated() {
            for (column, pad) in pads.enumerated() {
                let voice = kit.voice(forPad: pad)
                let x = 7 + column * (size + gap), y = 36 + row * (height + gap)
                canvas.fillRect(x: x, y: y, width: size, height: height,
                                voice == .off ? Theme.panel : voice.color.mixed(with: Theme.background, amount: 0.6))
                if pad == selected {
                    canvas.strokeRect(x: x - 2, y: y - 2, width: size + 4, height: height + 4, Theme.accent)
                    canvas.strokeRect(x: x - 1, y: y - 1, width: size + 2, height: height + 2, Theme.accent)
                }
                canvas.drawText(PanelPads.label(forPad: pad), x: x + 4, y: y + 4, Theme.text)
                let label = fit(voice.label, size / 6)
                canvas.drawText(label, x: x + (size - Canvas.textWidth(label)) / 2, y: y + height - 14, voice == .off ? Theme.dim : Theme.text)
            }
        }
        let voice = kit.voice(forPad: selected)
        let end = canvas.drawText("\(PanelPads.label(forPad: selected)): ", x: 7, y: 178, scale: 2, Theme.dim)
        canvas.drawText(voice.label, x: end, y: 178, scale: 2, voice == .off ? Theme.dim : voice.color)
        if let lane = kit.lane(forPad: selected) {
            canvas.drawText("Notes fall in lane \(lane + 1).", x: 7, y: 198, Theme.dim)
        }
    }

    // MARK: - Results

    private func drawResults(song: SongMetadata, difficulty: DrumDifficulty, session: GameSession, into canvas: inout Canvas) {
        drawSoftKeys(into: &canvas)
        drawFooter(into: &canvas)
        let score = session.score
        canvas.drawText(fit(song.title, 25), x: 10, y: 24, scale: 2, Theme.text)
        let speed = playback.speed < 1 ? " AT \(Self.percent(playback.speed)) SPEED" : ""
        canvas.drawText(fit("\(song.artist) - \(difficulty.rawValue.uppercased())\(speed)", 50), x: 10, y: 44, Theme.dim)
        let accuracy = "\(Int((session.accuracy * 100).rounded()))%"
        canvas.drawText(accuracy, x: 10, y: 66, scale: 5, Theme.accent)
        let rows: [(String, String)] = [
            ("HITS", "\(score.hits) / \(session.chart.notes.count)"),
            ("MISSES", "\(score.misses)"),
            ("OVERHITS", "\(score.overhits)"),
            ("BEST STREAK", "\(score.maxStreak)"),
        ]
        for (row, item) in rows.enumerated() {
            let y = 120 + row * 16
            canvas.drawText(item.0, x: 10, y: y, scale: 1, Theme.dim)
            canvas.drawText(item.1, x: 110, y: y, scale: 1, Theme.text)
        }
    }
}
