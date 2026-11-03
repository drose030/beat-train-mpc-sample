import BeatTrainCore
import MPCHardware

/// Drawing of the screens on the 320×240 display.
extension BeatTrainApp {
    static let highwayWidth = 200
    static let laneWidth = 50
    static let strikeY = 202
    static let highwayBottom = 216
    static let pixelsPerSecond = 125.0

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
        case let .settings(index, editing):
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

        let width = canvas.width / 3, top = canvas.height - 14
        // What K1, K2 and K3 do: a bar at the bottom, mirroring the soft keys.
        for (slot, label) in SettingsKeeper.knobs.map(\.item.title).enumerated() {
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
        let session = play.session
        let pps = Self.pixelsPerSecond
        let futureSec = Double(Self.strikeY) / pps
        let pastSec = Double(Self.highwayBottom - Self.strikeY) / pps

        canvas.fillRect(x: 0, y: 0, width: Self.highwayWidth, height: Self.highwayBottom, Theme.highway)

        // Beat grid.
        for beat in play.beatTimes where beat > time - pastSec && beat < time + futureSec {
            let y = Self.strikeY - Int(((beat - time) * pps).rounded())
            canvas.fillRect(x: 0, y: y, width: Self.highwayWidth, height: 1, Theme.beatLine)
        }

        // Lanes: input flash, separators, target boxes.
        for lane in 0..<4 {
            let x = lane * Self.laneWidth
            if let flash = play.laneFlash[lane], flash.until > now {
                canvas.fillRect(x: x, y: 0, width: Self.laneWidth, height: Self.highwayBottom, Theme.highway.mixed(with: flash.color, amount: 0.22))
            }
            if lane > 0 {
                canvas.fillRect(x: x, y: 0, width: 1, height: Self.highwayBottom, Theme.laneLine)
            }
            canvas.strokeRect(x: x + 4, y: Self.strikeY - 11, width: Self.laneWidth - 8, height: 22, Theme.dim)
        }

        // Notes, from the first one that can still be on screen.
        let notes = session.chart.notes
        var low = 0, high = notes.count
        while low < high {
            let mid = (low + high) / 2
            if notes[mid].timeSec < time - pastSec { low = mid + 1 } else { high = mid }
        }
        var index = low
        while index < notes.count, notes[index].timeSec < time + futureSec {
            defer { index += 1 }
            let state = session.state(ofNote: index)
            guard state != .hit else { continue }
            let target = session.target(ofNote: index)
            var color = session.voice(ofNote: index).color
            if state == .missed { color = color.mixed(with: Theme.highway, amount: 0.7) }
            let y = Self.strikeY - Int(((notes[index].timeSec - time) * pps).rounded())
            let x = target.lane * Self.laneWidth + 6
            let w = Self.laneWidth - 12
            let ghost = color.mixed(with: Theme.highway, amount: 0.8)
            // Upper half = the upper panel row, as the pads are laid out.
            canvas.fillRect(x: x, y: y - 9, width: w, height: 8, target.row == PanelPads.rowOnTop ? color : ghost)
            canvas.fillRect(x: x, y: y + 1, width: w, height: 8, target.row != PanelPads.rowOnTop ? color : ghost)
        }

        // Strike line and judgement flashes.
        canvas.fillRect(x: 0, y: Self.strikeY - 1, width: Self.highwayWidth, height: 2, Theme.accent)
        for lane in 0..<4 {
            guard let flash = play.judgeFlash[lane], flash.until > now else { continue }
            canvas.fillRect(x: lane * Self.laneWidth + 2, y: Self.strikeY - 4, width: Self.laneWidth - 4, height: 8, flash.isHit ? Theme.hit : Theme.miss)
        }

        // The eight pads under the highway.
        for pad in 0..<DrumKit.padCount {
            let target = DrumKit.layoutTarget(forPad: pad)
            let voice = kit.voice(forPad: pad)
            let lit = play.padFlashUntil[pad] > now
            let color = voice == .off ? Theme.panel : (lit ? voice.color : voice.color.mixed(with: Theme.background, amount: 0.7))
            let y = target.row == PanelPads.rowOnTop ? Self.highwayBottom + 3 : Self.highwayBottom + 13
            canvas.fillRect(x: target.lane * Self.laneWidth + 6, y: y, width: Self.laneWidth - 12, height: 8, color)
        }

        // Count-in and pause.
        if time < 0 {
            let count = "\(Int((-time).rounded(.up)))"
            canvas.drawText(count, x: Self.highwayWidth / 2 - Canvas.textWidth(count, scale: 5) / 2, y: 70, scale: 5, Theme.text)
        }
        if playback.isPaused {
            canvas.fillRect(x: 40, y: 80, width: 120, height: 28, Theme.panel)
            canvas.drawText("PAUSED", x: 100 - Canvas.textWidth("PAUSED", scale: 2) / 2, y: 87, scale: 2, Theme.text)
        } else if session.isFinished(at: time) {
            // The notes are done, the music plays on.
            canvas.fillRect(x: 20, y: 76, width: 160, height: 40, Theme.panel)
            canvas.drawText("SONG END", x: 100 - Canvas.textWidth("SONG END", scale: 2) / 2, y: 82, scale: 2, Theme.text)
            canvas.drawText("STOP: RESULTS", x: 100 - Canvas.textWidth("STOP: RESULTS") / 2, y: 102, Theme.dim)
        }

        drawSidebar(play, time: time, into: &canvas)
        drawSoftKeys(into: &canvas)
    }

    private func drawSidebar(_ play: Play, time: Double, into canvas: inout Canvas) {
        let x = Self.highwayWidth + 6
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
        for (row, hint) in hints.footer.enumerated() {
            canvas.drawText(hint, x: x, y: 214 + row * 12, Theme.dim)
        }
    }

    // MARK: - Settings

    private func drawSettings(index: Int, editing: Bool, into canvas: inout Canvas) {
        drawSoftKeys(into: &canvas)
        drawFooter(into: &canvas)
        let rowHeight = 15
        for (row, item) in SettingsItem.all.enumerated() {
            let y = 17 + row * rowHeight
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
        canvas.drawText(fit("\(song.artist) - \(difficulty.rawValue.uppercased())", 50), x: 10, y: 44, Theme.dim)
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
