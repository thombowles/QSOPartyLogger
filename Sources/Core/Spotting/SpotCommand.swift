import Foundation

/// Which station the spot command means.
///
/// One shortcut, not two. Two spot commands a single modifier apart is how a
/// sheet ends up open with your own call in it mid-QSO, so the operating mode
/// decides instead — the same mode that already picks the message set, and the
/// one thing that actually distinguishes the two cases. Running means
/// advertising your own frequency; searching means putting the station you
/// just found on the board.
///
/// Pure, so the branch is testable without a view: `MainView` only routes.
enum SpotCommand: Equatable, Sendable {
    /// Calling CQ — the spot is your own run.
    case myself
    /// Searching, with a call copied.
    case station(String)
    /// Searching, with nothing copied yet. The sheet opens anyway, empty, the
    /// way it already opens on a blank frequency: the operator finishes it.
    case blankStation

    static func target(mode: OperatingMode, entryCall: String) -> SpotCommand {
        // Run ignores the call field entirely. An operator calling CQ with a
        // half-copied call in it still means their own run, and guessing
        // otherwise would bring back the ambiguity this command removes.
        guard mode == .searchPounce else { return .myself }
        let call = entryCall.trimmingCharacters(in: .whitespaces).uppercased()
        return call.isEmpty ? .blankStation : .station(call)
    }
}
