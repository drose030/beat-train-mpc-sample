import BeatTrainCore

/// The play screen's note highway as geometry, for one **Highway layout** and
/// **Strike line**: its lanes and the pads each shows, where a chart time lies along
/// it, and which notes and beats are on it at a moment. The screen only paints what
/// it says.
///
/// "Along" is the way the notes run (y on the vertical highways, x on the
/// horizontal one), "across" the way the lanes lie side by side. On the horizontal
/// highway the lanes are its rows, top to bottom.
struct Highway {
    static let pixelsPerSecond = 125.0
    /// The vertical highways: `width` wide, from the top of the screen to `bottom`.
    static let width = 200
    static let bottom = 212
    /// The four-lane highway's lanes.
    static let laneWidth = 50
    // The horizontal highway: rows between `rowsTop` and `rowsBottom`, the panel
    // in miniature left of each row, the notes running left from the screen's edge.
    static let padMapWidth = 32
    static let rowsTop = 32
    static let rowsBottom = 218
    static let maxRowHeight = 32

    /// A note on the highway now.
    struct Note {
        let index: Int
        let lane: Int
        /// Where its time is along the highway.
        let position: Int
        let state: NoteJudgmentState
        let voice: DrumVoice
        /// Its slot after the player's pad assignment; its row tells which half of a
        /// four-lane note is lit.
        let target: DrumTarget
    }

    let layout: HighwayLayout
    /// The pads each lane shows, in order across: on the four-lane highway the pads
    /// of its pad column that have a voice, else one pad each.
    let lanes: [[Int]]
    /// Where lane 0 starts across, and each lane's size across.
    let laneStart: Int
    let laneSize: Int
    /// Along the highway: where time 0 is, where the notes come from and where they
    /// go to.
    let strike: Int
    private let comesFrom: Int
    private let goesTo: Int

    /// `chartPads`: the pads the chart's notes fall on, as `chartPads(of:kit:)`
    /// finds them.
    init(layout: HighwayLayout, strikeLine: StrikeLinePosition, chartPads: [Int], kit: DrumKit, screenWidth: Int = 320) {
        self.layout = layout
        switch layout {
        case .vertical:
            lanes = (0..<4).map { lane in
                (0..<DrumKit.padCount).filter { DrumKit.layoutTarget(forPad: $0).lane == lane && kit.voice(forPad: $0) != .off }
            }
            laneStart = 0
            laneSize = Self.laneWidth
        case .verticalByPad:
            let pads = Self.padLanes(chartPads)
            lanes = pads.map { [$0] }
            laneSize = Self.width / max(pads.count, 1)
            laneStart = (Self.width - laneSize * pads.count) / 2
        case .horizontal:
            lanes = chartPads.map { [$0] }
            laneSize = min(Self.maxRowHeight, (Self.rowsBottom - Self.rowsTop) / max(chartPads.count, 1))
            laneStart = Self.rowsTop + (Self.rowsBottom - Self.rowsTop - laneSize * chartPads.count) / 2
        }
        switch layout {
        case .vertical, .verticalByPad:
            strike = Self.strikeY(for: strikeLine)
            comesFrom = 0
            goesTo = Self.bottom
        case .horizontal:
            strike = Self.strikeX(for: strikeLine, width: screenWidth)
            comesFrom = screenWidth
            goesTo = Self.padMapWidth
        }
    }

    /// Where lane `lane` starts across.
    func laneOrigin(_ lane: Int) -> Int {
        laneStart + lane * laneSize
    }

    /// The size across of all lanes together.
    var lanesSize: Int {
        laneSize * lanes.count
    }

    /// Where chart time `t` lies along the highway when it is `time`.
    func position(of t: Double, at time: Double) -> Int {
        let offset = Int(((t - time) * Self.pixelsPerSecond).rounded())
        return comesFrom < goesTo ? strike - offset : strike + offset
    }

    /// The beat lines on the highway at `time`, as positions along it.
    func beats(_ beatTimes: [Double], at time: Double) -> [Int] {
        let window = self.window(at: time)
        return beatTimes.filter { $0 > window.from && $0 < window.to }.map { position(of: $0, at: time) }
    }

    /// The notes on the highway at `time`, in time order. On the by-pad and
    /// horizontal highways only those of a pad with a lane.
    func notes(of session: GameSession, at time: Double) -> [Note] {
        let notes = session.chart.notes
        let window = self.window(at: time)
        var index = Self.firstNote(in: notes, from: window.from)
        var shown: [Note] = []
        while index < notes.count, notes[index].timeSec < window.to {
            defer { index += 1 }
            let target = session.target(ofNote: index)
            guard let lane = lane(of: target) else { continue }
            shown.append(Note(index: index, lane: lane, position: position(of: notes[index].timeSec, at: time),
                              state: session.state(ofNote: index), voice: session.voice(ofNote: index), target: target))
        }
        return shown
    }

    /// The lane a slot's notes run in.
    func lane(of target: DrumTarget) -> Int? {
        switch layout {
        case .vertical: target.lane
        case .verticalByPad, .horizontal: lanes.firstIndex(of: [DrumKit.pad(forLayout: target)])
        }
    }

    /// The span of chart time on the highway at `time`: from what has just passed
    /// its end to what is about to come in.
    private func window(at time: Double) -> (from: Double, to: Double) {
        let future = Double(abs(strike - comesFrom)) / Self.pixelsPerSecond
        let past = Double(abs(goesTo - strike)) / Self.pixelsPerSecond
        return (time - past, time + future)
    }

    /// The index of the first of `notes` (in time order) at or after `time`.
    private static func firstNote(in notes: [DrumNoteEvent], from time: Double) -> Int {
        var low = 0, high = notes.count
        while low < high {
            let mid = (low + high) / 2
            if notes[mid].timeSec < time { low = mid + 1 } else { high = mid }
        }
        return low
    }

    // MARK: - Strike line

    /// The y of the vertical highways' strike line: near their bottom, or a
    /// quarter, a third or half way up.
    static func strikeY(for position: StrikeLinePosition) -> Int {
        switch position {
        case .edge: return bottom - 14
        case .quarter: return bottom - bottom / 4
        case .third: return bottom - bottom / 3
        case .middle: return bottom / 2
        }
    }

    /// The x of the horizontal highway's strike line: near its left end, or a
    /// quarter, a third or half way along it.
    static func strikeX(for position: StrikeLinePosition, width: Int = 320) -> Int {
        let length = width - padMapWidth
        switch position {
        case .edge: return padMapWidth + 42
        case .quarter: return padMapWidth + length / 4
        case .third: return padMapWidth + length / 3
        case .middle: return padMapWidth + length / 2
        }
    }

    // MARK: - Pads

    /// The pads a chart's notes fall on, as the horizontal highway's rows from the
    /// top: cymbals at the top and the kick at the bottom, as in drum notation.
    /// Every pad with a voice when the chart has no notes.
    static func chartPads(of session: GameSession, kit: DrumKit) -> [Int] {
        let order: [DrumVoice] = [.orange, .blue, .yellow, .red, .green, .kick]
        let used = Set(session.chart.notes.indices.map { DrumKit.pad(forLayout: session.target(ofNote: $0)) })
        let pads = (0..<DrumKit.padCount).filter { kit.voice(forPad: $0) != .off && (used.isEmpty || used.contains($0)) }
        return pads.sorted { (order.firstIndex(of: kit.voice(forPad: $0)) ?? order.count, $0) < (order.firstIndex(of: kit.voice(forPad: $1)) ?? order.count, $1) }
    }

    /// The lanes of the by-pad highway, left to right as the pads sit on the panel:
    /// by column, the upper panel row's pad first.
    static func padLanes(_ pads: [Int]) -> [Int] {
        func place(_ pad: Int) -> (Int, Int) {
            let target = DrumKit.layoutTarget(forPad: pad)
            return (target.lane, target.row == PanelPads.rowOnTop ? 0 : 1)
        }
        return pads.sorted { place($0) < place($1) }
    }
}
