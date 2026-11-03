/// Where the app is between start and exit. Every way out sets one of the two end
/// states through `BeatTrainApp.quit(powerOff:)`, which stops the song and saves
/// the settings first.
enum Lifecycle: Equatable {
    case running
    /// The power key was pressed: "Do you want to shut down?" is on screen.
    case askingToShutDown
    /// Back to the stock app (SHIFT+STOP, or a stop signal).
    case quitting
    /// YES to the question: the app exits and `session.sh` powers the MPC off.
    case poweringOff

    var isOver: Bool {
        self == .quitting || self == .poweringOff
    }

    /// The exit code `packaging/autorun/session.sh` reads: 10 powers the MPC off.
    var exitCode: Int32 {
        self == .poweringOff ? 10 : 0
    }
}
